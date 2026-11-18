import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/credit_card.dart';
import '../services/invoice_detection.dart';
import 'card_widgets.dart';

final _day = DateFormat('dd/MM/yyyy');

/// Cores extras para quem quer diferenciar dois cartões do mesmo banco.
const _palette = <int>[
  0xFF820AD1,
  0xFFEC7000,
  0xFFCC092F,
  0xFF005CA9,
  0xFF0F766E,
  0xFF21C25E,
  0xFFFBBF24,
  0xFFBE185D,
  0xFF2B2B2B,
  0xFF64748B,
];

/// Abre o formulário de cartão. Devolve o cartão preenchido (sem salvar) ou
/// nulo se o usuário cancelar.
///
/// [detected] pré-preenche com o que foi lido da fatura e mostra um aviso
/// para o usuário conferir as datas, que são perguntadas no primeiro uso.
Future<CreditCard?> showCardEditor(
  BuildContext context, {
  CreditCard? initial,
  InvoiceInfo? detected,
  List<CreditCard> existing = const [],
}) {
  return showModalBottomSheet<CreditCard>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _CardEditor(
      initial: initial,
      detected: detected,
      existing: existing,
    ),
  );
}

class _CardEditor extends StatefulWidget {
  final CreditCard? initial;
  final InvoiceInfo? detected;
  final List<CreditCard> existing;

  const _CardEditor({this.initial, this.detected, required this.existing});

  @override
  State<_CardEditor> createState() => _CardEditorState();
}

class _CardEditorState extends State<_CardEditor> {
  late final _nickname = TextEditingController(text: widget.initial?.nickname);
  late final _last4 = TextEditingController(
      text: widget.initial?.last4 ?? widget.detected?.last4);
  late final _customBank = TextEditingController();

  late String? _bank = widget.initial?.bank ?? widget.detected?.bank?.name;
  late int _color = widget.initial?.color ??
      widget.detected?.bank?.color ??
      knownBanks.first.color;
  late int? _closingDay =
      widget.initial?.closingDay ?? widget.detected?.suggestedClosingDay;
  late int? _dueDay = widget.initial?.dueDay ?? widget.detected?.dueDate?.day;
  bool _typingBank = false;
  String? _error;

  bool get _isEditing => widget.initial != null;

  /// Bancos digitados antes, para aparecerem junto dos conhecidos.
  List<String> get _customBanks {
    final known = knownBanks.map((b) => b.name.toLowerCase()).toSet();
    final seen = <String>{};
    return [
      for (final c in widget.existing)
        if (!known.contains(c.bank.toLowerCase()) &&
            seen.add(c.bank.toLowerCase()))
          c.bank,
      if (_bank != null &&
          !known.contains(_bank!.toLowerCase()) &&
          seen.add(_bank!.toLowerCase()))
        _bank!,
    ];
  }

  @override
  void dispose() {
    _nickname.dispose();
    _last4.dispose();
    _customBank.dispose();
    super.dispose();
  }

  CreditCard? get _draft {
    final bank = _bank;
    if (bank == null || bank.trim().isEmpty) return null;
    final digits = _last4.text.trim();
    return CreditCard(
      id: widget.initial?.id,
      bank: bank.trim(),
      nickname: _nickname.text.trim().isEmpty ? null : _nickname.text.trim(),
      last4: digits.length == 4 ? digits : null,
      closingDay: _closingDay ?? 1,
      dueDay: _dueDay ?? 10,
      color: _color,
    );
  }

  void _pickBank(String name, int color) => setState(() {
        _bank = name;
        _color = color;
        _typingBank = false;
        _error = null;
      });

  void _save() {
    if (_bank == null || _bank!.trim().isEmpty) {
      setState(() => _error = 'Escolha o banco do cartão.');
      return;
    }
    if (_closingDay == null || _dueDay == null) {
      setState(
          () => _error = 'Informe o dia do fechamento e o dia do vencimento.');
      return;
    }
    final digits = _last4.text.trim();
    if (digits.isNotEmpty && digits.length != 4) {
      setState(() => _error = 'O final do cartão tem 4 números.');
      return;
    }
    final draft = _draft!;
    final duplicate = widget.existing.any((c) =>
        c.id != draft.id &&
        c.bank.toLowerCase() == draft.bank.toLowerCase() &&
        c.last4 == draft.last4 &&
        (c.nickname ?? '') == (draft.nickname ?? ''));
    if (duplicate) {
      setState(() => _error =
          'Você já tem esse cartão. Use um apelido ou o final para diferenciar.');
      return;
    }
    Navigator.pop(context, draft);
  }

  Future<void> _chooseDay({required bool closing}) async {
    final current = closing ? _closingDay : _dueDay;
    final picked = await showDialog<int>(
      context: context,
      builder: (context) => _DayPicker(
        title: closing ? 'Dia do fechamento' : 'Dia do vencimento',
        help: closing
            ? 'Dia em que a fatura fecha. Compras a partir desse dia vão '
                'para a fatura seguinte.'
            : 'Dia em que a fatura precisa ser paga.',
        selected: current,
      ),
    );
    if (picked != null) {
      setState(() {
        if (closing) {
          _closingDay = picked;
        } else {
          _dueDay = picked;
        }
        _error = null;
      });
    }
  }

  /// Exemplo prático do ciclo com uma compra feita hoje.
  String? _example() {
    final draft = _draft;
    if (draft == null || _closingDay == null || _dueDay == null) return null;
    final today = DateTime.now();
    final due = draft.dueForPurchase(today);
    final closing = draft.closingForDue(due);
    return 'Uma compra hoje entra na fatura que fecha em '
        '${_day.format(closing)} e vence em ${_day.format(due)}.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final detected = widget.detected;
    final preview = _draft ??
        CreditCard(
            bank: 'Seu cartão',
            closingDay: _closingDay ?? 1,
            dueDay: _dueDay ?? 10,
            color: _color);
    final example = _example();

    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_isEditing ? 'Editar cartão' : 'Novo cartão de crédito',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: CardFace(
                  card: preview,
                  footer: _closingDay == null || _dueDay == null
                      ? 'Informe o fechamento e o vencimento'
                      : null,
                ),
              ),
            ),
            if (detected != null && detected.hasAnything && !_isEditing) ...[
              const SizedBox(height: 16),
              _DetectedBanner(info: detected),
            ],
            const SizedBox(height: 20),
            Text('Banco', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final b in knownBanks)
                _BankChoice(
                  name: b.name,
                  color: b.color,
                  selected: _bank == b.name,
                  onTap: () => _pickBank(b.name, b.color),
                ),
              for (final name in _customBanks)
                _BankChoice(
                  name: name,
                  color: _bank == name ? _color : customBankColor,
                  selected: _bank == name,
                  onTap: () =>
                      _pickBank(name, _bank == name ? _color : customBankColor),
                ),
              ActionChip(
                avatar: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Outro banco'),
                onPressed: () => setState(() => _typingBank = true),
              ),
            ]),
            if (_typingBank) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _customBank,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: 'Nome do banco',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.check_rounded),
                    onPressed: () {
                      final name = _customBank.text.trim();
                      if (name.isEmpty) return;
                      final known = bankByName(name);
                      _pickBank(
                          known?.name ?? name, known?.color ?? customBankColor);
                    },
                  ),
                ),
                onSubmitted: (v) {
                  final name = v.trim();
                  if (name.isEmpty) return;
                  final known = bankByName(name);
                  _pickBank(
                      known?.name ?? name, known?.color ?? customBankColor);
                },
              ),
            ],
            const SizedBox(height: 20),
            Text('Datas da fatura', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: _DayButton(
                  label: 'Fecha',
                  day: _closingDay,
                  icon: Icons.lock_clock_rounded,
                  onTap: () => _chooseDay(closing: true),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _DayButton(
                  label: 'Vence',
                  day: _dueDay,
                  icon: Icons.event_available_rounded,
                  onTap: () => _chooseDay(closing: false),
                ),
              ),
            ]),
            if (example != null) ...[
              const SizedBox(height: 8),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.info_outline_rounded,
                    size: 16, color: theme.colorScheme.outline),
                const SizedBox(width: 6),
                Expanded(
                    child: Text(example, style: theme.textTheme.bodySmall)),
              ]),
            ],
            const SizedBox(height: 20),
            Row(children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _nickname,
                  textCapitalization: TextCapitalization.sentences,
                  maxLength: 20,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Apelido (opcional)',
                    hintText: 'Ex.: Black, Casa',
                    border: OutlineInputBorder(),
                    counterText: '',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _last4,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Final',
                    hintText: '1234',
                    border: OutlineInputBorder(),
                    counterText: '',
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 4),
            Text(
              'O final ajuda o app a reconhecer o cartão nas próximas faturas.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            Text('Cor', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(spacing: 10, runSpacing: 10, children: [
              for (final c in {
                if (bankByName(_bank ?? '') != null) bankByName(_bank!)!.color,
                ..._palette,
              })
                GestureDetector(
                  onTap: () => setState(() => _color = c),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Color(c),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _color == c
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.15),
                        width: _color == c ? 3 : 1,
                      ),
                    ),
                    child: _color == c
                        ? Icon(Icons.check_rounded,
                            size: 18, color: onColor(Color(c)))
                        : null,
                  ),
                ),
            ]),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.check_rounded),
              label: Text(_isEditing ? 'Salvar alterações' : 'Salvar cartão'),
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52)),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetectedBanner extends StatelessWidget {
  final InvoiceInfo info;
  const _DetectedBanner({required this.info});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final parts = [
      if (info.bank != null) info.bank!.name,
      if (info.last4 != null) 'final ${info.last4}',
      if (info.dueDate != null) 'vence dia ${info.dueDate!.day}',
      if (info.suggestedClosingDay != null)
        info.closingIsEstimated
            ? 'fecha por volta do dia ${info.suggestedClosingDay}'
            : 'fecha dia ${info.suggestedClosingDay}',
    ];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFBBF24).withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: const Color(0xFFFBBF24).withValues(alpha: 0.35)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.auto_awesome_rounded, color: Color(0xFFFBBF24)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Encontramos na fatura',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(parts.join(' • '), style: theme.textTheme.bodyMedium),
              const SizedBox(height: 4),
              Text(
                info.closingIsEstimated
                    ? 'O fechamento foi estimado. Confira as datas antes de salvar.'
                    : 'Confira as datas antes de salvar.',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ]),
    );
  }
}

class _BankChoice extends StatelessWidget {
  final String name;
  final int color;
  final bool selected;
  final VoidCallback onTap;

  const _BankChoice({
    required this.name,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      avatar: BankBadge(bank: name, color: color, size: 22),
      label: Text(name),
      selected: selected,
      onSelected: (_) => onTap(),
    );
  }
}

class _DayButton extends StatelessWidget {
  final String label;
  final int? day;
  final IconData icon;
  final VoidCallback onTap;

  const _DayButton({
    required this.label,
    required this.day,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final missing = day == null;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: const Color(0xFF1A1A1A),
          border: Border.all(
            color: missing
                ? const Color(0xFFFBBF24).withValues(alpha: 0.7)
                : Colors.white.withValues(alpha: 0.10),
          ),
        ),
        child: Row(children: [
          Icon(icon, size: 20, color: const Color(0xFFFBBF24)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.bodySmall),
                Text(missing ? 'Escolher' : 'Dia $day',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 16)),
              ],
            ),
          ),
          const Icon(Icons.expand_more_rounded),
        ]),
      ),
    );
  }
}

class _DayPicker extends StatelessWidget {
  final String title;
  final String help;
  final int? selected;

  const _DayPicker({required this.title, required this.help, this.selected});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 320,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(help, style: theme.textTheme.bodySmall),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            children: [
              for (var d = 1; d <= 31; d++)
                InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => Navigator.pop(context, d),
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: d == selected
                          ? const Color(0xFFFBBF24)
                          : Colors.white.withValues(alpha: 0.05),
                    ),
                    child: Text(
                      '$d',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: d == selected ? Colors.black : null,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
      ],
    );
  }
}
