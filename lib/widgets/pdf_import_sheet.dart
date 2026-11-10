import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/tx.dart';
import '../services/pdf_import_service.dart';

final _money = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');

/// Bottom sheet que recebe os bytes de um arquivo (PDF ou CSV), extrai os
/// lançamentos e deixa o usuário categorizar cada um antes de salvar.
class ImportReviewSheet extends StatefulWidget {
  final Uint8List bytes;
  final DateTime defaultDate;
  final Future<List<ParsedItem>> Function(Uint8List) parser;
  final String title;

  const ImportReviewSheet({
    super.key,
    required this.bytes,
    required this.defaultDate,
    required this.parser,
    this.title = 'Importar lançamentos',
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
      setState(() {
        _items.addAll(parsed.map((item) => _ParsedItem(
              description: item.description,
              amount: item.amount,
              category:
                  suggestCategory(TxType.expense, item.description)?.name ??
                      'Outros',
            )));
        _loading = false;
      });
    } catch (_) {
      setState(() {
        _error =
            'Não foi possível ler o PDF. Verifique se o arquivo é uma fatura válida.';
        _loading = false;
      });
    }
  }

  void _save() {
    final selected = _items
        .where((i) => i.selected)
        .map((i) => i.toTx(widget.defaultDate))
        .toList();
    Navigator.pop(context, selected);
  }

  int get _selectedCount => _items.where((i) => i.selected).length;

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
          Text('Lendo fatura...'),
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
          Text('Nenhum lançamento encontrado no PDF.',
              textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
          const SizedBox(height: 4),
          const Text(
              'Verifique se o arquivo é uma fatura de cartão de crédito.'),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
        ]),
      );
    } else {
      body = Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Row(children: [
            Text('${_items.length} lançamentos encontrados',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const Spacer(),
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
            body,
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
    final cats =
        item.type == TxType.expense ? expenseCategories : incomeCategories;

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
                final sug = suggestCategory(item.type, text);
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
        // Linha 2: tipo + categorias
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
  TxType type = TxType.expense;
  String category;
  bool selected = true;

  _ParsedItem({
    required this.description,
    required this.amount,
    required this.category,
  });

  Tx toTx(DateTime date) => Tx(
        type: type,
        amount: amount,
        category: category,
        description: description,
        date: date,
      );
}
