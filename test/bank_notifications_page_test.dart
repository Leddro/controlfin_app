import 'package:financas_app/main.dart';
import 'package:financas_app/models/bank_notification.dart';
import 'package:financas_app/models/credit_card.dart';
import 'package:financas_app/models/tx.dart';
import 'package:financas_app/models/user_settings.dart';
import 'package:financas_app/pages/bank_notifications_page.dart';
import 'package:financas_app/services/bank_notification_service.dart';
import 'package:financas_app/widgets/bank_inbox_banner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';

/// Guarda as notificações na memória, no lugar do canal nativo.
class FakeService extends BankNotificationService {
  final List<Map<String, dynamic>> items;
  final updates = <String, Map<String, Object?>>{};

  FakeService(this.items);

  @override
  Future<NotificationAccess> status() async =>
      const NotificationAccess(listener: true, post: true, battery: false);

  @override
  Future<List<CapturedNotification>> list() async =>
      [for (final m in items) CapturedNotification.fromMap(m)];

  @override
  Future<void> update(String id, Map<String, Object?> fields) async {
    updates[id] = fields;
    final item = items.firstWhere((m) => m['id'] == id);
    fields.forEach((k, v) => v == null ? item.remove(k) : item[k] = v);
  }

  @override
  Future<bool> takeOpenInbox() async => false;
}

Map<String, dynamic> item(String id, String title, String text,
        {String package = 'com.nu.production', int minute = 47}) =>
    {
      'id': id,
      'package': package,
      'title': title,
      'text': text,
      'postedAt': DateTime(2026, 11, 18, 12, minute).millisecondsSinceEpoch,
    };

const nubank = CreditCard(
    id: 'nu',
    bank: 'Nubank',
    last4: '4821',
    closingDay: 1,
    dueDay: 9,
    color: 0xFF820AD1);

Future<void> pumpPage(WidgetTester tester, FakeService service,
    {List<Tx>? saved}) async {
  tester.view.physicalSize = const Size(412 * 3, 1800 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(FinancasApp(
    home: BankNotificationsPage(
      service: service,
      cards: Stream.value(const [nubank]),
      settings: Stream.value(const UserSettings()),
      save: (txs) async => saved?.addAll(txs),
      loadExisting: (_, __) async => const [],
      deleteTx: (_) async {},
      avatar: const CircleAvatar(radius: 17),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting('pt_BR'));

  testWidgets('confirma a compra no crédito no cartão certo', (tester) async {
    final service = FakeService([
      item('a', 'Compra no crédito aprovada',
          'Compra de R\$ 3.661,11 APROVADA em CASASBAHIACOM para o cartão com final 4821.'),
      item('b', 'Carlos, deposite R\$50 e receba R\$50', 'Aceite o desafio.',
          package: 'com.mercadopago.wallet'),
    ]);
    final saved = <Tx>[];
    await pumpPage(tester, service, saved: saved);

    expect(find.text('Para confirmar (1)'), findsOneWidget);
    expect(find.text('Compra no crédito'), findsOneWidget);
    expect(
        find.textContaining('fatura que vence em 09/12/2026'), findsOneWidget);

    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();

    final tx = saved.single;
    expect(tx.amount, 3661.11);
    expect(tx.description, 'Casasbahiacom');
    expect(tx.isCredit, isTrue);
    expect(tx.cardId, 'nu');
    expect(tx.billDate, DateTime(2026, 12, 9));
    expect(service.updates['a'], {'status': 'confirmed'});
    expect(find.text('Para confirmar (0)'), findsOneWidget);
  });

  testWidgets('Pix recebido vira ganho', (tester) async {
    final service = FakeService([
      item('p', 'Transferência recebida',
          'Você recebeu uma transferência de R\$ 1000,00 de PAGFAST'),
    ]);
    final saved = <Tx>[];
    await pumpPage(tester, service, saved: saved);
    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();
    expect(saved.single.type, TxType.income);
    expect(saved.single.description, 'Pix de Pagfast');
    expect(saved.single.payment, isNull);
  });

  testWidgets('usuário comum não vê a validação', (tester) async {
    final service = FakeService([
      item('a', 'Transferência recebida',
          'Você recebeu uma transferência de R\$ 0,01 de Joao Pereira.'),
    ]);
    await pumpPage(tester, service);
    expect(find.text('Para confirmar (1)'), findsOneWidget);
    expect(find.textContaining('Validar'), findsNothing);
    expect(find.text('Certo'), findsNothing);
  });

  testWidgets('aviso na Início com a contagem', (tester) async {
    final service = FakeService([
      item('a', 'Compra no débito aprovada', 'Compra de R\$ 17,00 em ACADEMIA'),
      item('b', '', 'Pix enviado: R\$ 39,75 para MARIA'),
    ]);
    await tester.pumpWidget(
        FinancasApp(home: Scaffold(body: BankInboxBanner(service: service))));
    await tester.pumpAndSettle();
    expect(
        find.text('2 movimentações dos bancos para confirmar'), findsOneWidget);
  });

  testWidgets('sem nada pendente o aviso não aparece', (tester) async {
    final service = FakeService([]);
    await tester.pumpWidget(
        FinancasApp(home: Scaffold(body: BankInboxBanner(service: service))));
    await tester.pumpAndSettle();
    expect(find.byType(InkWell), findsNothing);
  });
}
