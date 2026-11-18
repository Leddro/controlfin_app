import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';

import '../models/credit_card.dart';
import '../services/tx_service.dart';
import 'card_widgets.dart';

final _money = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');

String monthName(DateTime d) =>
    toBeginningOfSentenceCase(DateFormat('MMMM', 'pt_BR').format(d));

/// Avisa quanto do mês seguinte já está comprometido no crédito, para o
/// usuário saber hoje o que vai pagar depois.
class UpcomingCard extends StatelessWidget {
  final DateTime month;
  final MonthView view;
  final List<CreditCard> cards;
  final VoidCallback onOpenNextMonth;

  const UpcomingCard({
    super.key,
    required this.month,
    required this.view,
    required this.cards,
    required this.onOpenNextMonth,
  });

  /// Mostra o bloco só quando há algo a pagar depois.
  static bool hasContent(MonthView view) =>
      view.nextMonthTotal > 0 || view.deferred.isNotEmpty;

  CreditCard? _card(String? id) {
    for (final c in cards) {
      if (c.id == id) return c;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final next = DateTime(month.year, month.month + 1);
    final afterNext = DateTime(month.year, month.month + 2);
    final total = view.nextMonthTotal;

    // Quanto da próxima fatura vem de compras feitas neste mês.
    bool inMonth(DateTime d) => d.year == month.year && d.month == month.month;
    final fromThisMonth = view.nextMonthCredit
        .where((t) => inMonth(t.date))
        .fold(0.0, (s, t) => s + t.amount);
    final fromOthers = total - fromThisMonth;
    final later = view.deferred
        .where((t) => !t.billDate!.isBefore(afterNext))
        .fold(0.0, (s, t) => s + t.amount);

    final byCard = totalsByCard(view.nextMonthCredit).entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    Widget line(String label, double value) => Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(children: [
            Expanded(child: Text(label, style: theme.textTheme.bodySmall)),
            Text(_money.format(value),
                style: theme.textTheme.bodySmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
          ]),
        );

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFBBF24).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border:
            Border.all(color: const Color(0xFFFBBF24).withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.update_rounded, color: Color(0xFFFBBF24)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Já comprometido em ${monthName(next)}',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(
                    'Gastos no crédito que você vai pagar no mês que vem.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(_money.format(total),
                style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFFFBBF24))),
          ]),
          const SizedBox(height: 8),
          if (fromThisMonth > 0)
            line('Compras feitas em ${monthName(month).toLowerCase()}',
                fromThisMonth),
          if (fromOthers > 0.004)
            line('Parcelas e compras anteriores', fromOthers),
          if (later > 0)
            line(
                'Parcelas de ${monthName(month).toLowerCase()} para depois '
                'de ${monthName(next).toLowerCase()}',
                later),
          // Com um cartão só, o valor dele é o próprio total.
          if (byCard.length > 1) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final e in byCard)
                _CardAmount(card: _card(e.key), amount: e.value),
            ]),
          ],
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onOpenNextMonth,
              icon: const Icon(Icons.arrow_forward_rounded, size: 18),
              label: Text('Ver ${monthName(next).toLowerCase()}'),
            ),
          ),
        ],
      ),
    );
  }
}

class _CardAmount extends StatelessWidget {
  final CreditCard? card;
  final double amount;

  const _CardAmount({required this.card, required this.amount});

  @override
  Widget build(BuildContext context) {
    final c = card;
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 10, 4),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        BankBadge(
            bank: c?.bank ?? 'Outros',
            color: c?.color ?? customBankColor,
            size: 22),
        const SizedBox(width: 6),
        Text('${c?.label ?? 'Outros'}  ${_money.format(amount)}',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}
