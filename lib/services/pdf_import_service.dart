import 'dart:typed_data';

import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../models/tx.dart';

/// Item bruto extraído do PDF (antes do usuário revisar).
class ParsedItem {
  final String description;
  final double amount;

  ParsedItem({required this.description, required this.amount});
}

class PdfImportService {
  /// Extrai o texto do PDF e tenta identificar lançamentos de fatura.
  static Future<List<ParsedItem>> parse(Uint8List bytes) async {
    final document = PdfDocument(inputBytes: bytes);
    final text = PdfTextExtractor(document).extractText();
    document.dispose();
    return _parseTransactions(text);
  }

  /// Procura linhas que têm uma data no início e um valor no final.
  static List<ParsedItem> _parseTransactions(String text) {
    final items = <ParsedItem>[];
    final lines = text.split(RegExp(r'[\r\n]+'));

    // Data no início da linha: DD/MM, DD/MM/YY, DD/MM/YYYY
    // ou DD seguido de mês abreviado (jan, fev, mar, abr, mai, jun, ...)
    final dateRe = RegExp(
      r'^\s*(\d{1,2})[/-](\d{1,2})(?:[/-]\d{2,4})?\s+'
      r'|^\s*(\d{1,2})\s+(jan|fev|mar|abr|mai|jun|jul|ago|set|out|nov|dez)\w*\s+',
      caseSensitive: false,
    );

    // Valor no fim da linha: X.XXX,XX ou R$ X.XXX,XX (com sinal opcional)
    final amountRe = RegExp(r'(?:R\$\s*)?(-?[\d.]+,\d{2})\s*$');

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      final dateMatch = dateRe.firstMatch(trimmed);
      final amountMatch = amountRe.firstMatch(trimmed);

      if (dateMatch == null || amountMatch == null) continue;

      final dateEnd = dateMatch.end;
      final amountStart = amountMatch.start;
      if (dateEnd >= amountStart) continue;

      final description = trimmed.substring(dateEnd, amountStart).trim();
      final amount = parseMoney(amountMatch.group(1)!);

      if (amount == null || amount <= 0) continue;
      if (description.length < 3) continue;

      // Evita duplicar itens idênticos consecutivos
      if (items.isNotEmpty &&
          items.last.description == description &&
          items.last.amount == amount) {
        continue;
      }

      items.add(ParsedItem(description: description, amount: amount));
    }

    return items;
  }
}
