import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../models/savings_goal.dart';
import '../models/tx.dart' show parseMoney;
import '../services/savings_goals_service.dart';
import '../widgets/app_header.dart';
import '../widgets/info_button.dart';

final _money = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
const _cardColor = Color(0xFF1A1A1A);
const _green = Color(0xFF4ADE80);
const _red = Color(0xFFF87171);

/// Ícones que o usuário pode escolher (a chave é o que vai para o Firestore).
const goalIcons = <String, IconData>{
  'travel': Icons.flight_rounded,
  'beach': Icons.beach_access_rounded,
  'renovation': Icons.format_paint_rounded,
  'house': Icons.house_rounded,
  'furniture': Icons.chair_rounded,
  'car': Icons.directions_car_rounded,
  'motorcycle': Icons.two_wheeler_rounded,
  'wedding': Icons.favorite_rounded,
  'party': Icons.celebration_rounded,
  'school': Icons.school_rounded,
  'phone': Icons.smartphone_rounded,
  'computer': Icons.computer_rounded,
  'game': Icons.sports_esports_rounded,
  'pets': Icons.pets_rounded,
  'health': Icons.medical_services_rounded,
  'gift': Icons.card_giftcard_rounded,
  'savings': Icons.savings_rounded,
  'star': Icons.star_rounded,
};

const goalColors = [
  0xFF38BDF8,
  0xFF4ADE80,
  0xFFFBBF24,
  0xFFF87171,
  0xFFF472B6,
  0xFFA78BFA,
  0xFF2DD4BF,
  0xFFFB923C,
  0xFFA3E635,
  0xFFE879F9,
];

IconData goalIcon(String key) => goalIcons[key] ?? Icons.star_rounded;

String _deadlineLabel(DateTime d) =>
    DateFormat("MMMM 'de' yyyy", 'pt_BR').format(d);

/// Situação da meta numa linha: conquistada, quanto guardar por mês ou
/// prazo vencido.
(String, Color?) goalStatus(SavingsGoal g, DateTime now) {
  if (g.done) return ('Conquistada!', _green);
  final monthly = g.monthlyNeeded(now);
  if (monthly != null) {
    return ('Guardar ${_money.format(monthly)} por mês', null);
  }
  if (g.monthsLeft(now) == 0) {
    return ('O prazo passou: faltam ${_money.format(g.remaining)}', _red);
  }
  return ('Faltam ${_money.format(g.remaining)}', null);
}

/// Aba Metas: o que o usuário quer conquistar em breve (Viagem, Reforma...).
class GoalsPage extends StatefulWidget {
  /// Permitem trocar o Firestore nos testes.
  final Stream<List<SavingsGoal>>? goals;
  final Future<void> Function(List<SavingsGoal>)? onSave;
  final DateTime Function()? now;

  /// Foto do topo (os testes passam uma sem Firebase).
  final Widget? avatar;

  const GoalsPage({super.key, this.goals, this.onSave, this.now, this.avatar});

  @override
  State<GoalsPage> createState() => _GoalsPageState();
}

class _GoalsPageState extends State<GoalsPage> {
  late final SavingsGoalsService? _service =
      widget.goals == null || widget.onSave == null
          ? SavingsGoalsService()
          : null;
  late final Stream<List<SavingsGoal>> _stream =
      (widget.goals ?? _service!.watch()).asBroadcastStream();
  List<SavingsGoal> _goals = const [];

  DateTime get _now => (widget.now ?? DateTime.now)();

  Future<void> _save(List<SavingsGoal> goals) async {
    try {
      await (widget.onSave ?? _service!.save)(goals);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Não foi possível salvar. Tente de novo.')));
    }
  }

  Future<void> _create([GoalSuggestion? suggestion]) async {
    final goal = await showGoalEditor(context, suggestion: suggestion);
    if (goal == null) return;
    await _save([..._goals, goal]);
  }

  Future<void> _deposit(SavingsGoal goal) async {
    final d = await showDepositDialog(context, goal);
    if (d == null) return;
    await _save(replaceGoal(_goals, goal.withDeposit(d)));
  }

  void _open(SavingsGoal goal) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => GoalDetailPage(
        goalId: goal.id,
        goals: _stream,
        initial: _goals,
        onSave: _save,
        now: _now,
        avatar: widget.avatar,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppHeader(
        title: 'Metas',
        avatar: widget.avatar,
        actions: const [
          InfoButton(
            title: 'Metas',
            text: 'Cadastre o que você quer conquistar em breve: uma viagem, '
                'uma reforma, um carro. Diga quanto custa e até quando quer '
                'conseguir, e o app mostra quanto separar por mês.\n\n'
                'Toque em Guardar sempre que separar dinheiro para uma meta. '
                'Se precisar usar parte dele, registre uma retirada.\n\n'
                'As metas não mudam os lançamentos da Início nem a divisão do '
                'salário em Investimentos.',
          ),
          SizedBox(width: 4),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('goal-new'),
        heroTag: 'goal-fab',
        onPressed: _create,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nova meta'),
      ),
      body: StreamBuilder<List<SavingsGoal>>(
        stream: _stream,
        builder: (context, snap) {
          if (snap.hasError) {
            return const Center(
                child: Text('Não foi possível carregar suas metas.'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          _goals = snap.data!;
          final goals = sortGoals(_goals);
          final suggestions = unusedSuggestions(_goals);
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                children: [
                  if (goals.isEmpty)
                    const _Empty()
                  else ...[
                    _Summary(goals: goals, now: _now),
                    for (final g in goals)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: _GoalCard(
                          goal: g,
                          now: _now,
                          onTap: () => _open(g),
                          onDeposit: () => _deposit(g),
                        ),
                      ),
                  ],
                  if (suggestions.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Text('Sugestões',
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final s in suggestions)
                        ActionChip(
                          key: Key('suggest-goal-${s.name}'),
                          avatar: Icon(goalIcon(s.icon),
                              size: 18, color: Color(s.color)),
                          label: Text(s.name),
                          onPressed: () => _create(s),
                        ),
                    ]),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Lista com a meta trocada pela versão nova (mesmo id).
List<SavingsGoal> replaceGoal(List<SavingsGoal> goals, SavingsGoal goal) => [
      for (final g in goals) g.id == goal.id ? goal : g,
    ];

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.flag_rounded, size: 40, color: theme.colorScheme.primary),
          const SizedBox(height: 12),
          Text('O que você quer conquistar?',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const Text('Escolha uma sugestão abaixo ou crie a sua.'),
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  final List<SavingsGoal> goals;
  final DateTime now;

  const _Summary({required this.goals, required this.now});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final saved = goals.fold(0.0, (s, g) => s + g.saved);
    final target = goals.fold(0.0, (s, g) => s + g.target);
    final monthly = goals.fold(0.0, (s, g) => s + (g.monthlyNeeded(now) ?? 0));
    return Container(
      key: const Key('goals-summary'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(children: [
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Guardado', style: theme.textTheme.bodySmall),
            Text(_money.format(saved),
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800)),
            Text('de ${_money.format(target)}',
                style: theme.textTheme.bodySmall),
          ]),
        ),
        if (monthly > 0)
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('Por mês', style: theme.textTheme.bodySmall),
            Text(_money.format(monthly),
                style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.primary)),
            Text('para os prazos', style: theme.textTheme.bodySmall),
          ]),
      ]),
    );
  }
}

class _GoalCard extends StatelessWidget {
  final SavingsGoal goal;
  final DateTime now;
  final VoidCallback onTap;
  final VoidCallback onDeposit;

  const _GoalCard({
    required this.goal,
    required this.now,
    required this.onTap,
    required this.onDeposit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = Color(goal.color);
    final (status, statusColor) = goalStatus(goal, now);
    return Material(
      key: Key('goal-${goal.id}'),
      color: _cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                GoalAvatar(goal: goal),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(goal.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 16)),
                      Text(
                        goal.deadline == null
                            ? 'Sem prazo'
                            : 'Até ${_deadlineLabel(goal.deadline!)}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Text('${(goal.progress * 100).floor()}%',
                    style:
                        TextStyle(fontWeight: FontWeight.w800, color: color)),
              ]),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: goal.progress,
                  minHeight: 8,
                  color: color,
                  backgroundColor: color.withValues(alpha: 0.12),
                ),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          '${_money.format(goal.saved)} de '
                          '${_money.format(goal.target)}',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(status,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: statusColor)),
                    ],
                  ),
                ),
                if (!goal.done)
                  FilledButton.tonalIcon(
                    key: Key('goal-deposit-${goal.id}'),
                    onPressed: onDeposit,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Guardar'),
                  ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

class GoalAvatar extends StatelessWidget {
  final SavingsGoal goal;
  final double radius;

  const GoalAvatar({super.key, required this.goal, this.radius = 22});

  @override
  Widget build(BuildContext context) {
    final color = Color(goal.color);
    return CircleAvatar(
      radius: radius,
      backgroundColor: color.withValues(alpha: 0.18),
      child: Icon(goalIcon(goal.icon), color: color, size: radius),
    );
  }
}

// ---------------------------------------------------------------- Detalhe

/// Uma meta: progresso, guardar/retirar, histórico, editar e excluir.
class GoalDetailPage extends StatefulWidget {
  final String goalId;
  final Stream<List<SavingsGoal>> goals;
  final List<SavingsGoal> initial;
  final Future<void> Function(List<SavingsGoal>) onSave;
  final DateTime now;
  final Widget? avatar;

  const GoalDetailPage({
    this.avatar,
    super.key,
    required this.goalId,
    required this.goals,
    required this.initial,
    required this.onSave,
    required this.now,
  });

  @override
  State<GoalDetailPage> createState() => _GoalDetailPageState();
}

class _GoalDetailPageState extends State<GoalDetailPage> {
  late List<SavingsGoal> _goals = widget.initial;

  SavingsGoal? get _goal {
    for (final g in _goals) {
      if (g.id == widget.goalId) return g;
    }
    return null;
  }

  /// Aplica na hora (a tela não espera o Firestore) e salva.
  Future<void> _apply(List<SavingsGoal> goals) async {
    setState(() => _goals = goals);
    await widget.onSave(goals);
  }

  Future<void> _deposit(SavingsGoal goal) async {
    final d = await showDepositDialog(context, goal);
    if (d == null) return;
    await _apply(replaceGoal(_goals, goal.withDeposit(d)));
  }

  Future<void> _edit(SavingsGoal goal) async {
    final updated = await showGoalEditor(context, initial: goal);
    if (updated == null) return;
    await _apply(replaceGoal(_goals, updated));
  }

  Future<void> _delete(SavingsGoal goal) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Excluir "${goal.name}"?'),
        content: const Text('O histórico do que foi guardado também some.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              key: const Key('goal-delete-confirm'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Excluir')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final rest = [
      for (final g in _goals)
        if (g.id != goal.id) g,
    ];
    Navigator.of(context).pop();
    await widget.onSave(rest);
  }

  Future<void> _removeDeposit(SavingsGoal goal, GoalDeposit d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Apagar este registro?'),
        content: Text('${d.amount >= 0 ? 'Guardado' : 'Retirada'} de '
            '${_money.format(d.amount.abs())} em '
            '${DateFormat('dd/MM/yyyy').format(d.date)}.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Apagar')),
        ],
      ),
    );
    if (ok != true) return;
    await _apply(replaceGoal(
        _goals, goal.copyWith(deposits: [...goal.deposits]..remove(d))));
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<SavingsGoal>>(
      stream: widget.goals,
      builder: (context, snap) {
        if (snap.hasData) _goals = snap.data!;
        final goal = _goal;
        if (goal == null) {
          return Scaffold(
              appBar: AppHeader(title: 'Meta', avatar: widget.avatar),
              body: const SizedBox.shrink());
        }
        return _build(context, goal);
      },
    );
  }

  Widget _build(BuildContext context, SavingsGoal goal) {
    final theme = Theme.of(context);
    final color = Color(goal.color);
    final (status, statusColor) = goalStatus(goal, widget.now);
    final history = goal.history;
    return Scaffold(
      appBar: AppHeader(
        title: goal.name,
        avatar: widget.avatar,
        actions: [
          IconButton(
            key: const Key('goal-edit'),
            tooltip: 'Editar meta',
            onPressed: () => _edit(goal),
            icon: const Icon(Icons.edit_rounded),
          ),
          IconButton(
            key: const Key('goal-delete'),
            tooltip: 'Excluir meta',
            onPressed: () => _delete(goal),
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: _cardColor,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: color.withValues(alpha: 0.4)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      GoalAvatar(goal: goal, radius: 26),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_money.format(goal.saved),
                                style: theme.textTheme.headlineSmall
                                    ?.copyWith(fontWeight: FontWeight.w800)),
                            Text('de ${_money.format(goal.target)}',
                                style: theme.textTheme.bodyMedium),
                          ],
                        ),
                      ),
                    ]),
                    const SizedBox(height: 16),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(5),
                      child: LinearProgressIndicator(
                        value: goal.progress,
                        minHeight: 10,
                        color: color,
                        backgroundColor: color.withValues(alpha: 0.12),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(status,
                        style: TextStyle(
                            fontWeight: FontWeight.w600, color: statusColor)),
                    Text(
                      goal.deadline == null
                          ? 'Sem prazo'
                          : 'Prazo: ${_deadlineLabel(goal.deadline!)}',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        key: const Key('goal-detail-deposit'),
                        onPressed: () => _deposit(goal),
                        icon: const Icon(Icons.swap_vert_rounded),
                        label: const Text('Guardar ou retirar'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text('Histórico',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              if (history.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text('Nada guardado ainda.',
                      style: theme.textTheme.bodySmall),
                ),
              for (final d in history)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    d.amount >= 0
                        ? Icons.arrow_upward_rounded
                        : Icons.arrow_downward_rounded,
                    color: d.amount >= 0 ? _green : _red,
                  ),
                  title: Text(
                      '${d.amount >= 0 ? '+' : '-'} '
                      '${_money.format(d.amount.abs())}',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(DateFormat('dd/MM/yyyy').format(d.date)),
                  trailing: IconButton(
                    tooltip: 'Apagar registro',
                    onPressed: () => _removeDeposit(goal, d),
                    icon: const Icon(Icons.close_rounded, size: 18),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Guardar

/// Pergunta quanto foi guardado ou retirado. Retirada vem negativa.
Future<GoalDeposit?> showDepositDialog(
        BuildContext context, SavingsGoal goal) =>
    showDialog<GoalDeposit>(
      context: context,
      builder: (_) => _DepositDialog(goal: goal),
    );

class _DepositDialog extends StatefulWidget {
  final SavingsGoal goal;

  const _DepositDialog({required this.goal});

  @override
  State<_DepositDialog> createState() => _DepositDialogState();
}

class _DepositDialogState extends State<_DepositDialog> {
  final _amount = TextEditingController();
  bool _withdraw = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _save() {
    final v = parseMoney(_amount.text);
    if (v == null || v <= 0) {
      setState(() => _error = 'Informe um valor maior que zero.');
      return;
    }
    if (_withdraw && v > widget.goal.saved + 0.004) {
      setState(() => _error =
          'Só há ${_money.format(widget.goal.saved)} guardados nesta meta.');
      return;
    }
    final now = DateTime.now();
    Navigator.pop(
      context,
      GoalDeposit(amount: _withdraw ? -v : v, date: now),
    );
  }

  @override
  Widget build(BuildContext context) {
    final remaining = widget.goal.remaining;
    return AlertDialog(
      title: Text(widget.goal.name),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.goal.saved > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Guardar')),
                  ButtonSegment(value: true, label: Text('Retirar')),
                ],
                selected: {_withdraw},
                onSelectionChanged: (s) => setState(() {
                  _withdraw = s.first;
                  _error = null;
                }),
              ),
            ),
          TextField(
            key: const Key('deposit-amount'),
            controller: _amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: _withdraw ? 'Quanto retirou' : 'Quanto guardou',
              helperText: !_withdraw && remaining > 0
                  ? 'Faltam ${_money.format(remaining)}'
                  : null,
              prefixText: r'R$ ',
              border: const OutlineInputBorder(),
              errorText: _error,
            ),
            onSubmitted: (_) => _save(),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
        FilledButton(
            key: const Key('deposit-save'),
            onPressed: _save,
            child: const Text('Salvar')),
      ],
    );
  }
}

// ---------------------------------------------------------------- Editor

/// Cria (a partir de uma sugestão ou do zero) ou edita uma meta.
Future<SavingsGoal?> showGoalEditor(
  BuildContext context, {
  SavingsGoal? initial,
  GoalSuggestion? suggestion,
}) =>
    showDialog<SavingsGoal>(
      context: context,
      builder: (_) => _GoalEditor(initial: initial, suggestion: suggestion),
    );

class _GoalEditor extends StatefulWidget {
  final SavingsGoal? initial;
  final GoalSuggestion? suggestion;

  const _GoalEditor({this.initial, this.suggestion});

  @override
  State<_GoalEditor> createState() => _GoalEditorState();
}

class _GoalEditorState extends State<_GoalEditor> {
  late final _name = TextEditingController(
      text: widget.initial?.name ?? widget.suggestion?.name);
  late final _target = TextEditingController(
      text: widget.initial == null
          ? ''
          : widget.initial!.target.toStringAsFixed(2).replaceAll('.', ','));
  final _already = TextEditingController();
  late String _icon = widget.initial?.icon ?? widget.suggestion?.icon ?? 'star';
  late int _color =
      widget.initial?.color ?? widget.suggestion?.color ?? goalColors.first;
  late DateTime? _deadline = widget.initial?.deadline;
  String? _error;

  bool get _isNew => widget.initial == null;

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    _already.dispose();
    super.dispose();
  }

  void _useSuggestion(GoalSuggestion s) => setState(() {
        _name.text = s.name;
        _icon = s.icon;
        _color = s.color;
      });

  Future<void> _pickDeadline() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _deadline ?? DateTime(now.year + 1, now.month, 1),
      firstDate: DateTime(now.year, now.month, 1),
      lastDate: DateTime(now.year + 30, 12, 31),
      initialDatePickerMode: DatePickerMode.year,
      helpText: 'Até quando?',
    );
    if (picked != null) {
      setState(() => _deadline = DateTime(picked.year, picked.month, 1));
    }
  }

  void _save() {
    final name = _name.text.trim();
    final target = parseMoney(_target.text);
    final already =
        _already.text.trim().isEmpty ? 0.0 : parseMoney(_already.text);
    if (name.isEmpty) {
      setState(() => _error = 'Dê um nome para a meta.');
      return;
    }
    if (target == null || target <= 0) {
      setState(() => _error = 'Informe quanto a meta custa.');
      return;
    }
    if (already == null || already < 0) {
      setState(() => _error = 'Valor já guardado inválido.');
      return;
    }
    final initial = widget.initial;
    if (initial != null) {
      Navigator.pop(
        context,
        initial.copyWith(
          name: name,
          icon: _icon,
          color: _color,
          target: target,
          deadline: () => _deadline,
        ),
      );
      return;
    }
    final now = DateTime.now();
    Navigator.pop(
      context,
      SavingsGoal(
        id: now.microsecondsSinceEpoch.toString(),
        name: name,
        icon: _icon,
        color: _color,
        target: target,
        deadline: _deadline,
        deposits: [
          if (already > 0) GoalDeposit(amount: already, date: now),
        ],
        createdAt: now,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(_isNew ? 'Nova meta' : 'Editar meta'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_isNew) ...[
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final s in goalSuggestions)
                    ChoiceChip(
                      label: Text(s.name),
                      selected: _name.text == s.name,
                      onSelected: (_) => _useSuggestion(s),
                    ),
                ]),
                const SizedBox(height: 16),
              ],
              TextField(
                key: const Key('goal-name'),
                controller: _name,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Nome',
                  hintText: 'Ex.: Viagem para o Nordeste',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('goal-target'),
                controller: _target,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Quanto custa',
                  prefixText: r'R$ ',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('goal-deadline'),
                    onPressed: _pickDeadline,
                    icon: const Icon(Icons.event_rounded, size: 18),
                    label: Text(_deadline == null
                        ? 'Escolher prazo'
                        : 'Até ${_deadlineLabel(_deadline!)}'),
                  ),
                ),
                if (_deadline != null)
                  IconButton(
                    tooltip: 'Sem prazo',
                    onPressed: () => setState(() => _deadline = null),
                    icon: const Icon(Icons.close_rounded),
                  ),
              ]),
              if (_isNew) ...[
                const SizedBox(height: 12),
                TextField(
                  key: const Key('goal-already'),
                  controller: _already,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Já tenho guardado (opcional)',
                    prefixText: r'R$ ',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Text('Ícone', style: theme.textTheme.labelLarge),
              const SizedBox(height: 6),
              Wrap(spacing: 4, runSpacing: 4, children: [
                for (final e in goalIcons.entries)
                  IconButton(
                    key: Key('goal-icon-${e.key}'),
                    isSelected: _icon == e.key,
                    style: IconButton.styleFrom(
                      backgroundColor: _icon == e.key
                          ? Color(_color).withValues(alpha: 0.2)
                          : null,
                    ),
                    color: _icon == e.key ? Color(_color) : null,
                    onPressed: () => setState(() => _icon = e.key),
                    icon: Icon(e.value),
                  ),
              ]),
              const SizedBox(height: 12),
              Text('Cor', style: theme.textTheme.labelLarge),
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final c in goalColors)
                  InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => setState(() => _color = c),
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: Color(c),
                        shape: BoxShape.circle,
                        border: _color == c
                            ? Border.all(color: Colors.white, width: 3)
                            : null,
                      ),
                    ),
                  ),
              ]),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
        FilledButton(
            key: const Key('goal-save'),
            onPressed: _save,
            child: const Text('Salvar')),
      ],
    );
  }
}
