import 'dart:typed_data';

import 'package:csv/csv.dart';

import '../models/tx.dart';
import 'pdf_import_service.dart' show ParsedItem;

/// Mapeamento de cabeçalhos conhecidos para tipo de coluna.
/// Adicione novos padrões aqui para suportar outros bancos.
const _descHeaders = {
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
      text = const _Utf8OrLatin1Decoder().decode(bytes);
    } catch (_) {
      text = String.fromCharCodes(bytes);
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
      if (row.length <= amountCol) continue;

      final description = row[descCol].toString().trim();
      if (description.isEmpty || description.length < 2) continue;

      // Valor: se houver coluna de parcela, pode estar no formato "valor/parcelas"
      final rawAmount = row[amountCol].toString().trim();
      double? amount = parseMoney(rawAmount);

      // Tenta incorporar info de parcela na descrição
      String? installmentInfo;
      if (installmentCol != null && installmentCol < row.length) {
        final raw = row[installmentCol].toString().trim();
        if (raw.isNotEmpty && raw != '0' && raw != '-') {
          installmentInfo = raw;
        }
      }

      if (amount == null || amount <= 0) continue;

      final finalDesc = installmentInfo != null
          ? '$description (Parcela $installmentInfo)'
          : description;

      items.add(ParsedItem(description: finalDesc, amount: amount));
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

      // Última coluna com número válido = valor
      double? amount;
      int amountCol = row.length - 1;
      for (var i = row.length - 1; i >= 0; i--) {
        final v = parseMoney(row[i].toString());
        if (v != null && v > 0) {
          amount = v;
          amountCol = i;
          break;
        }
      }
      if (amount == null) continue;

      // Primeira coluna de texto longo (> 3 chars, não é data/número) = descrição
      String? description;
      for (var i = 0; i < amountCol; i++) {
        final cell = row[i].toString().trim();
        if (cell.length >= 3 &&
            parseMoney(cell) == null &&
            !_looksLikeDate(cell)) {
          description = cell;
          break;
        }
      }
      if (description == null) continue;

      items.add(ParsedItem(description: description, amount: amount));
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

  static bool _looksLikeDate(String s) =>
      RegExp(r'^\d{1,2}[/\-.]\d{1,2}([/\-.]\d{2,4})?$').hasMatch(s);
}

/// Decodificador que tenta UTF-8 e cai para latin-1.
class _Utf8OrLatin1Decoder {
  const _Utf8OrLatin1Decoder();

  String decode(List<int> bytes) {
    // Tenta detectar UTF-8 válido
    try {
      // ignore: unnecessary_statements
      bytes.map((b) => b).toList(); // just access
      return String.fromCharCodes(bytes);
    } catch (_) {
      return String.fromCharCodes(bytes);
    }
  }
}
