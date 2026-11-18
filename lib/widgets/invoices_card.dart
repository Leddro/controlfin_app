import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';

import '../models/credit_card.dart';
import '../models/tx.dart';
import 'card_widgets.dart';

final _money = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
final _dayMonth = DateFormat('dd/MM');

/// Faturas que vencem no mês, uma linha por cartão.
class InvoicesCard extends StatelessWidget {
  final DateTime month;

  /// Lançamentos que contam no mês (crédito pelo vencimento).
  final List<Tx> txs;
  final List<CreditCard> cards;

  /// Cartão filtrado na lista de lançamentos.
  final String? selectedCardId;
  final ValueChanged<String> onSelectCard;
  final VoidCallback onManage;
  final VoidCallback onAddCard;

  /// Hoje, para o status da fatura. Parâmetro para os testes.
  final DateTime? today;

  const InvoicesCard({
    super.key,
    required this.month,
    required this.txs,
    required this.cards,
    required this.onSelectCard,
    required this.onManage,
    required this.onAddCard,
    this.selectedCardId,
    this.today,
  });

  /// Chave de filtro dos lançamentos no crédito sem cartão conhecido.
  static const otherCards = '__outros__';

  String _status(CreditCard card, DateTime due) {
    final now = today ?? DateTime.now();
    final day = DateTime(now.year, now.month, now.day);
    final closing = card.closingForDue(due);
    if (day.isBefore(closing)) {
      return 'Aberta • fecha ${_dayMonth.format(closing)}';
    }
    if (!day.isAfter(due)) {
      final left = due.difference(day).inDays;
      final when = switch (left) {
        0 => 'vence hoje',
        1 => 'vence amanhã',
        _ => 'vence em $left dias',
      };
      return 'Fechada • $when';
    }
    return 'Venceu ${_dayMonth.format(due)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final credit =
        txs.where((t) => t.type == TxType.expense && t.isCredit).toList();
    final totals = totalsByCard(credit);
    final known = {for (final c in cards) c.id};
    final orphan = credit
        .where((t) => t.cardId == null || !known.contains(t.cardId))
        .fold(0.0, (s, t) => s + t.amount);
    final total = credit.fold(0.0, (s, t) => s + t.amount);

    // Vencimento real (do lançamento) ou o previsto pelo cartão.
    DateTime dueOf(CreditCard c) {
      for (final t in credit) {
        if (t.cardId == c.id && t.billDate != null) return t.billDate!;
      }
      return c.dueInMonth(month);
    }

    // Cartões com fatura no mês primeiro, do maior valor para o menor.
    final ordered = [...cards]
      ..sort((a, b) => (totals[b.id] ?? 0).compareTo(totals[a.id] ?? 0));

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            const Icon(Icons.credit_card_rounded, color: Color(0xFFFBBF24)),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Faturas do mês',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800)),
            ),
            TextButton(
              onPressed: cards.isEmpty ? onAddCard : onManage,
              child: Text(cards.isEmpty ? 'Adicionar' : 'Gerenciar'),
            ),
          ]),
          if (cards.isEmpty && orphan == 0) ...[
            const SizedBox(height: 4),
            Text(
              'Cadastre seus cartões para ver quanto vem em cada fatura. '
              'Ao importar uma fatura, o cartão é reconhecido sozinho.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onAddCard,
              icon: const Icon(Icons.add_card_rounded),
              label: const Text('Adicionar cartão'),
            ),
          ] else ...[
            const SizedBox(height: 4),
            for (final c in ordered)
              CardTotalRow(
                card: c,
                total: totals[c.id] ?? 0,
                subtitle: (totals[c.id] ?? 0) == 0
                    ? 'Sem compras nesta fatura'
                    : _status(c, dueOf(c)),
                selected: selectedCardId == c.id,
                onTap:
                    (totals[c.id] ?? 0) == 0 ? null : () => onSelectCard(c.id!),
              ),
            if (orphan > 0)
              CardTotalRow(
                card: const CreditCard(
                  bank: 'Outros',
                  closingDay: 1,
                  dueDay: 10,
                  color: customBankColor,
                ),
                total: orphan,
                subtitle: 'Crédito sem cartão cadastrado',
                selected: selectedCardId == otherCards,
                onTap: () => onSelectCard(otherCards),
              ),
            if (total > 0) ...[
              const Divider(height: 20),
              Row(children: [
                Expanded(
                  child: Text('Total no crédito',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                ),
                Text(_money.format(total),
                    style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: Color(0xFFF87171))),
              ]),
            ],
          ],
        ],
      ),
    );
  }
}
