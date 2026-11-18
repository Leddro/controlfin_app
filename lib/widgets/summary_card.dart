import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';

import '../models/tx.dart';

final _money = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');

/// Entradas, saídas e saldo do mês, com a divisão débito/crédito.
class SummaryCard extends StatelessWidget {
  final List<Tx> txs;

  const SummaryCard({super.key, required this.txs});

  double _sum(TxType type) =>
      txs.where((t) => t.type == type).fold(0.0, (s, t) => s + t.amount);

  @override
  Widget build(BuildContext context) {
    final income = _sum(TxType.income);
    final expense = _sum(TxType.expense);
    final balance = income - expense;
    final theme = Theme.of(context);
    Widget cell(String label, double v, Color color) => Expanded(
          child: Column(children: [
            Text(label,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelMedium),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(_money.format(v),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleSmall?.copyWith(
                      fontSize: 15, fontWeight: FontWeight.w800, color: color)),
            ),
          ]),
        );
    final credit = txs
        .where((t) => t.type == TxType.expense && t.isCredit)
        .fold(0.0, (s, t) => s + t.amount);
    Widget split(IconData icon, String label, double v, Color color) =>
        Expanded(
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('$label ${_money.format(v)}',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ),
            ),
          ]),
        );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(children: [
        Row(children: [
          cell('Entradas', income, const Color(0xFF4ADE80)),
          cell('Saídas', expense, const Color(0xFFF87171)),
          cell('Saldo', balance,
              balance >= 0 ? Colors.white : const Color(0xFFF87171)),
        ]),
        if (credit > 0) ...[
          const Divider(height: 24),
          Row(children: [
            split(Icons.bolt_rounded, 'Débito/Pix', expense - credit,
                const Color(0xFF2DD4BF)),
            const SizedBox(width: 12),
            split(Icons.credit_card_rounded, 'Crédito', credit,
                const Color(0xFFFBBF24)),
          ]),
        ],
      ]),
    );
  }
}
