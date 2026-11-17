import 'package:financas_app/models/credit_card.dart';
import 'package:financas_app/models/tx.dart';
import 'package:financas_app/services/invoice_detection.dart';
import 'package:financas_app/services/pdf_import_service.dart';
import 'package:financas_app/services/tx_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'statement_import_test.dart' show nubankPdfText;

CreditCard card({int closing = 1, int due = 9, String? last4 = '1234'}) =>
    CreditCard(
      id: 'c1',
      bank: 'Nubank',
      last4: last4,
      closingDay: closing,
      dueDay: due,
      color: 0xFF820AD1,
    );

Tx tx(String id, DateTime date,
        {PaymentMethod? payment, DateTime? bill, int index = 1}) =>
    Tx(
      id: id,
      type: TxType.expense,
      amount: 10,
      category: 'Outros',
      description: id,
      date: date,
      payment: payment,
      billDate: bill,
      index: index,
    );

void main() {
  group('ciclo da fatura', () {
    test('fecha dia 1 e vence dia 9: mesma fatura do mês', () {
      final c = card();
      expect(c.dueForPurchase(DateTime(2026, 11, 20)), DateTime(2026, 12, 9));
      // No dia do fechamento a compra já vai para a próxima.
      expect(c.dueForPurchase(DateTime(2026, 12, 1)), DateTime(2027, 1, 9));
      expect(c.closingForDue(DateTime(2026, 12, 9)), DateTime(2026, 12, 1));
    });

    test('fecha dia 28 e vence dia 5: vencimento no mês seguinte', () {
      final c = card(closing: 28, due: 5);
      expect(c.dueForPurchase(DateTime(2026, 11, 27)), DateTime(2026, 12, 5));
      expect(c.dueForPurchase(DateTime(2026, 11, 28)), DateTime(2027, 1, 5));
      expect(c.closingForDue(DateTime(2027, 1, 5)), DateTime(2026, 12, 28));
      final (from, to) = c.purchaseWindow(DateTime(2027, 1, 5));
      expect(from, DateTime(2026, 11, 28));
      expect(to, DateTime(2026, 12, 27));
    });

    test('dia 31 em mês curto usa o último dia', () {
      final c = card(closing: 31, due: 10);
      expect(c.dueForPurchase(DateTime(2027, 2, 27)), DateTime(2027, 3, 10));
      expect(c.dueForPurchase(DateTime(2027, 2, 28)), DateTime(2027, 4, 10));
    });
  });

  group('parcelas no crédito', () {
    test('cada parcela vai para a fatura seguinte com a data da compra', () {
      final list = buildSeries(
        type: TxType.expense,
        amount: 50,
        category: 'Compras',
        description: 'Fone',
        start: DateTime(2026, 11, 20),
        kind: TxKind.installment,
        count: 3,
        perInstallment: true,
        payment: PaymentMethod.credit,
        cardId: 'c1',
        firstBill: DateTime(2026, 12, 9),
      );
      expect(list.map((t) => t.billDate), [
        DateTime(2026, 12, 9),
        DateTime(2027, 1, 9),
        DateTime(2027, 2, 9),
      ]);
      expect(list.every((t) => t.date == DateTime(2026, 11, 20)), isTrue);
      expect(list.map((t) => t.cashDate.month), [12, 1, 2]);
      expect(list.every((t) => t.cardId == 'c1'), isTrue);
    });

    test('no débito não grava cartão nem fatura', () {
      final list = buildSeries(
        type: TxType.expense,
        amount: 30,
        category: 'Outros',
        description: 'Pix',
        start: DateTime(2026, 11, 20),
        kind: TxKind.single,
        payment: PaymentMethod.debit,
        cardId: 'c1',
        firstBill: DateTime(2026, 12, 9),
      );
      expect(list.single.cardId, isNull);
      expect(list.single.billDate, isNull);
      expect(list.single.cashDate, DateTime(2026, 11, 20));
    });
  });

  test('mês pela data em que o dinheiro sai', () {
    final byDate = [
      tx('pix', DateTime(2026, 12, 3), payment: PaymentMethod.debit),
      tx('antigo', DateTime(2026, 12, 4)),
      // Comprado em dezembro, mas a fatura vence em janeiro: fica de fora.
      tx('cartao-dez', DateTime(2026, 12, 5),
          payment: PaymentMethod.credit, bill: DateTime(2027, 1, 9)),
    ];
    final byBill = [
      tx('cartao-nov', DateTime(2026, 11, 20),
          payment: PaymentMethod.credit, bill: DateTime(2026, 12, 9)),
    ];
    final ids = mergeCashMonth(byDate, byBill).map((t) => t.id).toList();
    expect(ids, ['antigo', 'pix', 'cartao-nov']);
  });

  group('reconhecer a fatura', () {
    test('Nubank em PDF: banco, final, vencimento, fechamento e total', () {
      final info = detectInvoice('Nu Pagamentos S.A.\n$nubankPdfText');
      expect(info.bank?.name, 'Nubank');
      expect(info.last4, '1234');
      expect(info.dueDate, DateTime(2027, 1, 9));
      expect(info.closingDate, DateTime(2027, 1, 1));
      expect(info.total, 512.40);
      expect(info.isAccountStatement, isFalse);
    });

    test('formato de outros bancos, com datas numéricas', () {
      const text = '''
Itaú Unibanco - Itaucard Platinum
Cartão final 9876
Vencimento 15/12/2026
Data de fechamento: 07/12/2026
Total desta fatura R\$ 1.234,56
''';
      final info = detectInvoice(text);
      expect(info.bank?.name, 'Itaú');
      expect(info.last4, '9876');
      expect(info.dueDate, DateTime(2026, 12, 15));
      expect(info.closingDate, DateTime(2026, 12, 7));
      expect(info.total, 1234.56);
    });

    test('vencimento escrito por extenso e fechamento estimado', () {
      final info = detectInvoice(
          'Banco Inter\nSua fatura vence em 10 de dezembro de 2026');
      expect(info.bank?.name, 'Inter');
      expect(info.dueDate, DateTime(2026, 12, 10));
      expect(info.closingDate, isNull);
      expect(info.suggestedClosingDay, 3);
      expect(info.closingIsEstimated, isTrue);
    });

    test('CSV do Nubank: banco e vencimento pelo nome do arquivo', () {
      final info = detectInvoice('date,title,amount\n2026-12-01,Loja,10.00',
          fileName: 'Nubank_2027-01-09.csv');
      expect(info.bank?.name, 'Nubank');
      expect(info.dueDate, DateTime(2027, 1, 9));
    });

    test('extrato de conta não é fatura', () {
      final info = detectInvoice(
          'Data,Valor,Identificador,Descrição\n01/12/2026,-50.00,abc,Pix');
      expect(info.isAccountStatement, isTrue);
    });

    test('o texto do PDF devolve itens e dados juntos', () {
      final parsed = PdfImportService.parseStatementText(nubankPdfText);
      expect(parsed.items, hasLength(4));
      expect(parsed.info.dueDate, DateTime(2027, 1, 9));
    });
  });

  group('achar o cartão cadastrado', () {
    final nu = card();
    final nu2 = card(last4: '5555').copyWith(id: 'c2');
    const itau =
        CreditCard(id: 'c3', bank: 'Itaú', closingDay: 7, dueDay: 15, color: 0);

    test('pelo final', () {
      expect(matchCard([nu, nu2, itau], last4: '5555')?.id, 'c2');
    });
    test('pelo banco quando só há um cartão dele', () {
      expect(matchCard([nu, itau], bank: 'Itaú')?.id, 'c3');
    });
    test('banco igual com final diferente é cartão novo', () {
      expect(matchCard([nu], bank: 'Nubank', last4: '7777'), isNull);
    });
    test('dois cartões do banco sem final: não chuta', () {
      expect(matchCard([nu, nu2], bank: 'Nubank'), isNull);
    });
  });
}
