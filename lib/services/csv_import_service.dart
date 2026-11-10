import 'dart:typed_data';

import 'package:csv/csv.dart';

import '../models/tx.dart';
import 'pdf_import_service.dart' show ParsedItem;

class CsvImportService {
  /// Lê um CSV de fatura e extrai os lançamentos.
  /// Tenta identificar as colunas de data, descrição e valor
  /// pelos cabeçalhos; se não houver cabeçalho, assume as 3 primeiras colunas.
  static List<ParsedItem> parse(Uint8List bytes) {
    final text = String.fromCharCodes(bytes);
    final rows = Csv().decode(text);

    if (rows.length < 2) return [];

    // Tenta encontrar as colunas pelo cabeçalho
    final header =
        rows.first.map((e) => e.toString().trim().toLowerCase()).toList();
    int? dateCol;
    int? descCol;
    int? amountCol;

    for (var i = 0; i < header.length; i++) {
      final h = header[i];
      if (dateCol == null && (h.contains('data') || h == 'date')) {
        dateCol = i;
      }
      if (descCol == null &&
          (h.contains('descri') ||
              h.contains('estabelecimento') ||
              h.contains('histor') ||
              h == 'description')) {
        descCol = i;
      }
      if (amountCol == null &&
          (h.contains('valor') || h == 'amount' || h.contains('r\$'))) {
        amountCol = i;
      }
    }

    // Se não encontrou pelo cabeçalho, assume as 3 primeiras colunas
    if (dateCol == null || descCol == null || amountCol == null) {
      if (rows.first.length >= 3) {
        dateCol ??= 0;
        descCol ??= 1;
        amountCol ??= 2;
      } else {
        return [];
      }
    }

    // Pula a primeira linha se parece um cabeçalho
    final hasHeader = header.any((h) =>
        h.contains('data') || h.contains('descri') || h.contains('valor'));
    final startRow = hasHeader ? 1 : 0;

    final items = <ParsedItem>[];
    for (var i = startRow; i < rows.length; i++) {
      final row = rows[i];
      if (row.length <= amountCol) continue;

      final description = row[descCol].toString().trim();
      if (description.isEmpty) continue;

      final amount = parseMoney(row[amountCol].toString());
      if (amount == null || amount <= 0) continue;
      if (description.length < 3) continue;

      items.add(ParsedItem(description: description, amount: amount));
    }

    return items;
  }
}
