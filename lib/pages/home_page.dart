import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/tx.dart';
import '../services/auth_service.dart';
import '../services/tx_service.dart';

final _money = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _service = TxService();
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  int? _touched;

  void _shift(int delta) =>
      setState(() => _month = DateTime(_month.year, _month.month + delta));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Finanças',
            style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            tooltip: 'Sair',
            icon: const Icon(Icons.logout_rounded),
            onPressed: AuthService().signOut,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(context),
        icon: const Icon(Icons.add),
        label: const Text('Adicionar'),
      ),
      body: StreamBuilder<List<Tx>>(
        stream: _service.watchMonth(_month),
        builder: (context, snap) {
          if (snap.hasError) {
            return const Center(
                child: Text('Não foi possível carregar seus lançamentos.'));
          }
          if (!snap.hasData)
            return const Center(child: CircularProgressIndicator());
          final txs = snap.data!;
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                children: [
                  _monthSelector(),
                  const SizedBox(height: 8),
                  _summary(txs),
                  const SizedBox(height: 24),
                  if (txs.isEmpty)
                    _empty()
                  else ...[
                    _breakdown(txs),
                    const SizedBox(height: 24),
                    _list(txs),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _monthSelector() {
    final label = toBeginningOfSentenceCase(
        DateFormat('MMMM yyyy', 'pt_BR').format(_month))!;
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(children: [
        cell('Entradas', income, const Color(0xFF0F766E)),
        cell('Saídas', expense, const Color(0xFFB91C1C)),
        cell('Saldo', balance,
            balance >= 0 ? const Color(0xFF14232B) : const Color(0xFFB91C1C)),
      ]),
    );
  }

  Widget _breakdown(List<Tx> txs) {
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
    final topCat = categoryOf(TxType.expense, top.key);
    final base = income > 0 ? income : expense;
    final headline = income > 0
        ? '${top.key} consome ${(top.value / base * 100).toStringAsFixed(0)}% da sua renda'
        : '${top.key} é ${(top.value / base * 100).toStringAsFixed(0)}% dos seus gastos';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(20)),
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
                  color: categoryOf(TxType.expense, sorted[i].key).color,
                  radius: _touched == i ? 40 : 32,
                  showTitle: false,
                ),
            ],
          )),
        ),
        const SizedBox(height: 16),
        for (final e in sorted) _categoryBar(e.key, e.value, expense),
      ]),
    );
  }

  Widget _categoryBar(String name, double value, double total) {
    final cat = categoryOf(TxType.expense, name);
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

  Widget _list(List<Tx> txs) {
    final df = DateFormat("dd 'de' MMM", 'pt_BR');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Lançamentos',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
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
          onDismissed: (_) {
            _service.delete(t.id!);
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Lançamento excluído.')));
          },
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              backgroundColor:
                  categoryOf(t.type, t.category).color.withValues(alpha: 0.14),
              child: Icon(categoryOf(t.type, t.category).icon,
                  color: categoryOf(t.type, t.category).color, size: 20),
            ),
            title: Text(t.description.isEmpty ? t.category : t.description),
            subtitle: Text('${t.category} • ${df.format(t.date)}'),
            trailing: Text(
              '${t.type == TxType.income ? '+' : '-'} ${_money.format(t.amount)}',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: t.type == TxType.income
                    ? const Color(0xFF0F766E)
                    : const Color(0xFFB91C1C),
              ),
            ),
          ),
        ),
    ]);
  }

  Widget _empty() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 64),
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
    final tx = await showModalBottomSheet<Tx>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _TxForm(
          initialDate: _month.month == DateTime.now().month &&
                  _month.year == DateTime.now().year
              ? DateTime.now()
              : _month),
    );
    if (tx != null) await _service.add(tx);
  }
}

class _TxForm extends StatefulWidget {
  final DateTime initialDate;
  const _TxForm({required this.initialDate});
  @override
  State<_TxForm> createState() => _TxFormState();
}

class _TxFormState extends State<_TxForm> {
  final _amount = TextEditingController();
  final _desc = TextEditingController();
  TxType _type = TxType.expense;
  String _category = 'Outros';
  bool _manualCategory = false;
  late DateTime _date = widget.initialDate;
  String? _error;

  List<Category> get _cats =>
      _type == TxType.expense ? expenseCategories : incomeCategories;

  void _save() {
    final value =
        double.tryParse(_amount.text.replaceAll('.', '').replaceAll(',', '.'));
    if (value == null || value <= 0) {
      setState(() => _error = 'Informe um valor maior que zero.');
      return;
    }
    Navigator.pop(
      context,
      Tx(
          type: _type,
          amount: value,
          category: _category,
          description: _desc.text.trim(),
          date: _date),
    );
  }

  @override
  Widget build(BuildContext context) {
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
              final sug = suggestCategory(_type, _desc.text);
              if (sug != null) _category = sug.name;
            }),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
                labelText: 'Valor',
                prefixText: r'R$ ',
                border: OutlineInputBorder()),
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
              final sug = suggestCategory(_type, text);
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
          ]),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.calendar_today_rounded, size: 18),
            label: Text(DateFormat('dd/MM/yyyy').format(_date)),
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
