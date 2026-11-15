import 'package:flutter/material.dart';

import '../models/user_settings.dart';

const expenseTypePalette = <int>[
  0xFF7C3AED,
  0xFFDB2777,
  0xFF0891B2,
  0xFF16A34A,
  0xFFCA8A04,
  0xFFDC2626,
  0xFF2563EB,
  0xFFEA580C,
  0xFF0F766E,
  0xFF9333EA,
  0xFF4F46E5,
  0xFF64748B,
];

/// Primeira cor da paleta que nenhum tipo usa (ou a próxima, em rodízio).
int nextExpenseTypeColor(List<ExpenseType> types) {
  final used = types.map((t) => t.color).toSet();
  for (final color in expenseTypePalette) {
    if (!used.contains(color)) return color;
  }
  return expenseTypePalette[types.length % expenseTypePalette.length];
}

/// Pede nome, cor e a meta em que o novo tipo de gasto conta.
/// [budgets] são as metas do usuário; "Guardar" não aparece como opção.
Future<ExpenseType?> showExpenseTypeDialog(
  BuildContext context,
  List<String> takenNames, {
  List<BudgetCategory> budgets = BudgetCategory.defaults,
}) {
  return showDialog<ExpenseType>(
    context: context,
    builder: (_) => _ExpenseTypeDialog(
      takenNames: takenNames,
      goals: spendingGoals(budgets),
    ),
  );
}

class _ExpenseTypeDialog extends StatefulWidget {
  final List<String> takenNames;
  final List<BudgetCategory> goals;

  const _ExpenseTypeDialog({required this.takenNames, required this.goals});

  @override
  State<_ExpenseTypeDialog> createState() => _ExpenseTypeDialogState();
}

class _ExpenseTypeDialogState extends State<_ExpenseTypeDialog> {
  final _name = TextEditingController();
  int _color = expenseTypePalette.first;
  late String _goal = widget.goals
      .firstWhere((b) => b.kind == BudgetKind.wants,
          orElse: () => widget.goals.first)
      .name;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Dê um nome para o tipo de gasto.');
      return;
    }
    if (name.length > 24) {
      setState(() => _error = 'Use um nome com até 24 caracteres.');
      return;
    }
    final taken = widget.takenNames.map((n) => n.toLowerCase()).toSet();
    if (taken.contains(name.toLowerCase())) {
      setState(() => _error = 'Esse tipo de gasto já existe.');
      return;
    }
    Navigator.pop(context, ExpenseType(name: name, color: _color, goal: _goal));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Novo tipo de gasto'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const Key('expense-type-name'),
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Nome',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Cor', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final color in expenseTypePalette)
              InkWell(
                key: Key('expense-type-color-$color'),
                onTap: () => setState(() => _color = color),
                customBorder: const CircleBorder(),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Color(color),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color:
                          _color == color ? Colors.white : Colors.transparent,
                      width: 3,
                    ),
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 16),
          const Text('Conta em qual meta?',
              style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(
            'Ex.: ração do pet pode ser Essenciais; brinquedos, Desejos.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final goal in widget.goals)
              ChoiceChip(
                key: Key('expense-type-goal-${goal.name}'),
                label: Text(goal.name),
                selected: _goal == goal.name,
                onSelected: (_) => setState(() => _goal = goal.name),
              ),
          ]),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _save, child: const Text('Criar')),
      ],
    );
  }
}
