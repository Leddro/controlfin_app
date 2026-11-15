import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/tx.dart';
import '../models/user_settings.dart';
import '../services/pdf_import_service.dart';

final _money = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
final _day = DateFormat('dd/MM/yyyy');

/// Chave para achar lançamentos repetidos: dia e valor em centavos.
String _dupKey(DateTime date, double amount) =>
    '${date.year}-${date.month}-${date.day}|${(amount * 100).round()}';

/// Bottom sheet que recebe os bytes de um arquivo (PDF ou CSV), extrai os
/// lançamentos e deixa o usuário categorizar cada um antes de salvar.
class ImportReviewSheet extends StatefulWidget {
  final Uint8List bytes;
  final DateTime defaultDate;
  final Future<List<ParsedItem>> Function(Uint8List) parser;
  final String title;
  final List<ExpenseType> expenseTypes;

  /// Lançamentos já salvos entre duas datas (inclusive), para desmarcar o
  /// que já foi importado antes (ex.: o PDF e o CSV da mesma fatura).
  final Future<List<Tx>> Function(DateTime from, DateTime to)? loadExisting;

  const ImportReviewSheet({
    super.key,
    required this.bytes,
    required this.defaultDate,
    required this.parser,
    this.title = 'Importar lançamentos',
    this.expenseTypes = const [],
    this.loadExisting,
  });

  @override
  State<ImportReviewSheet> createState() => _ImportReviewSheetState();
}

class _ImportReviewSheetState extends State<ImportReviewSheet> {
  final List<_ParsedItem> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _parse();
  }

  Future<void> _parse() async {
    try {
      final parsed = await widget.parser(widget.bytes);
      final items = [
        for (final item in parsed)
          _ParsedItem(
            description: item.description,
            amount: item.amount,
            date: item.date ?? widget.defaultDate,
            installment: item.installment,
            installments: item.installments,
            category: suggestCategory(TxType.expense, item.description,
                        extra: widget.expenseTypes)
                    ?.name ??
                'Outros',
          ),
      ];
      await _markDuplicates(items);
      if (!mounted) return;
      setState(() {
        _items.addAll(items);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error =
            'Não foi possível ler o arquivo. Verifique se é um PDF ou CSV válido.';
        _loading = false;
      });
    }
  }

  /// Desmarca itens com mesmo dia e valor de um lançamento já salvo.
  Future<void> _markDuplicates(List<_ParsedItem> items) async {
    final load = widget.loadExisting;
    if (load == null || items.isEmpty) return;
    final dates = items.map((i) => i.date).toList()..sort();
    List<Tx> existing;
    try {
      existing = await load(dates.first, dates.last);
    } catch (_) {
      return; // Sem a checagem, a importação continua normal.
    }
    final saved = <String, int>{};
    for (final t in existing.where((t) => t.type == TxType.expense)) {
      final key = _dupKey(t.date, t.amount);
      saved[key] = (saved[key] ?? 0) + 1;
    }
    for (final item in items) {
      final key = _dupKey(item.date, item.amount);
      final left = saved[key] ?? 0;
      if (left > 0) {
        saved[key] = left - 1;
        item.duplicate = true;
        item.selected = false;
      }
    }
  }

  void _save() {
    final selected =
        _items.where((i) => i.selected).map((i) => i.toTx()).toList();
    Navigator.pop(context, selected);
  }

  int get _selectedCount => _items.where((i) => i.selected).length;
  int get _duplicates => _items.where((i) => i.duplicate).length;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    Widget body;
    if (_loading) {
      body = const Padding(
        padding: EdgeInsets.symmetric(vertical: 64),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Lendo arquivo...'),
        ]),
      );
    } else if (_error != null) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline_rounded, size: 48),
          const SizedBox(height: 12),
          Text(_error!,
              textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
        ]),
      );
    } else if (_items.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.search_off_rounded, size: 48),
          const SizedBox(height: 12),
          Text('Nenhum lançamento encontrado no arquivo.',
              textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
          const SizedBox(height: 4),
          const Text(
              'Verifique se o arquivo é uma fatura de cartão (PDF ou CSV).'),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
        ]),
      );
    } else {
      body = Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${_items.length} lançamentos encontrados',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  if (_duplicates > 0)
                    Text(
                      _duplicates == 1
                          ? '1 já lançado e desmarcado'
                          : '$_duplicates já lançados e desmarcados',
                      style: theme.textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => setState(() {
                final allSelected = _items.every((i) => i.selected);
                for (final item in _items) {
                  item.selected = !allSelected;
                }
              }),
              child: Text(_items.every((i) => i.selected)
                  ? 'Desmarcar tudo'
                  : 'Selecionar tudo'),
            ),
          ]),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            itemCount: _items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) => _itemTile(i, theme),
          ),
        ),
      ]);
    }

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.85,
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Text(widget.title,
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800)),
            ),
            Expanded(child: body),
            if (!_loading && _error == null && _items.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: FilledButton.icon(
                  onPressed: _selectedCount == 0 ? null : _save,
                  icon: const Icon(Icons.save_rounded),
                  label: Text(
                      'Salvar $_selectedCount lançamento${_selectedCount == 1 ? '' : 's'}'),
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _itemTile(int i, ThemeData theme) {
    final item = _items[i];
    final cats = categoriesFor(item.type, extra: widget.expenseTypes);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Linha 1: checkbox + descrição + valor
        Row(children: [
          Checkbox(
            value: item.selected,
            onChanged: (v) => setState(() => item.selected = v ?? false),
          ),
          Expanded(
            child: TextField(
              controller: TextEditingController(text: item.description),
              style: TextStyle(
                decoration: item.selected
                    ? TextDecoration.none
                    : TextDecoration.lineThrough,
                color: item.selected ? null : theme.colorScheme.outline,
              ),
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
              onChanged: (text) {
                item.description = text;
                final sug = suggestCategory(item.type, text,
                    extra: widget.expenseTypes);
                if (sug != null) item.category = sug.name;
              },
            ),
          ),
          Text(_money.format(item.amount),
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: item.type == TxType.income
                    ? const Color(0xFF4ADE80)
                    : const Color(0xFFF87171),
              )),
        ]),
        // Linha 2: data, parcela e aviso de repetido
        Padding(
          padding: const EdgeInsets.only(left: 48, bottom: 4),
          child: Text(
            [
              _day.format(item.date),
              if (item.isInstallment)
                'Parcela ${item.installment}/${item.installments}',
              if (item.duplicate) 'Já lançado',
            ].join(' • '),
            style: theme.textTheme.bodySmall?.copyWith(
              color: item.duplicate ? theme.colorScheme.tertiary : null,
            ),
          ),
        ),
        // Linha 3: categorias
        Row(children: [
          const SizedBox(width: 48),
          Expanded(
            child: Wrap(spacing: 6, runSpacing: 4, children: [
              for (final c in cats)
                ChoiceChip(
                  avatar: Icon(c.icon, size: 16, color: c.color),
                  label: Text(c.name, style: const TextStyle(fontSize: 12)),
                  selected: item.category == c.name,
                  onSelected: item.selected
                      ? (_) => setState(() => item.category = c.name)
                      : null,
                ),
            ]),
          ),
        ]),
      ]),
    );
  }
}

/// Estado editável de cada item importado.
class _ParsedItem {
  String description;
  double amount;
  final DateTime date;
  final int? installment;
  final int? installments;
  TxType type = TxType.expense;
  String category;
  bool selected = true;
  bool duplicate = false;

  _ParsedItem({
    required this.description,
    required this.amount,
    required this.date,
    required this.category,
    this.installment,
    this.installments,
  });

  bool get isInstallment => installment != null && installments != null;

  /// Só a parcela desta fatura; as próximas chegam nas próximas faturas.
  Tx toTx() => Tx(
        type: type,
        amount: amount,
        category: category,
        description: description,
        date: DateTime(date.year, date.month, date.day),
        kind: isInstallment ? TxKind.installment : TxKind.single,
        index: installment ?? 1,
        count: installments ?? 1,
      );
}
