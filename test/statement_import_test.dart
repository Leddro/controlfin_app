import 'dart:convert';
import 'dart:typed_data';

import 'package:financas_app/services/csv_import_service.dart';
import 'package:financas_app/services/pdf_import_service.dart';
import 'package:financas_app/services/statement_parsing.dart';
import 'package:flutter_test/flutter_test.dart';

/// Texto como a biblioteca de PDF extrai a fatura do Nubank: cada campo da
/// transação numa linha. Dados fictícios.
const nubankPdfText = '''
Olá, Fulano.
Esta é a sua fatura de
dezembro, no valor de
R\$ 512,40
Data de vencimento: 09 JAN 2027
Período vigente: 01 DEZ a 01 JAN
FULANO DE TAL
FATURA 09 JAN 2027
EMISSÃO E ENVIO 01 JAN 2027
RESUMO DA FATURA ATUAL
Fatura anterior R\$ 300,00
Pagamento recebido −R\$ 300,00
PRÓXIMAS FATURAS
Fechamento da próxima fatura
01 FEV 2027
Saldo em aberto da próxima fatura
R\$ 774,90
TRANSAÇÕES
DE 01 DEZ A 01 JAN
Fulano de Tal
R\$ 512,40
01 DEZ

•••• 1234
Escola Online - Parcela 3/12
R\$ 74,90
04 DEZ

•••• 1234
Pag*Lojadejogos
R\$ 16,28
12 DEZ

•••• 1234
Seguradora*Pcl2de12
R\$ 139,71
28 DEZ

•••• 1234
Dl *Uberrides
R\$ 7,96
Pagamentos
-R\$ 300,00
05 DEZ
Pagamento em 05 DEZ
−R\$ 300,00
Em cumprimento à regulação do Banco Central, as suas operações de
''';

Uint8List csvBytes(String text) => Uint8List.fromList(utf8.encode(text));

void main() {
  group('datas', () {
    test('formatos aceitos', () {
      expect(parseStatementDate('2026-10-25'), DateTime(2026, 10, 25));
      expect(parseStatementDate('25/10/2026'), DateTime(2026, 10, 25));
      expect(parseStatementDate('25/10/26'), DateTime(2026, 10, 25));
      expect(parseStatementDate('25 OUT', reference: DateTime(2026, 11, 9)),
          DateTime(2026, 10, 25));
      expect(parseStatementDate('31/02/2026'), isNull);
      expect(parseStatementDate('Pag*Steam'), isNull);
    });

    test('sem ano: dezembro numa fatura de janeiro é do ano anterior', () {
      final ref = DateTime(2027, 1, 9);
      expect(
          parseStatementDate('28 DEZ', reference: ref), DateTime(2026, 12, 28));
      expect(
          parseStatementDate('02 JAN', reference: ref), DateTime(2027, 1, 2));
    });
  });

  group('valores', () {
    test('formatos aceitos e sinais', () {
      expect(parseStatementAmount('7,96'), 7.96);
      expect(parseStatementAmount('R\$ 1.122,48'), 1122.48);
      expect(parseStatementAmount('- 1.122,48'), -1122.48);
      expect(parseStatementAmount('−R\$ 1.122,48'), -1122.48);
      expect(parseStatementAmount('7,96-'), -7.96);
      expect(parseStatementAmount('15.50'), 15.5);
      expect(parseStatementAmount('2026-10-25'), isNull);
    });
  });

  group('descrição', () {
    test('separa parcela e limpa prefixos', () {
      final a = cleanDescription('Gran Educacao - Parcela 3/12');
      expect((a.text, a.installment, a.installments), ('Gran Educacao', 3, 12));

      final b = cleanDescription('Mapfre*Pcl2de12');
      expect((b.text, b.installment, b.installments), ('Mapfre', 2, 12));

      expect(cleanDescription('Pag*Steam').text, 'Steam');
      expect(cleanDescription('Dl *Uberrides').text, 'Uberrides');
      expect(cleanDescription('•••• 1234 Jade Motos').text, 'Jade Motos');

      final c = cleanDescription('MAGAZINE LOJA 03/10');
      expect((c.text, c.installment, c.installments), ('MAGAZINE LOJA', 3, 10));
      expect(cleanDescription('Mercado').installment, isNull);
    });
  });

  test('PDF do Nubank: campos em linhas separadas', () {
    final items = PdfImportService.parseText(nubankPdfText);
    expect(items.map((i) => i.description), [
      'Escola Online',
      'Lojadejogos',
      'Seguradora',
      'Uberrides',
    ]);
    expect(items.map((i) => i.amount), [74.90, 16.28, 139.71, 7.96]);
    // Ano deduzido pelo vencimento em janeiro de 2027.
    expect(items.first.date, DateTime(2026, 12, 1));
    expect(items.last.date, DateTime(2026, 12, 28));
    expect((items[0].installment, items[0].installments), (3, 12));
    expect((items[2].installment, items[2].installments), (2, 12));
    expect(items[1].isInstallment, isFalse);
    // O pagamento da fatura (negativo) fica de fora.
    expect(items.any((i) => i.description.contains('Pagamento')), isFalse);
  });

  test('PDF com data, descrição e valor na mesma linha', () {
    const text = '''
Vencimento 10/11/2026
05/10 MERCADO BOM PRECO 123,45
07/10 FARMACIA CENTRAL 03/05 59,90
10/10 ESTORNO LOJA -20,00
''';
    final items = PdfImportService.parseText(text);
    expect(items.length, 2);
    expect(items[0].description, 'MERCADO BOM PRECO');
    expect(items[0].date, DateTime(2026, 10, 5));
    expect(items[1].description, 'FARMACIA CENTRAL');
    expect((items[1].installment, items[1].installments), (3, 5));
    expect(items[1].amount, 59.90);
  });

  test('CSV do Nubank: date,title,amount', () {
    final items = CsvImportService.parse(csvBytes('''
date,title,amount
2026-10-25,Dl *Uberrides,"7,96"
2026-10-12,Seguradora*Pcl2de12,"139,71"
2026-10-05,Pagamento recebido,"- 1.122,48"
2026-10-04,Pag*Lojadejogos,"16,28"
2026-10-01,Escola de Educação - Parcela 3/12,"74,90"
'''));
    expect(items.map((i) => i.description),
        ['Uberrides', 'Seguradora', 'Lojadejogos', 'Escola de Educação']);
    expect(items.map((i) => i.date), [
      DateTime(2026, 10, 25),
      DateTime(2026, 10, 12),
      DateTime(2026, 10, 4),
      DateTime(2026, 10, 1),
    ]);
    expect(items.map((i) => i.amount), [7.96, 139.71, 16.28, 74.90]);
    expect((items[1].installment, items[1].installments), (2, 12));
    expect((items[3].installment, items[3].installments), (3, 12));
  });

  test('CSV com ponto e vírgula, latin-1 e coluna de parcela', () {
    const text = 'Data;Estabelecimento;Parcela;Valor\n'
        '05/10/2026;Padaria São João;;12,50\n'
        '06/10/2026;Loja de Móveis;2 de 6;250,00\n';
    final items =
        CsvImportService.parse(Uint8List.fromList(latin1.encode(text)));
    expect(items.map((i) => i.description),
        ['Padaria São João', 'Loja de Móveis']);
    expect(items[0].date, DateTime(2026, 10, 5));
    expect((items[1].installment, items[1].installments), (2, 6));
  });
}
