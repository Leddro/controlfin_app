import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/tx.dart';
import '../models/user_settings.dart';

final _money = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');

const _teal = Color(0xFF4ADE80);
const _amber = Color(0xFFFBBF24);
const _red = Color(0xFFF87171);

class GoalsCard extends StatelessWidget {
  final UserSettings settings;
  final List<Tx> txs;
  final VoidCallback onEdit;

  const GoalsCard(
      {super.key,
      required this.settings,
      required this.txs,
      required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final box = BoxDecoration(
      color: const Color(0xFF1A1A1A),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
    );

    final income = settings.monthlyIncome ?? 0;

    if (income <= 0) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: box,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Defina sua renda média mensal',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const Text(
              'Com ela, o app calcula quanto você pode gastar em cada área '
              'e quanto guardar para a reserva de emergência.'),
          const SizedBox(height: 12),
          FilledButton.tonal(
              onPressed: onEdit, child: const Text('Definir renda')),
        ]),
      );
    }

    final expenses = txs.where((t) => t.type == TxType.expense);
    final spent = expenses.fold(0.0, (s, t) => s + t.amount);
    final needs = expenses
        .where((t) => needsCategoryNames.contains(t.category))
        .fold(0.0, (s, t) => s + t.amount);
    final wants = spent - needs;
    final left = income - spent;

    // Reserva: meses × gastos essenciais (reais do mês; se ainda não há, 50% da renda).
    final base = needs > 0 ? needs : income * 0.5;
    final target = base * settings.emergencyMonths;
    final reserve = settings.reserveSaved;
    final reserveProgress =
        target <= 0 ? 0.0 : (reserve / target).clamp(0.0, 1.0).toDouble();
    final remaining = target - reserve;
    final monthsLeft = remaining <= 0 ? 0 : (remaining / (income * 0.2)).ceil();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: box,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text('Suas metas do mês',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
          ),
          TextButton.icon(
            onPressed: onEdit,
            icon: const Icon(Icons.tune_rounded, size: 18),
            label: const Text('Ajustar'),
          ),
        ]),
        Text('Renda média: ${_money.format(income)}',
            style: theme.textTheme.bodyMedium),
        const SizedBox(height: 16),
        _GoalRow(
          label: 'Essenciais (50%)',
          hint: 'Moradia, alimentação, transporte, contas, saúde e educação',
          value: needs,
          goal: income * 0.5,
        ),
        _GoalRow(
          label: 'Desejos (30%)',
          hint: 'Lazer, compras e outros',
          value: wants,
          goal: income * 0.3,
        ),
        _GoalRow(
          label: 'Guardar (20%)',
          hint: 'O que sobra da renda vira reserva e investimentos',
          value: left,
          goal: income * 0.2,
          saving: true,
        ),
        const Divider(height: 32),
        Text('Reserva de emergência',
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(
            'Meta: ${_money.format(target)} (${settings.emergencyMonths} meses de gastos essenciais)'),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: reserveProgress,
            minHeight: 10,
            color: _teal,
            backgroundColor: _teal.withValues(alpha: 0.12),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          remaining <= 0
              ? 'Reserva completa: ${_money.format(reserve)} guardados.'
              : 'Guardado: ${_money.format(reserve)}. Guardando 20% da renda, '
                  'faltam cerca de $monthsLeft ${monthsLeft == 1 ? 'mês' : 'meses'}.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        Text(
          'Referência: regra 50/30/20 (Elizabeth Warren e Amelia Warren Tyagi) e a orientação '
          'comum de 3 a 6 meses de gastos essenciais na reserva. É um guia geral, não '
          'aconselhamento financeiro.',
          style: theme.textTheme.bodySmall,
        ),
      ]),
    );
  }
}

class _GoalRow extends StatelessWidget {
  final String label;
  final String hint;
  final double value;
  final double goal;
  final bool saving;

  const _GoalRow({
    required this.label,
    required this.hint,
    required this.value,
    required this.goal,
    this.saving = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shown = value < 0 ? 0.0 : value;
    final progress =
        goal <= 0 ? 0.0 : (shown / goal).clamp(0.0, 1.0).toDouble();

    late final Color color;
    late final String status;

    if (saving) {
      color = value >= goal ? _teal : (value < 0 ? _red : _amber);
      status = value >= goal
          ? 'Meta batida'
          : value < 0
              ? 'Gastos acima da renda'
              : 'Faltam ${_money.format(goal - value)}';
    } else if (value > goal) {
      color = _red;
      status = 'Passou ${_money.format(value - goal)} da meta';
    } else {
      color = progress >= 0.85 ? _amber : _teal;
      status = 'Restam ${_money.format(goal - value)}';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: Text(label,
                  style: const TextStyle(fontWeight: FontWeight.w700))),
          Text('${_money.format(shown)} de ${_money.format(goal)}'),
        ]),
        Text(hint, style: theme.textTheme.bodySmall),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            color: color,
            backgroundColor: color.withValues(alpha: 0.12),
          ),
        ),
        const SizedBox(height: 4),
        Text(status,
            style: TextStyle(color: color, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

Future<UserSettings?> showGoalsDialog(
  BuildContext context,
  UserSettings current,
  Future<double?> Function() suggestAverage,
) {
  return showDialog<UserSettings>(
    context: context,
    builder: (_) =>
        _GoalsDialog(current: current, suggestAverage: suggestAverage),
  );
}

class _GoalsDialog extends StatefulWidget {
  final UserSettings current;
  final Future<double?> Function() suggestAverage;

  const _GoalsDialog({required this.current, required this.suggestAverage});

  @override
  State<_GoalsDialog> createState() => _GoalsDialogState();
}

class _GoalsDialogState extends State<_GoalsDialog> {
  late final _income =
      TextEditingController(text: _fmt(widget.current.monthlyIncome));
  late final _reserve =
      TextEditingController(text: _fmt(widget.current.reserveSaved));
  late int _months = widget.current.emergencyMonths;
  String? _hint;

  String _fmt(double? v) =>
      v == null || v == 0 ? '' : v.toStringAsFixed(2).replaceAll('.', ',');

  @override
  void dispose() {
    _income.dispose();
    _reserve.dispose();
    super.dispose();
  }

  Future<void> _useAverage() async {
    final v = await widget.suggestAverage();
    if (!mounted) return;
    setState(() {
      if (v == null) {
        _hint = 'Ainda não há ganhos registrados nos últimos 3 meses.';
      } else {
        _income.text = _fmt(v);
        _hint = null;
      }
    });
  }

  void _save() {
    final income = parseMoney(_income.text);
    Navigator.pop(
      context,
      UserSettings(
        monthlyIncome: income != null && income > 0 ? income : null,
        emergencyMonths: _months,
        reserveSaved: parseMoney(_reserve.text) ?? 0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    return AlertDialog(
      title: const Text('Renda e metas'),
      content: SingleChildScrollView(
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _income,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'Renda média mensal',
                    prefixText: r'R$ ',
                    border: OutlineInputBorder()),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                    onPressed: _useAverage,
                    child: const Text('Usar média dos últimos 3 meses')),
              ),
              if (_hint != null) Text(_hint!, style: small),
              const SizedBox(height: 12),
              const Text(
                  'Reserva de emergência: quantos meses de gastos essenciais?',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [
                for (final m in [3, 6, 9, 12])
                  ChoiceChip(
                    label: Text('$m meses'),
                    selected: _months == m,
                    onSelected: (_) => setState(() => _months = m),
                  ),
              ]),
              const SizedBox(height: 6),
              Text(
                  '3 meses: renda estável (CLT, servidor). 6 meses: padrão mais comum. '
                  '12 meses: autônomo ou renda variável.',
                  style: small),
              const SizedBox(height: 16),
              TextField(
                controller: _reserve,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'Já tenho guardado na reserva',
                    prefixText: r'R$ ',
                    border: OutlineInputBorder()),
              ),
            ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
        FilledButton(onPressed: _save, child: const Text('Salvar')),
      ],
    );
  }
}
