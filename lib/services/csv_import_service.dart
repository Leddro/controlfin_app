import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';

import 'statement_parsing.dart';

/// Mapeamento de cabeçalhos conhecidos para tipo de coluna.
/// Adicione novos padrões aqui para suportar outros bancos.
const _descHeaders = {
  'title',
  'estabelecimento',
  'descricao',
  'descrição',
  'historico',
  'histórico',
  'description',
  'lancamento',
  'lançamento',
  'memo',
  'comerciante',
  'beneficiario',
  'beneficiário',
  'nome',
};

const _amountHeaders = {
  'valor',
  'amount',
  'debito',
  'débito',
  'credito',
  'crédito',
  'debit',
  'credit',
  'value',
  'importancia',
  'importância',
};

const _dateHeaders = {
  'data',
  'date',
  'data lançamento',
  'data lancamento',
  'data compra',
  'dt compra',
  'dt.',
  'vencimento',
};

const _installmentHeaders = {
  'parcela',
  'parcelas',
  'installment',
};

class CsvImportService {
  static List<ParsedItem> parse(Uint8List bytes) {
    // Tenta UTF-8 primeiro, depois latin-1 (comum em bancos brasileiros)
    String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      text = latin1.decode(bytes);
    }

    // Remove BOM se existir
    if (text.startsWith('\uFEFF')) text = text.substring(1);

    // Detecta separador automaticamente (;, , ou tab)
    final sep = _detectSeparator(text);
    final rows = Csv(fieldDelimiter: sep, autoDetect: false).decode(text);

    // Encontra a linha de cabeçalho (pode não ser a primeira linha)
    final headerRowIndex = _findHeaderRow(rows);
    if (headerRowIndex == null || headerRowIndex >= rows.length - 1) {
      return _parseWithoutHeader(rows);
    }

    final header =
        rows[headerRowIndex].map((e) => _normalize(e.toString())).toList();

    int? dateCol;
    int? descCol;
    int? amountCol;
    int? installmentCol;

    for (var i = 0; i < header.length; i++) {
      final h = header[i];
      if (dateCol == null && _dateHeaders.any((p) => h.contains(p))) {
        dateCol = i;
      }
      if (descCol == null && _descHeaders.any((p) => h.contains(p))) {
        descCol = i;
      }
      if (amountCol == null && _amountHeaders.any((p) => h.contains(p))) {
        amountCol = i;
      }
      if (installmentCol == null &&
          _installmentHeaders.any((p) => h.contains(p))) {
        installmentCol = i;
      }
    }

    // Fallback: usa posição se não encontrou pelo cabeçalho
    if (descCol == null || amountCol == null) {
      return _parseWithoutHeader(rows.skip(headerRowIndex + 1).toList());
    }

    final items = <ParsedItem>[];
    for (var i = headerRowIndex + 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.length <= amountCol || row.length <= descCol) continue;

      final description = row[descCol].toString().trim();
      if (description.length < 2) continue;

      // Negativo = pagamento da fatura, estorno ou crédito: fica de fora.
      final amount = parseStatementAmount(row[amountCol].toString());
      if (amount == null || amount <= 0) continue;

      final date = dateCol != null && dateCol < row.length
          ? parseStatementDate(row[dateCol].toString())
          : null;

      final clean = cleanDescription(description);
      int? index = clean.installment;
      int? count = clean.installments;
      if (installmentCol != null && installmentCol < row.length) {
        final m = RegExp(r'(\d{1,2})\s*(?:/|de)\s*(\d{1,2})')
            .firstMatch(row[installmentCol].toString());
        if (m != null) {
          final i = int.parse(m.group(1)!);
          final c = int.parse(m.group(2)!);
          if (i >= 1 && c >= 2 && i <= c) {
            index = i;
            count = c;
          }
        }
      }

      items.add(ParsedItem(
        description: clean.text,
        amount: amount,
        date: date,
        installment: index,
        installments: count,
      ));
    }

    return items;
  }

  /// Tenta parsear sem cabeçalho assumindo: data, descrição, valor
  /// (ou primeira coluna de texto + última coluna numérica).
  static List<ParsedItem> _parseWithoutHeader(List<List<dynamic>> rows) {
    if (rows.isEmpty) return [];

    final items = <ParsedItem>[];
    for (final row in rows) {
      if (row.length < 2) continue;
      final cells = row.map((c) => c.toString().trim()).toList();

      // Data: primeira célula que parece data.
      DateTime? date;
      for (final cell in cells) {
        date = parseStatementDate(cell);
        if (date != null) break;
      }

      // Valor: última célula numérica que não é data.
      double? amount;
      var amountCol = -1;
      for (var i = cells.length - 1; i >= 0; i--) {
        if (parseStatementDate(cells[i]) != null) continue;
        final v = parseStatementAmount(cells[i]);
        if (v != null) {
          amount = v;
          amountCol = i;
          break;
        }
      }
      if (amount == null || amount <= 0) continue;

      // Descrição: primeira célula de texto antes do valor.
      String? description;
      for (var i = 0; i < amountCol; i++) {
        final cell = cells[i];
        if (cell.length >= 3 &&
            parseStatementAmount(cell) == null &&
            parseStatementDate(cell) == null) {
          description = cell;
          break;
        }
      }
      if (description == null) continue;

      final clean = cleanDescription(description);
      items.add(ParsedItem(
        description: clean.text,
        amount: amount,
        date: date,
        installment: clean.installment,
        installments: clean.installments,
      ));
    }
    return items;
  }

  /// Encontra o índice da linha que mais parece ser o cabeçalho.
  static int? _findHeaderRow(List<List<dynamic>> rows) {
    for (var i = 0; i < rows.length && i < 10; i++) {
      final cells = rows[i].map((e) => _normalize(e.toString())).toList();
      final score = cells
          .where((c) =>
              _descHeaders.any((p) => c.contains(p)) ||
              _amountHeaders.any((p) => c.contains(p)) ||
              _dateHeaders.any((p) => c.contains(p)) ||
              _installmentHeaders.any((p) => c.contains(p)))
          .length;
      if (score >= 2) return i;
    }
    return null;
  }

  static String _detectSeparator(String text) {
    final firstLine = text.split('\n').first;
    final counts = {
      ';': ';'.allMatches(firstLine).length,
      ',': ','.allMatches(firstLine).length,
      '\t': '\t'.allMatches(firstLine).length,
    };
    return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  static String _normalize(String s) => s
      .toLowerCase()
      .trim()
      .replaceAll(RegExp(r'[áàãâä]'), 'a')
      .replaceAll(RegExp(r'[éèêë]'), 'e')
      .replaceAll(RegExp(r'[íìîï]'), 'i')
      .replaceAll(RegExp(r'[óòõôö]'), 'o')
      .replaceAll(RegExp(r'[úùûü]'), 'u')
      .replaceAll(RegExp(r'[ç]'), 'c');
}
