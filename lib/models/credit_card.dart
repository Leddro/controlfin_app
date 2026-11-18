import 'package:material_ui/material_ui.dart';

import 'tx.dart';

/// Banco conhecido: nome, cor da marca e palavras que aparecem nas faturas.
class Bank {
  final String name;
  final int color;
  final List<String> keywords;

  const Bank(this.name, this.color, [this.keywords = const []]);
}

/// Bancos e emissores mais comuns no Brasil. A ordem é a da lista de escolha.
const knownBanks = <Bank>[
  Bank('Nubank', 0xFF820AD1, ['nubank', 'nu pagamentos']),
  Bank('Itaú', 0xFFEC7000, ['itaú', 'itau', 'itaucard']),
  Bank('Inter', 0xFFFF7A00, ['banco inter', 'inter&co', 'bancointer']),
  Bank('C6 Bank', 0xFF2B2B2B, ['c6 bank', 'banco c6', 'c6bank', 'c6 carbon']),
  Bank('Bradesco', 0xFFCC092F, ['bradesco', 'bradescard']),
  Bank('Santander', 0xFFEC0000, ['santander']),
  Bank('Banco do Brasil', 0xFFF8D117, ['banco do brasil', 'ourocard']),
  Bank('Caixa', 0xFF005CA9, ['caixa econômica', 'caixa economica']),
  Bank('Mercado Pago', 0xFF00B1EA, ['mercado pago', 'mercadopago']),
  Bank('PicPay', 0xFF21C25E, ['picpay']),
  Bank('XP', 0xFF1F1F1F, ['xp investimentos', 'banco xp', 'xp visa']),
  Bank('BTG Pactual', 0xFF0B2A4A, ['btg pactual']),
  Bank('Neon', 0xFF0090FF, ['banco neon', 'neon pagamentos']),
  Bank('Next', 0xFF00C853, ['banco next']),
  Bank('Will Bank', 0xFFFFD400, ['will bank', 'willbank']),
  Bank('Banco Pan', 0xFF00AEEF, ['banco pan']),
  Bank('Porto Bank', 0xFF00A1E0, ['porto bank', 'portoseguro cartões']),
  Bank('Original', 0xFF00A857, ['banco original']),
  Bank('Sicoob', 0xFF003641, ['sicoob']),
  Bank('Sicredi', 0xFF3FA110, ['sicredi']),
];

/// Cor usada para bancos digitados pelo usuário.
const customBankColor = 0xFF64748B;

Bank? bankByName(String name) {
  final key = name.trim().toLowerCase();
  for (final b in knownBanks) {
    if (b.name.toLowerCase() == key) return b;
  }
  return null;
}

/// Texto legível sobre a cor de fundo [color] (branco ou quase preto).
Color onColor(Color color) =>
    color.computeLuminance() > 0.5 ? const Color(0xFF111111) : Colors.white;

/// Último dia válido do mês para [day] (dia 31 em fevereiro vira 28/29).
DateTime _clampedDay(int year, int month, int day) {
  final last = DateTime(year, month + 1, 0).day;
  return DateTime(year, month, day > last ? last : day);
}

class CreditCard {
  final String? id;

  /// Nome do banco (da lista conhecida ou digitado).
  final String bank;

  /// Apelido opcional, ex.: "Black", "Cartão da casa".
  final String? nickname;

  /// Últimos 4 dígitos, usados para reconhecer a fatura.
  final String? last4;

  /// Dia em que a fatura fecha. Compras nesse dia já vão para a próxima.
  final int closingDay;

  /// Dia do vencimento da fatura.
  final int dueDay;

  final int color;

  const CreditCard({
    this.id,
    required this.bank,
    this.nickname,
    this.last4,
    required this.closingDay,
    required this.dueDay,
    required this.color,
  });

  /// "Nubank •1234", "Itaú Black •9876" ou só "Inter".
  String get label {
    final name = nickname?.trim().isNotEmpty == true
        ? '$bank ${nickname!.trim()}'
        : bank;
    return last4 != null ? '$name •$last4' : name;
  }

  /// Fechamento da fatura que vence no mês de [due].
  DateTime closingForDue(DateTime due) {
    // Vencimento depois do fechamento no mesmo mês (fecha 1, vence 9);
    // senão o fechamento foi no mês anterior (fecha 28, vence 5).
    final sameMonth = dueDay > closingDay;
    final m = sameMonth ? due.month : due.month - 1;
    return _clampedDay(due.year, m, closingDay);
  }

  /// Vencimento da fatura que fecha em [closing].
  DateTime dueForClosing(DateTime closing) {
    final m = dueDay > closingDay ? closing.month : closing.month + 1;
    return _clampedDay(closing.year, m, dueDay);
  }

  /// Vencimento da fatura em que cai uma compra feita em [purchase].
  DateTime dueForPurchase(DateTime purchase) {
    final closingThisMonth =
        _clampedDay(purchase.year, purchase.month, closingDay);
    final closing = purchase.day < closingThisMonth.day
        ? closingThisMonth
        : _clampedDay(purchase.year, purchase.month + 1, closingDay);
    return dueForClosing(closing);
  }

  /// Vencimento da fatura que vence no mês de [month].
  DateTime dueInMonth(DateTime month) =>
      _clampedDay(month.year, month.month, dueDay);

  /// Primeiro e último dia de compras da fatura que vence em [due].
  (DateTime, DateTime) purchaseWindow(DateTime due) {
    final closing = closingForDue(due);
    final previous = _clampedDay(closing.year, closing.month - 1, closingDay);
    return (previous, closing.subtract(const Duration(days: 1)));
  }

  CreditCard copyWith({
    String? id,
    String? bank,
    String? Function()? nickname,
    String? Function()? last4,
    int? closingDay,
    int? dueDay,
    int? color,
  }) =>
      CreditCard(
        id: id ?? this.id,
        bank: bank ?? this.bank,
        nickname: nickname != null ? nickname() : this.nickname,
        last4: last4 != null ? last4() : this.last4,
        closingDay: closingDay ?? this.closingDay,
        dueDay: dueDay ?? this.dueDay,
        color: color ?? this.color,
      );

  Map<String, dynamic> toMap() => {
        'bank': bank,
        if (nickname?.trim().isNotEmpty == true) 'nickname': nickname!.trim(),
        if (last4 != null) 'last4': last4,
        'closingDay': closingDay,
        'dueDay': dueDay,
        'color': color,
      };

  factory CreditCard.fromMap(String id, Map<String, dynamic> m) => CreditCard(
        id: id,
        bank: (m['bank'] as String?)?.trim().isNotEmpty == true
            ? (m['bank'] as String).trim()
            : 'Cartão',
        nickname: m['nickname'] as String?,
        last4: m['last4'] as String?,
        closingDay: ((m['closingDay'] as num?)?.toInt() ?? 1).clamp(1, 31),
        dueDay: ((m['dueDay'] as num?)?.toInt() ?? 10).clamp(1, 31),
        color: (m['color'] as num?)?.toInt() ?? customBankColor,
      );
}

/// Acha o cartão de [cards] que combina com o banco e o final detectados.
///
/// Final igual vale mais que banco igual; banco sozinho só serve quando
/// existe um único cartão daquele banco.
CreditCard? matchCard(List<CreditCard> cards, {String? bank, String? last4}) {
  if (last4 != null) {
    final byDigits = cards.where((c) => c.last4 == last4).toList();
    if (byDigits.length == 1) return byDigits.first;
    if (bank != null) {
      for (final c in byDigits) {
        if (c.bank.toLowerCase() == bank.toLowerCase()) return c;
      }
    }
  }
  if (bank != null) {
    final byBank =
        cards.where((c) => c.bank.toLowerCase() == bank.toLowerCase()).toList();
    // Banco certo mas final diferente: provavelmente é outro cartão.
    final sameBankOtherDigits = last4 != null &&
        byBank.every((c) => c.last4 != null && c.last4 != last4);
    if (byBank.length == 1 && !sameBankOtherDigits) return byBank.first;
  }
  return null;
}

/// Total por cartão dos gastos no crédito de [txs].
Map<String?, double> totalsByCard(Iterable<Tx> txs) {
  final totals = <String?, double>{};
  for (final t in txs) {
    if (t.type != TxType.expense || t.payment != PaymentMethod.credit) continue;
    totals[t.cardId] = (totals[t.cardId] ?? 0) + t.amount;
  }
  return totals;
}
