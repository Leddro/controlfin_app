import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';

import '../models/market/contribution.dart';
import '../models/tx.dart';
import '../models/user_settings.dart';
import 'expense_type_dialog.dart';
import 'info_button.dart';

final _money = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');

const _teal = Color(0xFF4ADE80);
const _amber = Color(0xFFFBBF24);
const _red = Color(0xFFF87171);

class GoalsCard extends StatelessWidget {
  final UserSettings settings;
  final List<Tx> txs;
  final VoidCallback onEdit;

  /// Toque numa meta de gasto (todas menos "Guardar"): filtra os lançamentos.
  final ValueChanged<String>? onSelectGoal;

  /// Meta usada no filtro dos lançamentos, destacada no cartão.
  final String? selectedGoal;

  /// Média mensal dos gastos essenciais dos últimos meses fechados, para a
  /// meta da reserva (0: usa os gastos deste mês).
  final double essentialAverage;

  const GoalsCard({
    super.key,
    required this.settings,
    required this.txs,
    required this.onEdit,
    this.onSelectGoal,
    this.selectedGoal,
    this.essentialAverage = 0,
  });

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

    final budgets = settings.effectiveBudgets;
    final expenses = txs.where((t) => t.type == TxType.expense);
    final spent = expenses.fold(0.0, (s, t) => s + t.amount);
    // Quanto foi gasto em cada meta, conforme a meta de cada tipo de gasto.
    final byGoal = <String, double>{};
    for (final t in expenses) {
      final goal = settings.budgetOf(t.category).name;
      byGoal[goal] = (byGoal[goal] ?? 0) + t.amount;
    }
    final needsName =
        budgets.firstWhere((b) => b.kind == BudgetKind.needs).name;
    final needs = byGoal[needsName] ?? 0;
    final left = income - spent;

    // Reserva: meses × gasto essencial mensal (média dos últimos meses; sem
    // histórico, o deste mês; sem gastos, 50% da renda). Mesma regra do
    // aporte na aba Investimentos.
    final status = reserveStatus(
      settings,
      essentialAverage: essentialAverage,
      currentMonthNeeds: needs,
    );
    final target = status.target;
    final reserve = status.saved;
    final reserveProgress = status.progress;
    final remaining = target - reserve;
    final saveShare =
        budgets.firstWhere((b) => b.kind == BudgetKind.save).percent / 100;
    final monthlySaving = income * saveShare;
    final monthsLeft = remaining <= 0 || monthlySaving <= 0
        ? 0
        : (remaining / monthlySaving).ceil();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: box,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text('Orçamento do mês',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
          ),
          InfoButton(
            key: const Key('info-goals'),
            title: 'Orçamento do mês',
            text: '${onSelectGoal != null ? 'Toque numa meta para ver os '
                    'gastos dela.\n\n' : ''}'
                'Cada meta é uma parte da sua renda. Em Ajustar você muda as '
                'porcentagens e escolhe em qual meta cada tipo de gasto '
                'conta.\n\n'
                'Reserva de emergência: ${settings.emergencyMonths} meses de '
                '${_money.format(status.monthlyBase)} de gastos essenciais '
                '(pela ${status.baseSource}).',
            sections: [
              for (final budget in budgets)
                InfoSection(budget.name, _budgetHint(budget, settings)),
            ],
            footer: 'Referência: regra 50/30/20 (Elizabeth Warren e Amelia '
                'Warren Tyagi) e a orientação comum de 3 a 6 meses de gastos '
                'essenciais na reserva. É um guia geral, não aconselhamento '
                'financeiro.',
          ),
          TextButton.icon(
            onPressed: onEdit,
            icon: const Icon(Icons.tune_rounded, size: 18),
            label: const Text('Ajustar'),
          ),
        ]),
        Text('Renda média: ${_money.format(income)}',
            style: theme.textTheme.bodyMedium),
        const SizedBox(height: 12),
        for (final budget in budgets)
          _GoalRow(
            label: '${budget.name} (${_percentLabel(budget.percent)}%)',
            value: budget.kind == BudgetKind.save
                ? left
                : byGoal[budget.name] ?? 0,
            goal: income * budget.percent / 100,
            saving: budget.kind == BudgetKind.save,
            selected: selectedGoal == budget.name,
            onTap: budget.kind == BudgetKind.save || onSelectGoal == null
                ? null
                : () => onSelectGoal!(budget.name),
          ),
        const Divider(height: 32),
        Text('Reserva de emergência',
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text('Meta: ${_money.format(target)} '
            '(${settings.emergencyMonths} meses de gastos essenciais)'),
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
              : 'Guardado: ${_money.format(reserve)}. Guardando ${_percentLabel(saveShare * 100)}% da renda, '
                  'faltam cerca de $monthsLeft ${monthsLeft == 1 ? 'mês' : 'meses'}.',
          style: theme.textTheme.bodyMedium,
        ),
      ]),
    );
  }
}

String _budgetHint(BudgetCategory budget, UserSettings settings) {
  if (budget.kind == BudgetKind.save) {
    return 'O que sobra da renda vira reserva e investimentos';
  }
  bool here(String category) => settings.budgetOf(category).name == budget.name;
  final fixed = expenseCategories.map((c) => c.name).toSet();
  final names = [
    for (final name in fixed)
      if (name != 'Outros' && here(name)) name,
    for (final type in settings.expenseTypes)
      if (!fixed.contains(type.name) && here(type.name)) type.name,
  ];
  if (budget.kind == BudgetKind.wants) {
    names.add('o que não está em outra meta');
  }
  if (names.isEmpty) return 'Nenhum tipo de gasto ligado a esta meta';
  return names.join(', ');
}

String _percentLabel(double percent) {
  if (percent == percent.roundToDouble()) return percent.toStringAsFixed(0);
  return percent.toStringAsFixed(1).replaceAll('.', ',');
}

class _GoalRow extends StatelessWidget {
  final String label;
  final double value;
  final double goal;
  final bool saving;
  final bool selected;
  final VoidCallback? onTap;

  const _GoalRow({
    required this.label,
    required this.value,
    required this.goal,
    this.saving = false,
    this.selected = false,
    this.onTap,
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

    final content =
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
            child: Text(label,
                style: const TextStyle(fontWeight: FontWeight.w700))),
        Text('${_money.format(shown)} de ${_money.format(goal)}'),
        if (onTap != null)
          Icon(Icons.chevron_right_rounded,
              size: 20, color: theme.colorScheme.outline),
      ]),
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
      Text(status, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
    ]);

    // Material próprio para o efeito de toque aparecer sobre o fundo do cartão.
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Ink(
            decoration: BoxDecoration(
              color: selected ? _amber.withValues(alpha: 0.08) : null,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected
                    ? _amber.withValues(alpha: 0.6)
                    : Colors.transparent,
              ),
            ),
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
            child: content,
          ),
        ),
      ),
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

class _BudgetDraft {
  final BudgetCategory category;
  final TextEditingController percent;

  _BudgetDraft(this.category, this.percent);
}

class _GoalsDialogState extends State<_GoalsDialog> {
  late final _income =
      TextEditingController(text: _fmt(widget.current.monthlyIncome));
  late final _reserve =
      TextEditingController(text: _fmt(widget.current.reserveSaved));
  late final _newName = TextEditingController();
  late final _newPercent = TextEditingController();
  late final List<_BudgetDraft> _rows = [
    for (final budget in widget.current.effectiveBudgets)
      _BudgetDraft(
          budget, TextEditingController(text: _percentLabel(budget.percent))),
  ];
  late final List<ExpenseType> _types = [...widget.current.expenseTypes];
  // Tipos criados junto com uma categoria nesta edição (somem se ela for removida).
  final Set<String> _autoCreated = {};
  late int _months = widget.current.emergencyMonths;
  String? _hint;
  String? _budgetError;

  String _fmt(double? v) =>
      v == null || v == 0 ? '' : v.toStringAsFixed(2).replaceAll('.', ',');

  double get _totalPercent => _rows.fold(0.0, (s, r) {
        final v = parseMoney(r.percent.text);
        return s + (v ?? 0);
      });

  @override
  void dispose() {
    _income.dispose();
    _reserve.dispose();
    _newName.dispose();
    _newPercent.dispose();
    for (final row in _rows) {
      row.percent.dispose();
    }
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

  void _addCategory() {
    final name = _newName.text.trim();
    final percent = parseMoney(_newPercent.text);
    if (name.isEmpty) {
      setState(() => _budgetError = 'Dê um nome para a categoria.');
      return;
    }
    if (name.length > 24) {
      setState(() => _budgetError = 'Use um nome com até 24 caracteres.');
      return;
    }
    if (percent == null || percent <= 0 || percent > 100) {
      setState(() => _budgetError =
          'Informe uma porcentagem maior que zero e de até 100.');
      return;
    }
    final taken = _rows.map((r) => r.category.name.toLowerCase()).toSet();
    if (taken.contains(name.toLowerCase())) {
      setState(() => _budgetError = 'Já existe uma categoria com esse nome.');
      return;
    }
    setState(() {
      final saveAt =
          _rows.indexWhere((r) => r.category.kind == BudgetKind.save);
      final draft = _BudgetDraft(
        BudgetCategory(name: name, percent: percent, kind: BudgetKind.custom),
        TextEditingController(text: _percentLabel(percent)),
      );
      _rows.insert(saveAt < 0 ? _rows.length : saveAt, draft);
      _linkType(name);
      _newName.clear();
      _newPercent.clear();
      _budgetError = null;
    });
  }

  /// Liga (ou cria) o tipo de gasto com o mesmo nome da categoria nova.
  void _linkType(String name) {
    final key = name.toLowerCase();
    final i = _types.indexWhere((t) => t.name.toLowerCase() == key);
    if (i >= 0) {
      _types[i] = _types[i].copyWith(goal: () => name);
    } else if (!expenseCategories.any((c) => c.name.toLowerCase() == key)) {
      _types.add(ExpenseType(
        name: name,
        color: nextExpenseTypeColor(_types),
        goal: name,
      ));
      _autoCreated.add(key);
    }
  }

  List<BudgetCategory> get _draftBudgets =>
      _rows.map((r) => r.category).toList();

  void _removeCategory(_BudgetDraft row) {
    final controller = row.percent;
    final key = row.category.name.toLowerCase();
    setState(() {
      _rows.remove(row);
      if (_autoCreated.remove(key)) {
        _types.removeWhere((t) => t.name.toLowerCase() == key);
      }
      for (var i = 0; i < _types.length; i++) {
        if (_types[i].goal?.toLowerCase() == key) {
          _types[i] = _types[i].copyWith(goal: () => null);
        }
      }
      _budgetError = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
  }

  void _save() {
    final income = parseMoney(_income.text);
    final budgets = <BudgetCategory>[];
    for (final row in _rows) {
      final percent = parseMoney(row.percent.text);
      if (percent == null || percent < 0 || percent > 100) {
        setState(() =>
            _budgetError = 'Cada porcentagem precisa ficar entre 0 e 100.');
        return;
      }
      budgets.add(row.category.copyWith(percent: percent));
    }
    Navigator.pop(
      context,
      widget.current.copyWith(
        monthlyIncome: () => income != null && income > 0 ? income : null,
        emergencyMonths: _months,
        reserveSaved: parseMoney(_reserve.text) ?? 0,
        budgets: budgets,
        expenseTypes: _types,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    return AlertDialog(
      title: const Text('Renda e orçamento'),
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
              const SizedBox(height: 20),
              const Text('Categorias e porcentagens',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(
                'A soma ideal é 100% da renda. Uma categoria nova acompanha os gastos lançados com o mesmo nome.',
                style: small,
              ),
              const SizedBox(height: 12),
              for (final row in _rows) ...[
                Row(children: [
                  Expanded(
                    child: Text(row.category.name,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  SizedBox(
                    width: 88,
                    child: TextField(
                      controller: row.percent,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setState(() => _budgetError = null),
                      decoration: const InputDecoration(
                        isDense: true,
                        suffixText: '%',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  if (row.category.kind == BudgetKind.custom)
                    IconButton(
                      tooltip: 'Remover',
                      onPressed: () => _removeCategory(row),
                      icon: const Icon(Icons.close_rounded),
                    )
                  else
                    const SizedBox(width: 48),
                ]),
                const SizedBox(height: 8),
              ],
              Text(
                'Total: ${_percentLabel(_totalPercent)}%',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: (_totalPercent - 100).abs() < 0.05 ? _teal : _amber,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('goal-new-name'),
                controller: _newName,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Nova categoria',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('goal-new-percent'),
                controller: _newPercent,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Porcentagem',
                  suffixText: '%',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _addCategory,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Adicionar categoria'),
                ),
              ),
              if (_budgetError != null)
                Text(_budgetError!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              if (_types.isNotEmpty) ...[
                const SizedBox(height: 20),
                const Text('Tipos de gasto',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text('Escolha em qual meta cada tipo de gasto conta.',
                    style: small),
                const SizedBox(height: 8),
                for (var i = 0; i < _types.length; i++)
                  Row(children: [
                    Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: Color(_types[i].color),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(_types[i].name)),
                    DropdownButton<String>(
                      key: Key('type-goal-${_types[i].name}'),
                      value:
                          goalFor(_draftBudgets, _types, _types[i].name).name,
                      items: [
                        for (final goal in spendingGoals(_draftBudgets))
                          DropdownMenuItem(
                              value: goal.name, child: Text(goal.name)),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() =>
                            _types[i] = _types[i].copyWith(goal: () => value));
                      },
                    ),
                  ]),
              ],
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
