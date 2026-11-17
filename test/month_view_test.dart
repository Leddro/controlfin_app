import 'package:financas_app/main.dart';
import 'package:financas_app/models/credit_card.dart';
import 'package:financas_app/models/tx.dart';
import 'package:financas_app/services/tx_service.dart';
import 'package:financas_app/widgets/summary_card.dart';
import 'package:financas_app/widgets/upcoming_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

const nubank = CreditCard(
    id: 'nu',
    bank: 'Nubank',
    last4: '1234',
    closingDay: 1,
    dueDay: 9,
    color: 0xFF820AD1);

Tx credit(String id, DateTime date, DateTime bill, double amount,
        {int index = 1, int count = 1, String? group}) =>
    Tx(
      id: id,
      type: TxType.expense,
      amount: amount,
      category: 'Compras',
      description: id,
      date: date,
      payment: PaymentMethod.credit,
      cardId: 'nu',
      billDate: bill,
      index: index,
      count: count,
      groupId: group,
      kind: count > 1 ? TxKind.installment : TxKind.single,
    );

void main() {
  setUpAll(() => initializeDateFormatting('pt_BR'));

  final nov = DateTime(2026, 11);
  // Compra de novembro paga em dezembro.
  final tenis =
      credit('tenis', DateTime(2026, 11, 20), DateTime(2026, 12, 9), 300);
  // Fone em 3x comprado em novembro: dez, jan e fev.
  final fone = [
    for (var i = 0; i < 3; i++)
      credit('fone', DateTime(2026, 11, 10), DateTime(2026, 12 + i, 9), 50,
          index: i + 1, count: 3, group: 'g1'),
  ];
  // Parcela de compra antiga que também vence em dezembro.
  final antiga = credit(
      'antiga', DateTime(2026, 9, 5), DateTime(2026, 12, 9), 80,
      index: 3, count: 4);
  final pix = Tx(
      id: 'pix',
      type: TxType.expense,
      amount: 40,
      category: 'Outros',
      description: 'pix',
      date: DateTime(2026, 11, 3),
      payment: PaymentMethod.debit);

  MonthView view() => buildMonthView(
        nov,
        [pix, tenis, ...fone],
        const [],
        [tenis, fone.first, antiga],
      );

  test('compras de novembro no crédito ficam à parte do mês', () {
    final v = view();
    expect(v.counted.map((t) => t.id), ['pix']);
    expect(v.deferred.map((t) => t.id), ['tenis', 'fone', 'fone', 'fone']);
    expect(v.deferredTotal, 450);
    expect(v.nextMonthTotal, 430);
  });

  testWidgets('bloco "Já comprometido" explica de onde vem o valor',
      (tester) async {
    var opened = false;
    await tester.pumpWidget(FinancasApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: UpcomingCard(
            month: nov,
            view: view(),
            cards: const [nubank],
            onOpenNextMonth: () => opened = true,
          ),
        ),
      ),
    ));
    expect(find.text('Já comprometido em Dezembro'), findsOneWidget);
    expect(find.textContaining('430,00'), findsOneWidget);
    expect(find.text('Compras feitas em novembro'), findsOneWidget);
    expect(find.textContaining('350,00'), findsOneWidget); // 300 + 50
    expect(find.text('Parcelas e compras anteriores'), findsOneWidget);
    expect(find.textContaining('80,00'), findsOneWidget);
    // As 2 parcelas do fone depois de dezembro.
    expect(find.textContaining('100,00'), findsOneWidget);
    await tester.tap(find.text('Ver dezembro'));
    expect(opened, isTrue);
  });

  test('sem nada no crédito, o bloco não aparece', () {
    expect(UpcomingCard.hasContent(MonthView(counted: [pix])), isFalse);
  });

  testWidgets('resumo centralizado cabe numa tela estreita', (tester) async {
    tester.view.physicalSize = const Size(320 * 3, 600 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(FinancasApp(
      home: Scaffold(
        body: SummaryCard(txs: [
          Tx(
              type: TxType.income,
              amount: 12345.67,
              category: 'Salário',
              description: '',
              date: DateTime(2026, 11, 5)),
          pix,
          credit('c', DateTime(2026, 10, 20), DateTime(2026, 11, 9), 9876.54),
        ]),
      ),
    ));
    expect(tester.takeException(), isNull);
    final label = tester.getCenter(find.text('Entradas'));
    final value = tester.getCenter(find.textContaining('12.345,67'));
    expect((label.dx - value.dx).abs(), lessThan(1));
  });
}
