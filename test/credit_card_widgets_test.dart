import 'dart:typed_data';

import 'package:financas_app/main.dart';
import 'package:financas_app/models/credit_card.dart';
import 'package:financas_app/models/tx.dart';
import 'package:financas_app/services/pdf_import_service.dart';
import 'package:financas_app/widgets/invoices_card.dart';
import 'package:financas_app/widgets/pdf_import_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'statement_import_test.dart' show nubankPdfText;

const nubank = CreditCard(
  id: 'nu',
  bank: 'Nubank',
  last4: '1234',
  closingDay: 1,
  dueDay: 9,
  color: 0xFF820AD1,
);

/// Abre a revisão da importação; o futuro completa quando ela fecha.
Future<Future<List<Tx>?>> openImport(
  WidgetTester tester, {
  required String text,
  List<CreditCard> cards = const [],
  Future<CreditCard> Function(CreditCard)? onCreateCard,
}) async {
  late Future<List<Tx>?> result;
  await tester.binding.setSurfaceSize(const Size(500, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(FinancasApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => FilledButton(
          onPressed: () {
            result = showModalBottomSheet<List<Tx>>(
              context: context,
              isScrollControlled: true,
              builder: (_) => ImportReviewSheet(
                bytes: Uint8List(0),
                defaultDate: DateTime(2026, 12, 1),
                parser: (_, __) async =>
                    PdfImportService.parseStatementText(text),
                cards: cards,
                onCreateCard: onCreateCard,
              ),
            );
          },
          child: const Text('abrir'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
  return result;
}

Future<void> tapSave(WidgetTester tester) async {
  final save = find.textContaining('Salvar 4 lançamentos');
  await tester.ensureVisible(save);
  await tester.tap(save);
  await tester.pumpAndSettle();
}

const nubankText = 'Nu Pagamentos S.A.\n$nubankPdfText';

void main() {
  setUpAll(() => initializeDateFormatting('pt_BR'));

  testWidgets('cartão cadastrado: reconhece, lança na fatura e nas próximas',
      (tester) async {
    final result =
        await openImport(tester, text: nubankText, cards: const [nubank]);

    expect(find.text('Nubank •1234'), findsOneWidget);
    expect(find.text('Reconhecido'), findsOneWidget);
    expect(find.text('09/01/2027'), findsOneWidget);
    expect(find.textContaining('Janeiro, mês do vencimento'), findsOneWidget);
    expect(find.textContaining('confere com os lançamentos'), findsNothing);

    await tapSave(tester);
    final txs = (await result)!;

    // 4 itens: 2 à vista + "Parcela 3/12" (+9) + "Pcl2de12" (+10).
    expect(txs, hasLength(4 + 9 + 10));
    expect(txs.every((t) => t.isCredit && t.cardId == 'nu'), isTrue);
    final escola = txs.where((t) => t.description == 'Escola Online').toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    expect(escola.first.billDate, DateTime(2027, 1, 9));
    expect(escola.first.index, 3);
    expect(escola.last.index, 12);
    expect(escola.last.billDate, DateTime(2027, 10, 9));
    expect(escola.map((t) => t.groupId).toSet(), hasLength(1));
    final uber = txs.singleWhere((t) => t.description == 'Uberrides');
    expect(uber.date, DateTime(2026, 12, 28));
    expect(uber.cashDate, DateTime(2027, 1, 9));
  });

  testWidgets('cartão novo: pede para conferir as datas antes de salvar',
      (tester) async {
    final created = <CreditCard>[];
    final result = await openImport(
      tester,
      text: nubankText,
      onCreateCard: (card) async {
        final saved = card.copyWith(id: 'novo');
        created.add(saved);
        return saved;
      },
    );

    expect(find.text('Novo • confira as datas'), findsOneWidget);
    await tapSave(tester);

    // Abriu o cadastro com o que veio da fatura.
    expect(find.text('Novo cartão de crédito'), findsOneWidget);
    expect(find.text('Encontramos na fatura'), findsOneWidget);
    expect(find.text('Dia 1'), findsOneWidget); // fechamento
    expect(find.text('Dia 9'), findsOneWidget); // vencimento
    final saveCard = find.text('Salvar cartão');
    await tester.ensureVisible(saveCard);
    await tester.tap(saveCard);
    await tester.pumpAndSettle();

    // Confirmado o cartão, a importação continua e salva sozinha.
    final txs = (await result)!;
    expect(created.single.bank, 'Nubank');
    expect(created.single.last4, '1234');
    expect(created.single.closingDay, 1);
    expect(created.single.dueDay, 9);
    expect(txs.every((t) => t.cardId == 'novo'), isTrue);
  });

  testWidgets('extrato da conta: salva como débito/Pix sem fatura',
      (tester) async {
    final result =
        await openImport(tester, text: nubankText, cards: const [nubank]);
    await tester.tap(find.text('Extrato da conta'));
    await tester.pumpAndSettle();
    await tapSave(tester);
    final txs = (await result)!;
    expect(txs, hasLength(4));
    expect(txs.every((t) => !t.isCredit && t.billDate == null), isTrue);
  });

  testWidgets('faturas do mês: total por cartão e status', (tester) async {
    String? selected;
    final txs = [
      Tx(
          id: 'a',
          type: TxType.expense,
          amount: 100,
          category: 'Outros',
          description: 'a',
          date: DateTime(2026, 11, 20),
          payment: PaymentMethod.credit,
          cardId: 'nu',
          billDate: DateTime(2026, 12, 9)),
      Tx(
          id: 'b',
          type: TxType.expense,
          amount: 50,
          category: 'Outros',
          description: 'b',
          date: DateTime(2026, 12, 2),
          payment: PaymentMethod.debit),
    ];
    await tester.pumpWidget(FinancasApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: InvoicesCard(
            month: DateTime(2026, 12),
            txs: txs,
            cards: const [nubank],
            today: DateTime(2026, 12, 4),
            onSelectCard: (id) => selected = id,
            onManage: () {},
            onAddCard: () {},
          ),
        ),
      ),
    ));
    expect(find.text('Nubank •1234'), findsOneWidget);
    expect(find.text('Fechada • vence em 5 dias'), findsOneWidget);
    expect(find.textContaining('100,00'), findsNWidgets(2)); // cartão e total
    await tester.tap(find.text('Nubank •1234'));
    expect(selected, 'nu');
  });

  testWidgets('sem cartões: convite para cadastrar', (tester) async {
    var added = false;
    await tester.pumpWidget(FinancasApp(
      home: Scaffold(
        body: InvoicesCard(
          month: DateTime(2026, 12),
          txs: const [],
          cards: const [],
          onSelectCard: (_) {},
          onManage: () {},
          onAddCard: () => added = true,
        ),
      ),
    ));
    await tester.tap(find.text('Adicionar cartão'));
    expect(added, isTrue);
  });
}
