/// Reconhece, no texto de uma fatura ou extrato, o banco, o cartão e as
/// datas da fatura, para o usuário não precisar informar.
library;

import '../models/credit_card.dart';
import '../models/tx.dart';
import 'statement_parsing.dart';

/// O que foi possível descobrir sobre o arquivo importado.
class InvoiceInfo {
  final Bank? bank;

  /// Últimos 4 dígitos do cartão.
  final String? last4;

  /// Vencimento desta fatura.
  final DateTime? dueDate;

  /// Fechamento desta fatura.
  final DateTime? closingDate;

  /// Valor total informado na fatura, para conferir com a soma dos itens.
  final double? total;

  /// O arquivo parece extrato de conta (débito/Pix), não fatura de cartão.
  final bool isAccountStatement;

  const InvoiceInfo({
    this.bank,
    this.last4,
    this.dueDate,
    this.closingDate,
    this.total,
    this.isAccountStatement = false,
  });

  /// Dia do fechamento para um cartão novo. Sem fechamento na fatura, estima
  /// 7 dias antes do vencimento, o prazo mais comum.
  int? get suggestedClosingDay {
    if (closingDate != null) return closingDate!.day;
    if (dueDate != null) {
      return dueDate!.subtract(const Duration(days: 7)).day;
    }
    return null;
  }

  bool get closingIsEstimated => closingDate == null && dueDate != null;

  bool get hasAnything =>
      bank != null || last4 != null || dueDate != null || closingDate != null;
}

/// Lançamentos e informações lidos de um arquivo.
class ParsedStatement {
  final List<ParsedItem> items;
  final InvoiceInfo info;

  const ParsedStatement(this.items, [this.info = const InvoiceInfo()]);
}

const _datePattern = r'(\d{1,2}/\d{1,2}/\d{2,4}'
    r'|\d{1,2}\s+(?:de\s+)?(?:jan|fev|mar|abr|mai|jun|jul|ago|set|out|nov|dez)'
    r'[a-zç]*\.?(?:\s+(?:de\s+)?\d{4})?)';

final _dueRe = RegExp(
  r'(vencimento|vence em|pague até|pagar até|pagável até)[^\d]{0,30}?'
  '$_datePattern',
  caseSensitive: false,
);

final _closingRe = RegExp(
  r'(fechamento|fecha em|data de corte|melhor dia de compra)([^\d]{0,40}?)'
  '$_datePattern',
  caseSensitive: false,
);

final _periodRe = RegExp(
  r'(?:per[ií]odo|transa[çc][õo]es|lan[çc]amentos)[^\d\n]{0,25}'
  '$_datePattern'
  r'\s+(?:a|até|-|–)\s+'
  '$_datePattern',
  caseSensitive: false,
);

final _totalRe = RegExp(
  r'(?:total (?:da|desta) fatura|valor (?:total )?da fatura|no valor de|'
  r'total a pagar)[^\d]{0,25}((?:R\$\s*)?(?:\d{1,3}(?:\.\d{3})+|\d+),\d{2})',
  caseSensitive: false,
);

final _last4Res = [
  // "•••• 1234", "**** 1234", "XXXX XXXX XXXX 1234", "5502 **** **** 1234"
  RegExp(r'(?<![A-Za-z])(?:[•*·xX]{4}[\s.-]*){1,3}(\d{4})\b'),
  RegExp(r'(?<![A-Za-z])[•*·]{2,}\s*(\d{4})\b'),
  // "final 1234", "Cartão final: 1234"
  RegExp(r'\bfinal\s*(?:do cart[ãa]o)?\s*:?\s*(\d{4})\b', caseSensitive: false),
];

/// "10 de dezembro de 2026" vira "10 dezembro 2026", que o leitor entende.
String _normalizeDate(String raw) =>
    raw.replaceAll(RegExp(r'\s+de\s+', caseSensitive: false), ' ');

DateTime? _date(String raw, {DateTime? reference}) =>
    parseStatementDate(_normalizeDate(raw), reference: reference);

Bank? detectBank(String text) {
  final lower = text.toLowerCase();
  Bank? best;
  var bestCount = 0;
  for (final bank in knownBanks) {
    var count = 0;
    for (final k in bank.keywords) {
      count += RegExp('(?<![a-z])${RegExp.escape(k)}(?![a-z])')
          .allMatches(lower)
          .length;
    }
    if (count > bestCount) {
      best = bank;
      bestCount = count;
    }
  }
  return best;
}

String? detectLast4(String text) {
  final counts = <String, int>{};
  for (final re in _last4Res) {
    for (final m in re.allMatches(text)) {
      final digits = m.group(1)!;
      counts[digits] = (counts[digits] ?? 0) + 1;
    }
  }
  if (counts.isEmpty) return null;
  return (counts.entries.toList()..sort((a, b) => b.value - a.value)).first.key;
}

/// Lê o texto (e o nome do arquivo, que em alguns bancos traz o banco e o
/// vencimento, ex.: "Nubank_2027-01-09.csv").
InvoiceInfo detectInvoice(String text, {String? fileName}) {
  final name = fileName ?? '';
  final lower = text.toLowerCase();

  final bank = detectBank(text) ?? detectBank(name.replaceAll('_', ' '));
  final last4 = detectLast4(text);

  DateTime? due;
  final dueMatch = _dueRe.firstMatch(text);
  if (dueMatch != null) due = _date(dueMatch.group(2)!);
  if (due == null) {
    final iso = RegExp(r'(\d{4})-(\d{2})-(\d{2})').firstMatch(name);
    if (iso != null) due = parseStatementDate(iso.group(0)!);
  }

  DateTime? closing;
  DateTime? nextClosing;
  for (final m in _closingRe.allMatches(text)) {
    final context = '${m.group(1)}${m.group(2)}'.toLowerCase();
    if (context.contains('melhor dia')) continue;
    final date = _date(m.group(3)!, reference: due);
    if (date == null) continue;
    if (context.contains('próxim') || context.contains('proxim')) {
      nextClosing ??= date;
    } else {
      closing ??= date;
    }
  }
  if (closing == null) {
    final period = _periodRe.firstMatch(text);
    if (period != null) closing = _date(period.group(2)!, reference: due);
  }
  if (closing == null && nextClosing != null) {
    closing = addMonths(nextClosing, -1);
  }
  // Fechamento depois do vencimento não faz sentido: descarta.
  if (closing != null && due != null && closing.isAfter(due)) closing = null;

  double? total;
  final totalMatch = _totalRe.firstMatch(text);
  if (totalMatch != null) total = parseStatementAmount(totalMatch.group(1)!);

  final statementWords = RegExp(r'\bextrato\b|\bidentificador\b|saldo do dia');
  final invoiceWords = RegExp(r'\bfatura\b|vencimento|fechamento');
  final isStatement = statementWords.hasMatch(lower) &&
      !invoiceWords.hasMatch(lower) &&
      due == null;

  return InvoiceInfo(
    bank: bank,
    last4: last4,
    dueDate: due,
    closingDate: closing,
    total: total,
    isAccountStatement: isStatement,
  );
}
