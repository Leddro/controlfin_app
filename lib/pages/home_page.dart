import 'package:fl_chart/fl_chart.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/tx.dart';
import '../models/user_settings.dart';
import '../services/csv_import_service.dart';
import '../services/pdf_import_service.dart';
import '../services/settings_service.dart';
import '../services/tx_service.dart';
import '../widgets/app_logo.dart';
import '../widgets/expense_type_dialog.dart';
import '../widgets/goals_card.dart';
import '../widgets/pdf_import_sheet.dart';
import '../widgets/user_avatar.dart';

final _money = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');

class HomePage extends StatefulWidget {
  /// Chamado ao tocar na foto do usuário (abre a aba Conta).
  final VoidCallback? onOpenAccount;

  const HomePage({super.key, this.onOpenAccount});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _service = TxService();
  final _settingsService = SettingsService();
  UserSettings _settings = const UserSettings();
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  int? _touched;

  /// Filtro da lista: nulo = todos, [_incomeFilter] = ganhos, ou o nome de
  /// uma meta de gasto.
  String? _filter;
  static const _incomeFilter = '__ganhos__';
  final _listKey = GlobalKey();

  // Guardados para não reabrir a conexão com o Firestore a cada setState.
  late final Stream<UserSettings> _settingsStream = _settingsService.watch();
  late Stream<List<Tx>> _txStream = _service.watchMonth(_month);

  void _shift(int delta) => setState(() {
        _month = DateTime(_month.year, _month.month + delta);
        _txStream = _service.watchMonth(_month);
      });

  /// Aplica o filtro da meta e rola até a lista de lançamentos.
  void _showGoal(String goal) {
    setState(() => _filter = goal);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _listKey.currentContext;
      if (target == null) return;
      Scrollable.ensureVisible(
        target,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const Padding(
          padding: EdgeInsets.all(10),
          child: AppLogo(size: 32),
        ),
        // Encolhe em telas estreitas para caber o botão de importar.
        title: const FittedBox(
          fit: BoxFit.scaleDown,
          child: Text('ControlFin',
              style: TextStyle(
                  fontWeight: FontWeight.w800, color: Color(0xFFFBBF24))),
        ),
        actions: [
          MenuAnchor(
            alignmentOffset: const Offset(0, 4),
            builder: (context, controller, _) => FilledButton.icon(
              onPressed: () =>
                  controller.isOpen ? controller.close() : controller.open(),
              icon: const Icon(Icons.receipt_long_rounded, size: 18),
              label: const Text('Importar fatura'),
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                textStyle: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            menuChildren: [
              MenuItemButton(
                leadingIcon: const Icon(Icons.picture_as_pdf_rounded),
                onPressed: () => _importPdf(context),
                child: const Text('Fatura em PDF'),
              ),
              MenuItemButton(
                leadingIcon: const Icon(Icons.table_chart_rounded),
                onPressed: () => _importCsv(context),
                child: const Text('Arquivo CSV'),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 4, right: 12),
            child: Tooltip(
              message: 'Conta',
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: widget.onOpenAccount,
                child: const UserAvatar(radius: 17),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(context),
        icon: const Icon(Icons.add),
        label: const Text('Adicionar'),
      ),
      body: StreamBuilder<UserSettings>(
        stream: _settingsStream,
        builder: (context, settingsSnap) {
          final settings = settingsSnap.data ?? _settings;
          _settings = settings;
          return StreamBuilder<List<Tx>>(
            stream: _txStream,
            builder: (context, snap) {
              if (snap.hasError) {
                return const Center(
                    child: Text('Não foi possível carregar seus lançamentos.'));
              }
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final txs = snap.data!;
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  // Coluna inteira (não ListView) para a lista existir e o
                  // toque numa meta conseguir rolar até ela.
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _monthSelector(),
                          const SizedBox(height: 8),
                          _summary(txs),
                          const SizedBox(height: 16),
                          GoalsCard(
                            settings: settings,
                            txs: txs,
                            onEdit: () => _editGoals(settings),
                            onSelectGoal: _showGoal,
                            selectedGoal: _filter,
                          ),
                          const SizedBox(height: 16),
                          if (txs.isEmpty)
                            _empty()
                          else ...[
                            _breakdown(txs, settings),
                            const SizedBox(height: 24),
                            _list(txs, settings),
                          ],
                        ]),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _editGoals(UserSettings current) async {
    final result =
        await showGoalsDialog(context, current, _service.averageIncome);
    if (result != null) await _settingsService.save(result);
  }

  Future<void> _importPdf(BuildContext context) async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (file == null || !context.mounted) return;

    final bytes = await file.readAsBytes();
    if (!context.mounted) return;

    final txs = await showModalBottomSheet<List<Tx>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ImportReviewSheet(
        bytes: bytes,
        defaultDate: DateTime(_month.year, _month.month, 1),
        parser: PdfImportService.parse,
        title: 'Importar fatura',
        expenseTypes: _settings.expenseTypes,
        loadExisting: _service.fetchRange,
      ),
    );
    if (txs != null && txs.isNotEmpty) await _service.addAll(txs);
  }

  Future<void> _importCsv(BuildContext context) async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['csv', 'txt'],
    );
    if (file == null || !context.mounted) return;

    final bytes = await file.readAsBytes();
    if (!context.mounted) return;

    final txs = await showModalBottomSheet<List<Tx>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ImportReviewSheet(
        bytes: bytes,
        defaultDate: DateTime(_month.year, _month.month, 1),
        parser: (b) async => CsvImportService.parse(b),
        title: 'Importar CSV',
        expenseTypes: _settings.expenseTypes,
        loadExisting: _service.fetchRange,
      ),
    );
    if (txs != null && txs.isNotEmpty) await _service.addAll(txs);
  }

  Future<void> _editTx(Tx tx) async {
    final result = await showModalBottomSheet<Tx>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _TxForm(
        initialDate: tx.date,
        editTx: tx,
        settings: _settings,
        onSaveSettings: _persistSettings,
      ),
    );
    if (result != null) await _service.update(result);
  }

  Widget _monthSelector() {
    final label = toBeginningOfSentenceCase(
        DateFormat('MMMM yyyy', 'pt_BR').format(_month));
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
            onPressed: () => _shift(-1),
            icon: const Icon(Icons.chevron_left_rounded)),
        SizedBox(
          width: 180,
          child: Text(label,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
        ),
        IconButton(
            onPressed: () => _shift(1),
            icon: const Icon(Icons.chevron_right_rounded)),
      ],
    );
  }

  Widget _summary(List<Tx> txs) {
    final income = _sum(txs, TxType.income);
    final expense = _sum(txs, TxType.expense);
    final balance = income - expense;
    final theme = Theme.of(context);
    Widget cell(String label, double v, Color color) => Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(_money.format(v),
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800, color: color)),
            ),
          ]),
        );
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(children: [
        cell('Entradas', income, const Color(0xFF4ADE80)),
        cell('Saídas', expense, const Color(0xFFF87171)),
        cell('Saldo', balance,
            balance >= 0 ? Colors.white : const Color(0xFFF87171)),
      ]),
    );
  }

  Future<void> _persistSettings(UserSettings next) async {
    _settings = next;
    await _settingsService.save(next);
  }

  Widget _breakdown(List<Tx> txs, UserSettings settings) {
    final theme = Theme.of(context);
    final expense = _sum(txs, TxType.expense);
    final income = _sum(txs, TxType.income);
    if (expense == 0) return const SizedBox.shrink();

    final totals = <String, double>{};
    for (final t in txs.where((t) => t.type == TxType.expense)) {
      totals[t.category] = (totals[t.category] ?? 0) + t.amount;
    }
    final sorted = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = sorted.first;
    final topCat =
        categoryOf(TxType.expense, top.key, extra: settings.expenseTypes);
    final base = income > 0 ? income : expense;
    final headline = income > 0
        ? '${top.key} consome ${(top.value / base * 100).toStringAsFixed(0)}% da sua renda'
        : '${top.key} é ${(top.value / base * 100).toStringAsFixed(0)}% dos seus gastos';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(headline,
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w800, color: topCat.color)),
        const SizedBox(height: 4),
        Text('Para onde foram suas saídas', style: theme.textTheme.bodyMedium),
        const SizedBox(height: 20),
        SizedBox(
          height: 220,
          child: PieChart(PieChartData(
            centerSpaceRadius: 64,
            sectionsSpace: 3,
            pieTouchData: PieTouchData(touchCallback: (event, resp) {
              setState(
                  () => _touched = resp?.touchedSection?.touchedSectionIndex);
            }),
            sections: [
              for (var i = 0; i < sorted.length; i++)
                PieChartSectionData(
                  value: sorted[i].value,
                  color: categoryOf(TxType.expense, sorted[i].key,
                          extra: settings.expenseTypes)
                      .color,
                  radius: _touched == i ? 40 : 32,
                  showTitle: false,
                ),
            ],
          )),
        ),
        const SizedBox(height: 16),
        for (final e in sorted)
          _categoryBar(e.key, e.value, expense, settings.expenseTypes),
      ]),
    );
  }

  Widget _categoryBar(
      String name, double value, double total, List<ExpenseType> types) {
    final cat = categoryOf(TxType.expense, name, extra: types);
    final pct = value / total;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(children: [
        Row(children: [
          Icon(cat.icon, size: 18, color: cat.color),
          const SizedBox(width: 8),
          Expanded(
              child: Text(name,
                  style: const TextStyle(fontWeight: FontWeight.w600))),
          Text(_money.format(value)),
          SizedBox(
            width: 52,
            child: Text('${(pct * 100).toStringAsFixed(0)}%',
                textAlign: TextAlign.right,
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: pct,
            minHeight: 8,
            color: cat.color,
            backgroundColor: cat.color.withValues(alpha: 0.12),
          ),
        ),
      ]),
    );
  }

  String _subtitle(Tx t) {
    final date = DateFormat("dd 'de' MMM", 'pt_BR').format(t.date);
    final extra = switch (t.kind) {
      TxKind.installment => ' • Parcela ${t.index}/${t.count}',
      TxKind.recurring => ' • Mensal',
      TxKind.single => '',
    };
    return '${t.category} • $date$extra';
  }

  Widget _list(List<Tx> all, UserSettings settings) {
    final theme = Theme.of(context);
    final goals = spendingGoals(settings.effectiveBudgets);
    // Meta removida ou renomeada: volta a mostrar tudo.
    final filter = _filter == null ||
            _filter == _incomeFilter ||
            goals.any((g) => g.name == _filter)
        ? _filter
        : null;

    final txs = switch (filter) {
      null => all,
      _incomeFilter => all.where((t) => t.type == TxType.income).toList(),
      final goal => all
          .where((t) =>
              t.type == TxType.expense &&
              settings.budgetOf(t.category).name == goal)
          .toList(),
    };
    final total = txs.fold(0.0, (s, t) => s + t.amount);

    Widget chip(String label, String? value) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            key: Key('filter-${value ?? 'todos'}'),
            label: Text(label),
            selected: filter == value,
            onSelected: (_) => setState(() =>
                _filter = filter == value && value != null ? null : value),
          ),
        );

    return Column(
        key: _listKey,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Lançamentos',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              chip('Todos', null),
              for (final goal in goals) chip(goal.name, goal.name),
              chip('Ganhos', _incomeFilter),
            ]),
          ),
          if (filter != null) ...[
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: Text(
                  '${txs.length} lançamento${txs.length == 1 ? '' : 's'} • '
                  '${_money.format(total)}',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              TextButton.icon(
                onPressed: () => setState(() => _filter = null),
                icon: const Icon(Icons.filter_alt_off_rounded, size: 18),
                label: const Text('Limpar filtro'),
              ),
            ]),
          ],
          const SizedBox(height: 4),
          if (txs.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  filter == _incomeFilter
                      ? 'Nenhum ganho neste mês.'
                      : 'Nenhum gasto em $filter neste mês.',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ),
          for (final t in txs)
            Dismissible(
              key: ValueKey(t.id),
              direction: DismissDirection.endToStart,
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 20),
                color: Colors.red.shade100,
                child: const Icon(Icons.delete_outline_rounded),
              ),
              // A exclusão é feita aqui; o item some quando o Firestore atualiza a lista.
              confirmDismiss: (_) async {
                await _confirmDelete(t);
                return false;
              },
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                onTap: () => _editTx(t),
                leading: CircleAvatar(
                  backgroundColor: categoryOf(t.type, t.category,
                          extra: settings.expenseTypes)
                      .color
                      .withValues(alpha: 0.20),
                  child: Icon(
                      categoryOf(t.type, t.category,
                              extra: settings.expenseTypes)
                          .icon,
                      color: categoryOf(t.type, t.category,
                              extra: settings.expenseTypes)
                          .color,
                      size: 20),
                ),
                title: Text(t.description.isEmpty ? t.category : t.description),
                subtitle: Text(_subtitle(t)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${t.type == TxType.income ? '+' : '-'} ${_money.format(t.amount)}',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: t.type == TxType.income
                            ? const Color(0xFF4ADE80)
                            : const Color(0xFFF87171),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, size: 20),
                      color: const Color(0xFFF87171),
                      onPressed: () => _confirmDelete(t),
                    ),
                  ],
                ),
              ),
            ),
        ]);
  }

  Future<void> _confirmDelete(Tx t) async {
    if (t.groupId == null) {
      await _service.deleteOne(t.id!);
      return;
    }

    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir lançamento'),
        content: Text(t.kind == TxKind.installment
            ? 'Esta é a parcela ${t.index} de ${t.count}.'
            : 'Este lançamento se repete todo mês.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, 'one'),
              child: const Text('Só este')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, 'next'),
              child: const Text('Este e os próximos')),
        ],
      ),
    );

    if (choice == 'one') await _service.deleteOne(t.id!);
    if (choice == 'next') await _service.deleteGroupFrom(t.groupId!, t.date);
  }

  Widget _empty() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Column(children: [
          const Icon(Icons.receipt_long_rounded, size: 48),
          const SizedBox(height: 12),
          Text('Nenhum lançamento neste mês.',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text('Toque em Adicionar para registrar um ganho ou gasto.'),
        ]),
      );

  double _sum(List<Tx> txs, TxType type) =>
      txs.where((t) => t.type == type).fold(0.0, (s, t) => s + t.amount);

  Future<void> _openForm(BuildContext context) async {
    final now = DateTime.now();
    final sameMonth = _month.month == now.month && _month.year == now.year;
    final list = await showModalBottomSheet<List<Tx>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _TxForm(
          initialDate:
              sameMonth ? DateTime(now.year, now.month, now.day) : _month,
          settings: _settings,
          onSaveSettings: _persistSettings),
    );
    if (list != null) await _service.addAll(list);
  }
}

class _TxForm extends StatefulWidget {
  final DateTime initialDate;
  final Tx? editTx;
  final UserSettings settings;
  final Future<void> Function(UserSettings next) onSaveSettings;
  const _TxForm({
    required this.initialDate,
    required this.settings,
    required this.onSaveSettings,
    this.editTx,
  });
  @override
  State<_TxForm> createState() => _TxFormState();
}

class _TxFormState extends State<_TxForm> {
  static const _recurringOptions = [6, 12, 24, 36];
  static const _installmentOptions = [2, 3, 4, 5, 6, 10, 12, 18, 24];

  final _amount = TextEditingController();
  final _desc = TextEditingController();
  TxType _type = TxType.expense;
  TxKind _kind = TxKind.single;
  int _count = 12;
  int _currentIndex = 1;
  String _category = 'Outros';
  bool _manualCategory = false;
  late DateTime _date = widget.initialDate;
  String? _error;
  final List<ExpenseType> _created = [];

  bool get _isEditing => widget.editTx != null;

  List<ExpenseType> get _types {
    final seen = <String>{};
    return [
      for (final type in [...widget.settings.expenseTypes, ..._created])
        if (seen.add(type.name.toLowerCase())) type,
    ];
  }

  List<Category> get _cats => categoriesFor(_type, extra: _types);

  @override
  void initState() {
    super.initState();
    if (widget.editTx != null) {
      final t = widget.editTx!;
      _amount.text = t.amount.toStringAsFixed(2).replaceAll('.', ',');
      _desc.text = t.description;
      _type = t.type;
      _category = t.category;
      _date = t.date;
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _desc.dispose();
    super.dispose();
  }

  void _save() {
    final value = parseMoney(_amount.text);
    if (value == null || value <= 0) {
      setState(() => _error = 'Informe um valor maior que zero.');
      return;
    }
    if (_isEditing) {
      final t = widget.editTx!;
      Navigator.pop(
        context,
        Tx(
          id: t.id,
          type: _type,
          amount: value,
          category: _category,
          description: _desc.text.trim(),
          date: DateTime(_date.year, _date.month, _date.day),
          groupId: t.groupId,
          kind: t.kind,
          index: t.index,
          count: t.count,
        ),
      );
    } else {
      Navigator.pop(
        context,
        buildSeries(
          type: _type,
          amount: value,
          category: _category,
          description: _desc.text.trim(),
          start: DateTime(_date.year, _date.month, _date.day),
          kind: _kind,
          count: _count,
          startIndex: _kind == TxKind.installment ? _currentIndex : 1,
          perInstallment: _kind == TxKind.installment,
        ),
      );
    }
  }

  String? _preview() {
    final value = parseMoney(_amount.text);
    if (_kind == TxKind.installment) {
      if (value == null || value <= 0) return null;
      final total = value * _count;
      final remaining = _count - _currentIndex + 1;
      return 'Total: ${_money.format(total)}. Faltam $remaining parcelas de ${_money.format(value)}.';
    }
    if (_kind == TxKind.recurring) {
      return 'Será lançado todo mês, por $_count meses, a partir de ${DateFormat('dd/MM/yyyy').format(_date)}.';
    }
    return null;
  }

  Future<void> _createType() async {
    final created = await showExpenseTypeDialog(
      context,
      [
        ...expenseCategories.map((c) => c.name),
        ..._types.map((t) => t.name),
      ],
      budgets: widget.settings.effectiveBudgets,
    );
    if (created == null || !mounted) return;
    final seen = <String>{};
    final types = <ExpenseType>[
      for (final type in [
        ...widget.settings.expenseTypes,
        ..._created,
        created
      ])
        if (seen.add(type.name.toLowerCase())) type,
    ];
    final next = widget.settings.copyWith(expenseTypes: types);
    await widget.onSaveSettings(next);
    if (!mounted) return;
    setState(() {
      _created.add(created);
      _category = created.name;
      _manualCategory = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = _preview();
    final options =
        _kind == TxKind.installment ? _installmentOptions : _recurringOptions;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SegmentedButton<TxType>(
            segments: const [
              ButtonSegment(value: TxType.expense, label: Text('Gasto')),
              ButtonSegment(value: TxType.income, label: Text('Ganho')),
            ],
            selected: {_type},
            onSelectionChanged: (s) => setState(() {
              _type = s.first;
              _category = 'Outros';
              _manualCategory = false;
              if (_type == TxType.income && _kind == TxKind.installment) {
                _kind = TxKind.single;
              }
              final sug = suggestCategory(_type, _desc.text, extra: _types);
              if (sug != null) _category = sug.name;
            }),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText:
                  _kind == TxKind.installment ? 'Valor da parcela' : 'Valor',
              prefixText: r'R$ ',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _desc,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
                labelText: 'Descrição (ex.: Mercado, Aluguel, Salário)',
                border: OutlineInputBorder()),
            onChanged: (text) {
              if (_manualCategory) return;
              final sug = suggestCategory(_type, text, extra: _types);
              if (sug != null) setState(() => _category = sug.name);
            },
          ),
          const SizedBox(height: 16),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final c in _cats)
              ChoiceChip(
                avatar: Icon(c.icon, size: 18, color: c.color),
                label: Text(c.name),
                selected: _category == c.name,
                onSelected: (_) => setState(() {
                  _category = c.name;
                  _manualCategory = true;
                }),
              ),
            if (_type == TxType.expense)
              ActionChip(
                avatar: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Novo tipo'),
                onPressed: _createType,
              ),
          ]),
          if (!_isEditing) ...[
            const SizedBox(height: 16),
            SegmentedButton<TxKind>(
              segments: [
                const ButtonSegment(value: TxKind.single, label: Text('Única')),
                const ButtonSegment(
                    value: TxKind.recurring, label: Text('Todo mês')),
                if (_type == TxType.expense)
                  const ButtonSegment(
                      value: TxKind.installment, label: Text('Parcelada')),
              ],
              selected: {_kind},
              onSelectionChanged: (s) => setState(() {
                _kind = s.first;
                _count = _kind == TxKind.installment ? 3 : 12;
                _currentIndex = 1;
              }),
            ),
            if (_kind != TxKind.single) ...[
              const SizedBox(height: 12),
              Text(
                  _kind == TxKind.installment
                      ? 'Número de parcelas'
                      : 'Repetir por',
                  style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final n in options)
                  ChoiceChip(
                    label: Text(
                        _kind == TxKind.installment ? '${n}x' : '$n meses'),
                    selected: _count == n,
                    onSelected: (_) => setState(() {
                      _count = n;
                      if (_currentIndex > n) _currentIndex = 1;
                    }),
                  ),
              ]),
              if (_kind == TxKind.installment) ...[
                const SizedBox(height: 12),
                Text('Qual parcela você está?',
                    style: theme.textTheme.labelLarge),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (var i = 1; i <= _count; i++)
                    ChoiceChip(
                      label: Text('$i'),
                      selected: _currentIndex == i,
                      onSelected: (_) => setState(() => _currentIndex = i),
                    ),
                ]),
              ],
              if (preview != null) ...[
                const SizedBox(height: 8),
                Text(preview, style: theme.textTheme.bodyMedium),
              ],
            ],
          ],
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.calendar_today_rounded, size: 18),
            label: Text(_kind == TxKind.single
                ? DateFormat('dd/MM/yyyy').format(_date)
                : 'Primeiro lançamento: ${DateFormat('dd/MM/yyyy').format(_date)}'),
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _date,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (picked != null) setState(() => _date = picked);
            },
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _save,
            style:
                FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            child: const Text('Salvar'),
          ),
        ]),
      ),
    );
  }
}
