/// Funções comuns à leitura de faturas e extratos (PDF e CSV).
library;

/// Lançamento lido do arquivo, antes de o usuário revisar.
class ParsedItem {
  final String description;
  final double amount;

  /// Data da compra, quando o arquivo informa.
  final DateTime? date;

  /// Parcela atual e total de parcelas, quando é uma compra parcelada.
  final int? installment;
  final int? installments;

  const ParsedItem({
    required this.description,
    required this.amount,
    this.date,
    this.installment,
    this.installments,
  });

  bool get isInstallment => installment != null && installments != null;

  @override
  String toString() => 'ParsedItem($description, $amount, $date, '
      '${isInstallment ? '$installment/$installments' : '-'})';
}

/// Descrição limpa e a parcela que estava escrita nela.
class CleanDescription {
  final String text;
  final int? installment;
  final int? installments;

  const CleanDescription(this.text, [this.installment, this.installments]);
}

const _monthNames = {
  'jan': 1,
  'fev': 2,
  'mar': 3,
  'abr': 4,
  'mai': 5,
  'jun': 6,
  'jul': 7,
  'ago': 8,
  'set': 9,
  'out': 10,
  'nov': 11,
  'dez': 12,
};

const _monthPattern = r'(jan|fev|mar|abr|mai|jun|jul|ago|set|out|nov|dez)';

final _isoDate = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})');
final _brDate = RegExp(r'^(\d{1,2})[/.-](\d{1,2})(?:[/.-](\d{2,4}))?$');
final _textDate = RegExp(
  '^(\\d{1,2})\\s+$_monthPattern[a-zç]*\\.?(?:\\s+(\\d{4}))?\$',
  caseSensitive: false,
);

/// Lê datas como "2026-10-25", "25/10/2026", "25/10/26", "25/10" e "25 OUT".
/// Sem ano, usa o ano de [reference]; se o mês for depois do mês de
/// referência, a compra é do ano anterior (fatura de janeiro com compras de
/// dezembro).
DateTime? parseStatementDate(String raw, {DateTime? reference}) {
  final s = raw.trim();
  int? day, month, year;

  final iso = _isoDate.firstMatch(s);
  if (iso != null) {
    year = int.parse(iso.group(1)!);
    month = int.parse(iso.group(2)!);
    day = int.parse(iso.group(3)!);
  } else if (_brDate.firstMatch(s) case final br?) {
    day = int.parse(br.group(1)!);
    month = int.parse(br.group(2)!);
    final y = br.group(3);
    if (y != null) year = y.length == 2 ? 2000 + int.parse(y) : int.parse(y);
  } else if (_textDate.firstMatch(s) case final text?) {
    day = int.parse(text.group(1)!);
    month = _monthNames[text.group(2)!.toLowerCase()];
    final y = text.group(3);
    if (y != null) year = int.parse(y);
  } else {
    return null;
  }

  if (month == null || month < 1 || month > 12 || day < 1 || day > 31) {
    return null;
  }
  if (year == null) {
    final ref = reference ?? DateTime.now();
    year = month > ref.month ? ref.year - 1 : ref.year;
  }
  final date = DateTime(year, month, day);
  // Rejeita datas que "transbordam" (31/02 vira 03/03).
  if (date.month != month) return null;
  return date;
}

/// Primeira data completa (com ano) do texto, usada como referência para
/// as datas sem ano. Nas faturas costuma ser o vencimento ou a emissão.
DateTime? findReferenceDate(String text) {
  final textual = RegExp(
    '(\\d{1,2})\\s+$_monthPattern[a-zç]*\\.?\\s+(\\d{4})',
    caseSensitive: false,
  ).firstMatch(text);
  if (textual != null) {
    return parseStatementDate(textual.group(0)!);
  }
  final numeric = RegExp(r'(\d{1,2})/(\d{1,2})/(\d{4})').firstMatch(text);
  if (numeric != null) return parseStatementDate(numeric.group(0)!);
  return null;
}

final _installmentPatterns = [
  // "Loja - Parcela 3/12", "Loja (Parc. 3 de 12)"
  RegExp(
      r'\s*[-–]?\s*\(?\bparc(?:ela)?\.?\s*(\d{1,2})\s*(?:/|de)\s*(\d{1,2})\)?',
      caseSensitive: false),
  // "Mapfre*Pcl2de12"
  RegExp(r'\s*\*?\s*\bpcl\.?\s*(\d{1,2})\s*(?:/|de)\s*(\d{1,2})',
      caseSensitive: false),
  // "LOJA 03/10" no fim da descrição
  RegExp(r'\s+\(?(\d{1,2})\s*/\s*(\d{1,2})\)?\s*$'),
];

/// Número do cartão mascarado: "•••• 1234", "**** 1234", "Final 1234".
final _cardMask =
    RegExp(r'(?:[•*·]{2,}\s*\d{4}|\bfinal\s+\d{4})\s*', caseSensitive: false);

/// Prefixo de intermediador de pagamento: "Pag*", "Dl *", "Mp *", "Ifd*".
final _processorPrefix = RegExp(r'^[A-Za-z]{2,3}\s?\*\s?(?=\S)');

/// Tira número do cartão, prefixo de intermediador e a parcela da
/// descrição, devolvendo a parcela separada.
CleanDescription cleanDescription(String raw) {
  var text = raw.replaceAll(_cardMask, ' ').trim();
  int? index, count;
  for (final pattern in _installmentPatterns) {
    final m = pattern.firstMatch(text);
    if (m == null) continue;
    final i = int.parse(m.group(1)!);
    final c = int.parse(m.group(2)!);
    if (i < 1 || c < 2 || i > c) continue;
    index = i;
    count = c;
    text = text.replaceRange(m.start, m.end, ' ');
    break;
  }
  final withoutPrefix = text.trim().replaceFirst(_processorPrefix, '');
  if (withoutPrefix.trim().length >= 2) text = withoutPrefix;
  text = text
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'^[\s*\-–]+|[\s*\-–]+$'), '')
      .trim();
  if (text.isEmpty) text = raw.trim();
  return CleanDescription(text, index, count);
}

/// Lê "1.234,56", "R$ 1.234,56", "- 1.234,56", "−R$ 7,96" e "7,96-".
/// Negativo indica pagamento, estorno ou crédito.
double? parseStatementAmount(String raw) {
  var s = raw.trim().replaceAll(' ', ' ');
  var negative = false;
  if (RegExp(r'^[-−–]').hasMatch(s) || RegExp(r'[-−–]$').hasMatch(s)) {
    negative = true;
  }
  // Sinal só vale no começo ou no fim ("2026-10-25" não é valor).
  s = s
      .replaceAll(RegExp(r'^[-−–+]\s*|\s*[-−–]$'), '')
      .replaceAll(r'R$', '')
      .trim()
      .replaceAll(RegExp(r'^[-−–]\s*'), '');
  if (RegExp(r'[-−–+]').hasMatch(s)) return null;
  s = s.replaceAll(' ', '');
  if (s.isEmpty) return null;
  if (s.contains(',')) {
    if (!RegExp(r'^\d{1,3}(\.\d{3})*,\d{1,2}$|^\d+,\d{1,2}$').hasMatch(s)) {
      return null;
    }
    s = s.replaceAll('.', '').replaceAll(',', '.');
  } else if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(s)) {
    return null;
  }
  final value = double.tryParse(s);
  if (value == null) return null;
  return negative ? -value : value;
}
