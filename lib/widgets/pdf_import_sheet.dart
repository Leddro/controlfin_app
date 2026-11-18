import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';

import '../models/credit_card.dart';
import '../models/tx.dart';
import '../models/user_settings.dart';
import '../services/invoice_detection.dart';
import 'card_editor_sheet.dart';
import 'card_widgets.dart';

final _money = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
final _day = DateFormat('dd/MM/yyyy');
final _dayMonth = DateFormat('dd/MM');

String _cents(double amount) => '${(amount * 100).round()}';

/// Chave para achar lançamentos repetidos: dia e valor em centavos.
String _dupKey(DateTime date, double amount) =>
    '${date.year}-${date.month}-${date.day}|${_cents(amount)}';

/// De onde veio o cartão escolhido na importação.
enum _CardSource { recognized, created, chosen, none }

/// Bottom sheet que recebe os bytes de um arquivo (PDF ou CSV), extrai os
/// lançamentos, reconhece o cartão e a fatura e deixa o usuário revisar
/// tudo antes de salvar.
class ImportReviewSheet extends StatefulWidget {
  final Uint8List bytes;
  final String? fileName;
  final DateTime defaultDate;
  final Future<ParsedStatement> Function(Uint8List bytes, String? fileName)
      parser;
  final String title;
  final List<ExpenseType> expenseTypes;
  final List<CreditCard> cards;

  /// Grava um cartão novo e devolve com o id.
  final Future<CreditCard> Function(CreditCard card)? onCreateCard;

  /// Lançamentos já salvos entre duas datas de compra (inclusive), para
  /// desmarcar o que já foi importado antes (ex.: o PDF e o CSV da mesma
  /// fatura).
  final Future<List<Tx>> Function(DateTime from, DateTime to)? loadExisting;

  /// Gastos já salvos na fatura que vence no dia informado.
  final Future<List<Tx>> Function(DateTime due)? loadBill;

  const ImportReviewSheet({
    super.key,
    required this.bytes,
    required this.defaultDate,
    required this.parser,
    this.fileName,
    this.title = 'Importar lançamentos',
    this.expenseTypes = const [],
    this.cards = const [],
    this.onCreateCard,
    this.loadExisting,
    this.loadBill,
  });

  @override
  State<ImportReviewSheet> createState() => _ImportReviewSheetState();
}

class _ImportReviewSheetState extends State<ImportReviewSheet> {
  final List<_ParsedItem> _items = [];
  bool _loading = true;
  bool _saving = false;
  String? _error;

  InvoiceInfo _info = const InvoiceInfo();
  PaymentMethod _payment = PaymentMethod.credit;
  CreditCard? _card;
  _CardSource _source = _CardSource.none;

  /// Cartão novo ainda sem o usuário confirmar as datas.
  bool _needsConfirm = false;
  DateTime? _due;
  bool _dueFromFile = false;
  bool _futureInstallments = true;
  late List<CreditCard> _cards = [...widget.cards];

  @override
  void initState() {
    super.initState();
    _parse();
  }

  Future<void> _parse() async {
    try {
      final parsed = await widget.parser(widget.bytes, widget.fileName);
      _info = parsed.info;
      final items = [
        for (final item in parsed.items)
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
      _items.addAll(items);
      _identifyCard();
      await _markDuplicates();
      if (!mounted) return;
      setState(() => _loading = false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error =
            'Não foi possível ler o arquivo. Verifique se é um PDF ou CSV válido.';
        _loading = false;
      });
    }
  }

  /// Descobre o cartão e o vencimento pelo que foi lido do arquivo.
  void _identifyCard() {
    if (_info.isAccountStatement) {
      _payment = PaymentMethod.debit;
      return;
    }
    final match = matchCard(_cards, bank: _info.bank?.name, last4: _info.last4);
    if (match != null) {
      _card = match;
      _source = _CardSource.recognized;
    } else if (_info.bank != null || _info.last4 != null) {
      _card = CreditCard(
        bank: _info.bank?.name ?? 'Cartão',
        last4: _info.last4,
        closingDay: _info.suggestedClosingDay ?? 1,
        dueDay: _info.dueDate?.day ?? 10,
        color: _info.bank?.color ?? customBankColor,
      );
      _source = _CardSource.created;
      _needsConfirm = true;
    } else if (_cards.length == 1) {
      // Só existe um cartão: é o palpite mais provável.
      _card = _cards.first;
      _source = _CardSource.chosen;
    }
    _due = _info.dueDate;
    _dueFromFile = _due != null;
    _due ??= _estimatedDue();
  }

  /// Vencimento previsto pelo cartão, a partir da compra mais recente.
  DateTime? _estimatedDue() {
    final card = _card;
    if (card == null || _items.isEmpty) return null;
    final latest =
        _items.map((i) => i.date).reduce((a, b) => a.isAfter(b) ? a : b);
    return card.dueForPurchase(latest);
  }

  /// Desmarca itens já salvos: na mesma fatura com o mesmo valor, ou no
  /// mesmo dia com o mesmo valor.
  Future<void> _markDuplicates() async {
    if (_items.isEmpty) return;
    final existing = <Tx>[];
    try {
      final load = widget.loadExisting;
      if (load != null) {
        final dates = _items.map((i) => i.date).toList()..sort();
        existing.addAll(await load(dates.first, dates.last));
      }
      final due = _due;
      if (widget.loadBill != null &&
          due != null &&
          _payment == PaymentMethod.credit) {
        existing.addAll(await widget.loadBill!(due));
      }
    } catch (_) {
      return; // Sem a checagem, a importação continua normal.
    }

    final seen = <String?>{};
    final inBill = <String, int>{};
    final byDay = <String, int>{};
    for (final t in existing) {
      if (t.type != TxType.expense || !seen.add(t.id)) continue;
      final due = _due;
      if (t.isCredit &&
          t.billDate != null &&
          due != null &&
          DateUtils.isSameDay(t.billDate, due) &&
          (_card?.id == null || t.cardId == null || t.cardId == _card!.id)) {
        inBill[_cents(t.amount)] = (inBill[_cents(t.amount)] ?? 0) + 1;
      } else {
        final key = _dupKey(t.date, t.amount);
        byDay[key] = (byDay[key] ?? 0) + 1;
      }
    }

    for (final item in _items) {
      final wasDuplicate = item.duplicate;
      var dup = false;
      final cents = _cents(item.amount);
      if ((inBill[cents] ?? 0) > 0) {
        inBill[cents] = inBill[cents]! - 1;
        dup = true;
      } else {
        final key = _dupKey(item.date, item.amount);
        if ((byDay[key] ?? 0) > 0) {
          byDay[key] = byDay[key]! - 1;
          dup = true;
        }
      }
      item.duplicate = dup;
      if (dup) item.selected = false;
      if (wasDuplicate && !dup) item.selected = true;
    }
  }

  Future<void> _refreshDuplicates() async {
    await _markDuplicates();
    if (mounted) setState(() {});
  }

  Future<void> _changeDue() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _due ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'Vencimento desta fatura',
    );
    if (picked == null) return;
    setState(() {
      _due = picked;
      _dueFromFile = false;
    });
    await _refreshDuplicates();
  }

  Future<void> _chooseCard() async {
    final choice = await showModalBottomSheet<Object>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('De qual cartão é esta fatura?',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            ),
            for (final c in _cards)
              ListTile(
                leading: BankBadge(bank: c.bank, color: c.color),
                title: Text(c.label),
                subtitle:
                    Text('Fecha dia ${c.closingDay} • vence dia ${c.dueDay}'),
                trailing:
                    c.id == _card?.id ? const Icon(Icons.check_rounded) : null,
                onTap: () => Navigator.pop(context, c),
              ),
            ListTile(
              leading: const Icon(Icons.add_card_rounded),
              title: const Text('Novo cartão'),
              onTap: () => Navigator.pop(context, 'new'),
            ),
          ]),
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'new') {
      final draft =
          await showCardEditor(context, detected: _info, existing: _cards);
      if (draft == null) return;
      _setCard(draft, _CardSource.created, confirmed: true);
    } else if (choice is CreditCard) {
      _setCard(choice, _CardSource.chosen, confirmed: true);
    }
    await _refreshDuplicates();
  }

  void _setCard(CreditCard card, _CardSource source,
      {required bool confirmed}) {
    setState(() {
      _card = card;
      _source = source;
      _needsConfirm = !confirmed;
      if (!_dueFromFile) _due = _estimatedDue();
    });
  }

  /// Pede as datas do cartão novo detectado (só na primeira fatura dele).
  Future<bool> _confirmNewCard() async {
    final draft = await showCardEditor(context,
        initial: null, detected: _info, existing: _cards);
    if (draft == null) return false;
    _setCard(draft, _CardSource.created, confirmed: true);
    return true;
  }

  Future<void> _save() async {
    if (_payment == PaymentMethod.credit) {
      if (_card == null) {
        await _chooseCard();
        if (_card == null) return;
      }
      if (_needsConfirm && !await _confirmNewCard()) return;
      if (!mounted) return;
    }

    setState(() => _saving = true);
    try {
      var card = _card;
      if (_payment == PaymentMethod.credit && card != null && card.id == null) {
        final create = widget.onCreateCard;
        if (create != null) {
          card = await create(card);
          _cards = [..._cards, card];
        }
      }
      final due = _payment == PaymentMethod.credit
          ? (_due ?? card?.dueForPurchase(DateTime.now()))
          : null;
      final txs = <Tx>[
        for (final item in _items.where((i) => i.selected))
          ...item.toTxs(
            payment: _payment,
            card: card,
            due: due,
            futureInstallments: _futureInstallments,
          ),
      ];
      if (mounted) Navigator.pop(context, txs);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Não foi possível salvar. Tente de novo.')));
    }
  }

  int get _selectedCount => _items.where((i) => i.selected).length;
  int get _duplicates => _items.where((i) => i.duplicate).length;
  double get _selectedTotal =>
      _items.where((i) => i.selected).fold(0.0, (s, i) => s + i.amount);
  bool get _hasInstallments =>
      _items.any((i) => i.isInstallment && i.installment! < i.installments!);

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
      body = _message(theme, Icons.error_outline_rounded, _error!, null);
    } else if (_items.isEmpty) {
      body = _message(
        theme,
        Icons.search_off_rounded,
        'Nenhum lançamento encontrado no arquivo.',
        'Verifique se o arquivo é uma fatura de cartão (PDF ou CSV).',
      );
    } else {
      body = ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        itemCount: _items.length + 1,
        separatorBuilder: (_, i) =>
            i == 0 ? const SizedBox.shrink() : const Divider(height: 1),
        itemBuilder: (context, i) =>
            i == 0 ? _header(theme) : _itemTile(i - 1, theme),
      );
    }

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.9,
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Text(widget.title,
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800)),
            ),
            Expanded(child: body),
            if (!_loading && _error == null && _items.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: FilledButton.icon(
                  onPressed: _selectedCount == 0 || _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save_rounded),
                  label: Text(
                      'Salvar $_selectedCount lançamento${_selectedCount == 1 ? '' : 's'}'
                      ' • ${_money.format(_selectedTotal)}'),
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _message(ThemeData theme, IconData icon, String text, String? help) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 48),
        const SizedBox(height: 12),
        Text(text,
            textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
        if (help != null) ...[
          const SizedBox(height: 4),
          Text(help, textAlign: TextAlign.center),
        ],
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Fechar'),
        ),
      ]),
    );
  }

  /// Painel do topo: tipo do arquivo, cartão, vencimento e conferência.
  Widget _header(ThemeData theme) {
    final credit = _payment == PaymentMethod.credit;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<PaymentMethod>(
          segments: const [
            ButtonSegment(
              value: PaymentMethod.credit,
              icon: Icon(Icons.credit_card_rounded),
              label: Text('Fatura de cartão'),
            ),
            ButtonSegment(
              value: PaymentMethod.debit,
              icon: Icon(Icons.account_balance_rounded),
              label: Text('Extrato da conta'),
            ),
          ],
          selected: {_payment},
          onSelectionChanged: (s) {
            setState(() => _payment = s.first);
            _refreshDuplicates();
          },
        ),
        const SizedBox(height: 12),
        if (credit) _cardPanel(theme) else _debitPanel(theme),
        const SizedBox(height: 16),
        Row(children: [
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
      ],
    );
  }

  Widget _debitPanel(ThemeData theme) => _panel(
        child: Row(children: [
          const Icon(Icons.bolt_rounded, color: Color(0xFF2DD4BF)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Os gastos serão salvos como débito/Pix, no dia de cada '
              'lançamento.',
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ]),
      );

  Widget _cardPanel(ThemeData theme) {
    final card = _card;
    final (badgeText, badgeColor) = switch (_source) {
      _CardSource.recognized => ('Reconhecido', const Color(0xFF4ADE80)),
      _CardSource.created => (
          _needsConfirm ? 'Novo • confira as datas' : 'Novo cartão',
          const Color(0xFFFBBF24)
        ),
      _CardSource.chosen => ('Escolhido', theme.colorScheme.outline),
      _CardSource.none => ('', Colors.transparent),
    };
    final due = _due;
    final closing =
        card != null && due != null ? card.closingForDue(due) : null;
    final total = _info.total;

    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (card == null)
            Row(children: [
              const Icon(Icons.help_outline_rounded, color: Color(0xFFFBBF24)),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('Não reconhecemos o cartão desta fatura.',
                    style: TextStyle(fontWeight: FontWeight.w600)),
              ),
              FilledButton.tonal(
                  onPressed: _chooseCard, child: const Text('Escolher')),
            ])
          else
            Row(children: [
              BankBadge(bank: card.bank, color: card.color, size: 42),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(card.label,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 16)),
                    const SizedBox(height: 2),
                    Text(badgeText,
                        style: TextStyle(
                            color: badgeColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              TextButton(onPressed: _chooseCard, child: const Text('Trocar')),
            ]),
          if (_needsConfirm && card != null) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _confirmNewCard,
              icon: const Icon(Icons.event_rounded, size: 18),
              label: const Text('Conferir fechamento e vencimento'),
            ),
          ],
          const Divider(height: 24),
          Row(children: [
            Expanded(
              child: _InfoTile(
                icon: Icons.event_available_rounded,
                label: 'Vencimento',
                value: due == null ? 'Escolher' : _day.format(due),
                onTap: _changeDue,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _InfoTile(
                icon: Icons.lock_clock_rounded,
                label: 'Fechamento',
                value: closing == null ? '—' : _dayMonth.format(closing),
              ),
            ),
          ]),
          if (due != null) ...[
            const SizedBox(height: 8),
            Text(
              'Esses gastos vão contar em '
              '${toBeginningOfSentenceCase(DateFormat('MMMM', 'pt_BR').format(due))}, '
              'mês do vencimento.',
              style: theme.textTheme.bodySmall,
            ),
          ],
          if (total != null) ...[
            const SizedBox(height: 12),
            _totalCheck(theme, total),
          ],
          if (_hasInstallments) ...[
            const SizedBox(height: 4),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _futureInstallments,
              onChanged: (v) => setState(() => _futureInstallments = v),
              title: const Text('Lançar as próximas parcelas'),
              subtitle: const Text(
                  'Compras parceladas já aparecem nas faturas dos próximos meses.'),
            ),
          ],
        ],
      ),
    );
  }

  /// Compara o total da fatura com o que vai ser salvo.
  Widget _totalCheck(ThemeData theme, double total) {
    final found = _items.fold(0.0, (s, i) => s + i.amount);
    final matches = (found - total).abs() < 0.05;
    return Row(children: [
      Icon(matches ? Icons.verified_rounded : Icons.info_outline_rounded,
          size: 18,
          color: matches ? const Color(0xFF4ADE80) : theme.colorScheme.outline),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          matches
              ? 'Total da fatura ${_money.format(total)} confere com os lançamentos.'
              : 'Total da fatura ${_money.format(total)}; lançamentos lidos '
                  '${_money.format(found)}. A diferença costuma ser pagamentos, '
                  'juros ou saldo anterior.',
          style: theme.textTheme.bodySmall,
        ),
      ),
    ]);
  }

  // Material (e não Container) para o toque do interruptor aparecer.
  Widget _panel({required Widget child}) => Material(
        color: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Padding(padding: const EdgeInsets.all(14), child: child),
      );

  Widget _itemTile(int i, ThemeData theme) {
    final item = _items[i];
    final cats = categoriesFor(TxType.expense, extra: widget.expenseTypes);
    final futureCount =
        item.isInstallment ? item.installments! - item.installment! : 0;

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
            child: TextFormField(
              initialValue: item.description,
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
                final sug = suggestCategory(TxType.expense, text,
                    extra: widget.expenseTypes);
                if (sug != null) setState(() => item.category = sug.name);
              },
            ),
          ),
          Text(_money.format(item.amount),
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: Color(0xFFF87171),
              )),
        ]),
        // Linha 2: data, parcela e aviso de repetido
        Padding(
          padding: const EdgeInsets.only(left: 48, bottom: 4),
          child: Text(
            [
              _payment == PaymentMethod.credit
                  ? 'Compra ${_day.format(item.date)}'
                  : _day.format(item.date),
              if (item.isInstallment)
                'Parcela ${item.installment}/${item.installments}'
                    '${_payment == PaymentMethod.credit && _futureInstallments && futureCount > 0 ? ' (+$futureCount nas próximas)' : ''}',
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

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Icon(icon, size: 20, color: const Color(0xFFFBBF24)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.bodySmall),
                Text(value,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ],
            ),
          ),
          if (onTap != null)
            Icon(Icons.edit_rounded,
                size: 16, color: theme.colorScheme.outline),
        ]),
      ),
    );
  }
}

/// Estado editável de cada item importado.
class _ParsedItem {
  String description;
  final double amount;
  final DateTime date;
  final int? installment;
  final int? installments;
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

  /// Lançamento desta fatura e, no crédito, as parcelas que ainda vêm nas
  /// próximas faturas.
  List<Tx> toTxs({
    required PaymentMethod payment,
    required CreditCard? card,
    required DateTime? due,
    required bool futureInstallments,
  }) {
    final credit = payment == PaymentMethod.credit;
    final day = DateTime(date.year, date.month, date.day);
    final future = credit && futureInstallments && isInstallment && due != null
        ? installments! - installment!
        : 0;
    final groupId = isInstallment && future > 0
        ? '${DateTime.now().microsecondsSinceEpoch}${description.hashCode}'
        : null;
    return [
      for (var k = 0; k <= future; k++)
        Tx(
          type: TxType.expense,
          amount: amount,
          category: category,
          description: description.trim(),
          date: day,
          kind: isInstallment ? TxKind.installment : TxKind.single,
          index: (installment ?? 1) + k,
          count: installments ?? 1,
          groupId: groupId,
          payment: payment,
          cardId: credit ? card?.id : null,
          billDate: credit && due != null ? addMonths(due, k) : null,
        ),
    ];
  }
}
