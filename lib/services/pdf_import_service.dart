import 'dart:typed_data';

import 'package:syncfusion_flutter_pdf/pdf.dart';

import 'invoice_detection.dart';
import 'statement_parsing.dart';

export 'invoice_detection.dart' show InvoiceInfo, ParsedStatement;
export 'statement_parsing.dart' show ParsedItem;

class PdfImportService {
  /// Extrai o texto do PDF e tenta identificar lançamentos de fatura.
  static Future<List<ParsedItem>> parse(Uint8List bytes) async =>
      (await parseDocument(bytes)).items;

  /// Lançamentos e dados da fatura (banco, cartão, vencimento).
  static Future<ParsedStatement> parseDocument(Uint8List bytes,
      {String? fileName}) async {
    final document = PdfDocument(inputBytes: bytes);
    final text = PdfTextExtractor(document).extractText();
    document.dispose();
    return parseStatementText(text, fileName: fileName);
  }

  static ParsedStatement parseStatementText(String text, {String? fileName}) =>
      ParsedStatement(parseText(text), detectInvoice(text, fileName: fileName));

  // Data no início da linha: "25/10", "25/10/2026", "25 OUT".
  static final _leadingDate = RegExp(
    r'^(\d{1,2}[/.-]\d{1,2}(?:[/.-]\d{2,4})?'
    r'|\d{1,2}\s+(?:jan|fev|mar|abr|mai|jun|jul|ago|set|out|nov|dez)[a-zç]*\.?'
    r'(?:\s+\d{4})?)'
    r'(?=\s|$)',
    caseSensitive: false,
  );

  // Linhas de resumo da fatura que também têm data e valor
  // ("01 DEZ 2026" / "Saldo em aberto da próxima fatura" / "R$ 774,90").
  static final _summary = RegExp(
    r'^(saldo|total|fatura|limite|vencimento|fechamento|pagamento|'
    r'encargos|juros|iof|multa|anuidade cancelada)',
    caseSensitive: false,
  );

  // Valor no fim da linha, com sinal opcional antes ou depois.
  static final _trailingAmount = RegExp(
    r'([-−–]?\s*(?:R\$\s*)?[-−–]?\s*(?:\d{1,3}(?:\.\d{3})+|\d+),\d{2}\s*-?)\s*$',
  );

  // Linha só com o valor: "R$ 74,90", "−R$ 1.122,48".
  static final _amountOnly = RegExp(
    r'^[-−–]?\s*(?:R\$\s*)?[-−–]?\s*(?:\d{1,3}(?:\.\d{3})+|\d+),\d{2}\s*-?$',
  );

  // Linha só com o cartão: "•••• 1234".
  static final _cardOnly = RegExp(r'^[•*·]{2,}\s*\d{4}$');

  /// Lê os lançamentos do texto da fatura.
  ///
  /// Aceita a data, a descrição e o valor na mesma linha (comum em vários
  /// bancos) ou em linhas seguidas, como o Nubank:
  /// "25 OUT" / "•••• 1234" / "Dl *Uberrides" / "R$ 7,96".
  /// Valores negativos (pagamentos, estornos) ficam de fora.
  static List<ParsedItem> parseText(String text) {
    final reference = findReferenceDate(text);
    final lines = text
        .split(RegExp(r'[\r\n]+'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    final items = <ParsedItem>[];
    DateTime? pendingDate;
    final pendingDesc = <String>[];

    void emit(DateTime? date, String rawDesc, String rawAmount) {
      final amount = parseStatementAmount(rawAmount);
      if (amount == null || amount <= 0) return;
      final clean = cleanDescription(rawDesc);
      if (clean.text.length < 2 || _summary.hasMatch(clean.text)) return;
      items.add(ParsedItem(
        description: clean.text,
        amount: amount,
        date: date,
        installment: clean.installment,
        installments: clean.installments,
      ));
    }

    for (final line in lines) {
      final dateMatch = _leadingDate.firstMatch(line);
      if (dateMatch != null) {
        final date =
            parseStatementDate(dateMatch.group(1)!, reference: reference);
        if (date != null) {
          final rest = line.substring(dateMatch.end).trim();
          final amountMatch = _trailingAmount.firstMatch(rest);
          if (amountMatch != null && amountMatch.start > 0) {
            // Tudo na mesma linha.
            emit(date, rest.substring(0, amountMatch.start),
                amountMatch.group(1)!);
            pendingDate = null;
            pendingDesc.clear();
            continue;
          }
          pendingDate = date;
          pendingDesc
            ..clear()
            ..addAll([if (rest.isNotEmpty) rest]);
          continue;
        }
      }

      if (pendingDate == null) continue;

      if (_amountOnly.hasMatch(line)) {
        if (pendingDesc.isNotEmpty) {
          emit(pendingDate, pendingDesc.join(' '), line);
        }
        pendingDate = null;
        pendingDesc.clear();
      } else if (_cardOnly.hasMatch(line)) {
        continue;
      } else if (pendingDesc.length < 3) {
        pendingDesc.add(line);
      } else {
        // Texto demais depois da data: não era um lançamento.
        pendingDate = null;
        pendingDesc.clear();
      }
    }
    return items;
  }
}
