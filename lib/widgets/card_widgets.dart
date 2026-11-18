import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';

import '../models/credit_card.dart';
import '../models/tx.dart';

final _money = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');

/// Iniciais do banco para o selo: "Nubank" → "NU", "Banco do Brasil" → "BB".
String bankInitials(String bank) {
  final words = bank
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty && !{'de', 'do', 'da'}.contains(w))
      .toList();
  if (words.isEmpty) return '?';
  if (words.length == 1) {
    final w = words.first;
    return w.substring(0, w.length < 2 ? w.length : 2).toUpperCase();
  }
  return (words[0][0] + words[1][0]).toUpperCase();
}

/// Quadradinho com a cor e as iniciais do banco.
class BankBadge extends StatelessWidget {
  final String bank;
  final int color;
  final double size;

  const BankBadge(
      {super.key, required this.bank, required this.color, this.size = 36});

  @override
  Widget build(BuildContext context) {
    final bg = Color(color);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(size * 0.28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Text(
        bankInitials(bank),
        style: TextStyle(
          color: onColor(bg),
          fontWeight: FontWeight.w800,
          fontSize: size * 0.36,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// Desenho de cartão de crédito, com a cor do banco.
class CardFace extends StatelessWidget {
  final CreditCard card;

  /// Linha de baixo (ex.: total da fatura). Sem ela mostra os dias.
  final String? footer;

  const CardFace({super.key, required this.card, this.footer});

  @override
  Widget build(BuildContext context) {
    final base = Color(card.color);
    final fg = onColor(base);
    final darker = Color.lerp(base, Colors.black, 0.35)!;
    return AspectRatio(
      aspectRatio: 1.586, // proporção de um cartão de verdade
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [base, darker],
          ),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          boxShadow: [
            BoxShadow(
              color: base.withValues(alpha: 0.30),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: DefaultTextStyle.merge(
          style: TextStyle(color: fg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: Text(
                    card.nickname?.trim().isNotEmpty == true
                        ? '${card.bank} ${card.nickname!.trim()}'
                        : card.bank,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 18),
                  ),
                ),
                Icon(Icons.contactless_rounded,
                    color: fg.withValues(alpha: 0.8)),
              ]),
              const Spacer(),
              // Chip do cartão.
              Container(
                width: 38,
                height: 28,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  gradient: const LinearGradient(
                    colors: [Color(0xFFF5D67B), Color(0xFFC9A44A)],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '••••  ••••  ••••  ${card.last4 ?? '••••'}',
                style: TextStyle(
                  fontSize: 16,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w600,
                  color: fg.withValues(alpha: 0.9),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                footer ??
                    'Fecha dia ${card.closingDay}  •  Vence dia ${card.dueDay}',
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: fg.withValues(alpha: 0.85)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Etiqueta pequena com a forma de pagamento de um lançamento.
class PaymentTag extends StatelessWidget {
  final Tx tx;
  final CreditCard? card;

  const PaymentTag({super.key, required this.tx, this.card});

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (tx.payment) {
      PaymentMethod.credit => (
          card?.label ?? (tx.cardId == null ? 'Crédito' : 'Cartão excluído'),
          Color(card?.color ?? customBankColor),
          Icons.credit_card_rounded,
        ),
      PaymentMethod.debit => (
          'Débito/Pix',
          const Color(0xFF2DD4BF),
          Icons.bolt_rounded,
        ),
      null => ('', Colors.transparent, Icons.circle),
    };
    if (tx.payment == null) return const SizedBox.shrink();
    // Cores muito escuras somem no fundo preto: clareia o contorno.
    final visible = color.computeLuminance() < 0.2
        ? Color.lerp(color, Colors.white, 0.5)!
        : color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: visible.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: visible.withValues(alpha: 0.45)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: visible),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: visible),
          ),
        ),
      ]),
    );
  }
}

/// Linha "Nubank •1234 — R$ 1.234,56" usada em listas e resumos.
class CardTotalRow extends StatelessWidget {
  final CreditCard card;
  final double total;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool selected;

  const CardTotalRow({
    super.key,
    required this.card,
    required this.total,
    this.subtitle,
    this.onTap,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: selected
              ? Color(card.color).withValues(alpha: 0.14)
              : Colors.transparent,
          border: Border.all(
            color: selected
                ? Color(card.color).withValues(alpha: 0.6)
                : Colors.transparent,
          ),
        ),
        child: Row(children: [
          BankBadge(bank: card.bank, color: card.color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(card.label,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                if (subtitle != null)
                  Text(subtitle!, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          Text(_money.format(total),
              style:
                  const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        ]),
      ),
    );
  }
}
