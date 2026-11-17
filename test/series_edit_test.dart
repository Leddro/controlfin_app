import 'package:financas_app/models/credit_card.dart';
import 'package:financas_app/models/tx.dart';
import 'package:flutter_test/flutter_test.dart';

const nubank = CreditCard(
    id: 'nu', bank: 'Nubank', closingDay: 1, dueDay: 9, color: 0xFF820AD1);

/// Compra parcelada antiga, lançada no débito: uma data por mês.
List<Tx> debitSeries({int count = 4, double amount = 100}) => [
      for (var i = 1; i <= count; i++)
        Tx(
          id: 'p$i',
          type: TxType.expense,
          amount: amount,
          category: 'Outros',
          description: 'Geladeira',
          date: DateTime(2026, 9 + i, 10),
          groupId: 'g',
          kind: TxKind.installment,
          index: i,
          count: count,
          payment: PaymentMethod.debit,
        ),
    ];

/// O que o formulário devolve ao editar a parcela [k] para o cartão com a
/// compra em [purchase]: a fatura da parcela k é a k-ésima depois da compra.
Tx editToCard(Tx t, DateTime purchase, {double? amount}) => t.copyWith(
      amount: amount,
      date: purchase,
      payment: () => PaymentMethod.credit,
      cardId: () => 'nu',
      billDate: () => addMonths(nubank.dueForPurchase(purchase), t.index - 1),
    );

void main() {
  test('somar e voltar meses atravessando o ano', () {
    expect(addMonths(DateTime(2027, 1, 9), -2), DateTime(2026, 11, 9));
    expect(addMonths(DateTime(2027, 1, 9), -13), DateTime(2025, 12, 9));
    expect(addMonths(DateTime(2026, 11, 9), 3), DateTime(2027, 2, 9));
    expect(addMonths(DateTime(2026, 1, 31), 1), DateTime(2026, 2, 28));
    expect(addMonths(DateTime(2026, 3, 31), -1), DateTime(2026, 2, 28));
  });

  group('editar uma parcela edita a compra', () {
    test('parcelas acompanham a data da compra, cada uma na sua fatura', () {
      final series = debitSeries();
      // Abriu a parcela 3 e informou a compra de 15/10/2026.
      final edited = editToCard(series[2], DateTime(2026, 10, 15));
      final result = rebuildInstallments(edited, series, oldAmount: 100);

      expect(result.every((t) => t.isCredit && t.cardId == 'nu'), isTrue);
      expect(result.every((t) => t.date == DateTime(2026, 10, 15)), isTrue);
      expect(result.map((t) => t.billDate), [
        DateTime(2026, 11, 9),
        DateTime(2026, 12, 9),
        DateTime(2027, 1, 9),
        DateTime(2027, 2, 9),
      ]);
    });

    test('a parcela editada não é empurrada para frente', () {
      // Relato: a parcela de março (6/6) foi parar em novembro e vice-versa.
      // Compra em 20/09: a 6ª parcela tem que cair na fatura de março.
      final series = debitSeries(count: 6);
      final edited = editToCard(series[5], DateTime(2026, 9, 20));
      expect(edited.billDate, DateTime(2027, 3, 9));
      final result = rebuildInstallments(edited, series, oldAmount: 100);
      expect(result.first.billDate, DateTime(2026, 10, 9));
      expect(result.last.billDate, DateTime(2027, 3, 9));
    });

    test('mover a fatura de uma parcela move as outras junto', () {
      final series = debitSeries();
      final moved = editToCard(series[1], DateTime(2026, 10, 15))
          .copyWith(billDate: () => DateTime(2027, 1, 9));
      final result = rebuildInstallments(moved, series, oldAmount: 100);
      expect(result.map((t) => t.billDate?.month), [12, 1, 2, 3]);
    });

    test('série já quebrada (datas iguais e erradas) é corrigida', () {
      // Estado deixado pela versão anterior: todas com a data da parcela 3.
      final broken = [
        for (final t in debitSeries())
          t.copyWith(
            date: DateTime(2026, 12, 10),
            payment: () => PaymentMethod.credit,
            cardId: () => 'nu',
            billDate: () => DateTime(2027, t.index, 9),
          ),
      ];
      final fixed = rebuildInstallments(
          editToCard(broken[0], DateTime(2026, 10, 15)), broken,
          oldAmount: 100);
      expect(fixed.every((t) => t.date == DateTime(2026, 10, 15)), isTrue);
      expect(fixed.map((t) => t.billDate?.month), [11, 12, 1, 2]);
    });

    test('valor novo vale para as parcelas iguais; ajuste de centavos fica',
        () {
      final series = debitSeries(count: 3);
      final cents = [
        series[0].copyWith(amount: 33.34),
        series[1].copyWith(amount: 33.33),
        series[2].copyWith(amount: 33.33),
      ];
      final result = rebuildInstallments(cents[1].copyWith(amount: 40), cents,
          oldAmount: 33.33);
      expect(result.map((t) => t.amount), [33.34, 40, 40]);
    });

    test('voltar para débito: cada parcela um mês depois da anterior', () {
      final credit = rebuildInstallments(
          editToCard(debitSeries()[0], DateTime(2026, 10, 15)), debitSeries());
      final back = rebuildInstallments(
        credit[2].copyWith(
          date: DateTime(2026, 12, 10),
          payment: () => PaymentMethod.debit,
          cardId: () => null,
          billDate: () => null,
        ),
        credit,
      );
      expect(back.map((t) => t.date), [
        DateTime(2026, 10, 10),
        DateTime(2026, 11, 10),
        DateTime(2026, 12, 10),
        DateTime(2027, 1, 10),
      ]);
      expect(back.every((t) => !t.isCredit && t.billDate == null), isTrue);
    });

    test('parcela importada sozinha (sem série) também funciona', () {
      final single = debitSeries()[2].copyWith(groupId: null);
      final result = rebuildInstallments(
          editToCard(single, DateTime(2026, 10, 15)), [single]);
      expect(result.single.billDate, DateTime(2027, 1, 9));
    });
  });

  group('lançamento mensal', () {
    final monthly = [
      for (var i = 1; i <= 3; i++)
        Tx(
          id: 'm$i',
          type: TxType.expense,
          amount: 39.9,
          category: 'Lazer',
          description: 'Streaming',
          date: DateTime(2026, 10 + i, 5),
          groupId: 'r',
          kind: TxKind.recurring,
          index: i,
          count: 3,
        ),
    ];

    test('cada mês mantém a data e vai para a fatura do seu mês', () {
      final edited = monthly[0].copyWith(
        payment: () => PaymentMethod.credit,
        cardId: () => 'nu',
        billDate: () => DateTime(2026, 12, 9),
      );
      final result = applyToSeries(edited, monthly);
      expect(result.map((t) => t.date), monthly.map((t) => t.date));
      expect(result.map((t) => t.billDate?.month), [12, 1, 2]);
    });

    test('detecta o que vale levar para os outros meses', () {
      final t = monthly[0];
      expect(changesSeries(t, t.copyWith(amount: 49.9)), isFalse);
      expect(changesSeries(t, t.copyWith(payment: () => PaymentMethod.credit)),
          isTrue);
    });
  });
}
