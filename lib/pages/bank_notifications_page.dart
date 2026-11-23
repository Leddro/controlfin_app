import 'dart:async';

import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../models/bank_notification.dart';
import '../models/credit_card.dart';
import '../models/tx.dart';
import '../models/user_settings.dart';
import '../services/bank_notification_service.dart';
import '../services/card_service.dart';
import '../services/notification_samples_service.dart';
import '../services/settings_service.dart';
import '../services/tx_service.dart';
import '../widgets/app_header.dart';
import '../widgets/card_widgets.dart';
import '../widgets/info_button.dart';

final _money = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
final _when = DateFormat("dd/MM 'às' HH:mm", 'pt_BR');
final _day = DateFormat('dd/MM/yyyy');

String _fmt(double v) => _money.format(v);

/// Notificações dos bancos: permissões, lançamentos para confirmar e a
/// validação de cada texto lido.
class BankNotificationsPage extends StatefulWidget {
  // Trocáveis nos testes (o padrão usa o canal nativo e o Firebase).
  final BankNotificationService? service;
  final Stream<List<CreditCard>>? cards;
  final Stream<UserSettings>? settings;
  final Future<void> Function(List<Tx>)? save;
  final Future<List<Tx>> Function(DateTime from, DateTime to)? loadExisting;
  final Future<void> Function(String id)? deleteTx;

  /// Troca a foto do topo nos testes (a padrão usa o Firebase).
  final Widget? avatar;

  const BankNotificationsPage({
    super.key,
    this.service,
    this.cards,
    this.settings,
    this.save,
    this.loadExisting,
    this.deleteTx,
    this.avatar,
  });

  @override
  State<BankNotificationsPage> createState() => _BankNotificationsPageState();
}

class _BankNotificationsPageState extends State<BankNotificationsPage>
    with WidgetsBindingObserver {
  late final BankNotificationService _service =
      widget.service ?? BankNotificationService();
  late final Stream<List<CreditCard>> _cardsStream =
      widget.cards ?? CardService().watch();
  late final Stream<UserSettings> _settingsStream =
      widget.settings ?? SettingsService().watch();

  NotificationAccess _access = const NotificationAccess();
  List<InboxEntry> _inbox = const [];
  List<Tx> _existing = const [];
  bool _loading = true;

  final _confirmKeys = <String, GlobalKey<_ConfirmCardState>>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _reload();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Volta das Configurações do Android: atualiza o estado do acesso.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _reload();
  }

  Future<void> _reload() async {
    final access = await _service.status();
    final items = await _service.list();
    if (widget.service == null) {
      unawaited(NotificationSamplesService()
          .reportNew(items, _service)
          .catchError((Object _) {}));
    }
    final inbox = buildInbox(items);
    var existing = const <Tx>[];
    final pendingDates = [
      for (final e in inbox)
        if (e.state == InboxState.pending) e.parsed.date
    ]..sort();
    if (pendingDates.isNotEmpty) {
      try {
        final load = widget.loadExisting ?? TxService().fetchRange;
        existing = await load(
            pendingDates.first.subtract(const Duration(days: 5)),
            pendingDates.last);
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _access = access;
      _inbox = inbox;
      _existing = existing;
      _loading = false;
    });
  }

  List<InboxEntry> get _pending =>
      _inbox.where((e) => e.state == InboxState.pending).toList();

  void _toast(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _saveTxs(List<Tx> txs) async {
    final save = widget.save ?? TxService().addAll;
    await save(txs);
  }

  Future<void> _confirm(InboxEntry e, Tx tx) async {
    await _saveTxs([tx]);
    await _service.update(e.notification.id, {'status': 'confirmed'});
    await _reload();
    if (mounted) _toast('Lançamento salvo: ${tx.description}.');
  }

  Future<void> _discard(InboxEntry e) async {
    await _service.update(e.notification.id, {'status': 'discarded'});
    await _reload();
  }

  Future<void> _confirmAll() async {
    final ready = <(InboxEntry, Tx)>[];
    var skipped = 0;
    for (final e in _pending) {
      final tx = _confirmKeys[e.notification.id]?.currentState?.buildTx();
      if (tx == null) {
        skipped++;
      } else {
        ready.add((e, tx));
      }
    }
    if (ready.isEmpty) {
      _toast('Nenhum lançamento pronto. Confira os que pedem um cartão ou '
          'um valor.');
      return;
    }
    await _saveTxs([for (final r in ready) r.$2]);
    for (final r in ready) {
      await _service.update(r.$1.notification.id, {'status': 'confirmed'});
    }
    await _reload();
    if (!mounted) return;
    _toast('${ready.length} lançamento${ready.length == 1 ? '' : 's'} salvo'
        '${ready.length == 1 ? '' : 's'}'
        '${skipped > 0 ? '. $skipped ainda precisa${skipped == 1 ? '' : 'm'} de ajuste.' : '.'}');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!BankNotificationService.supported && widget.service == null) {
      return Scaffold(
        appBar:
            AppHeader(title: 'Notificações dos bancos', avatar: widget.avatar),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              'A leitura das notificações dos bancos funciona só no app '
              'Android. No iPhone e no navegador o sistema não permite.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
          ),
        ),
      );
    }
    final pending = _pending;
    return Scaffold(
      appBar: AppHeader(
        title: 'Notificações dos bancos',
        avatar: widget.avatar,
        actions: const [
          InfoButton(
            key: Key('info-bank-notifications'),
            title: 'Notificações dos bancos',
            text: 'O app lê as notificações de compra e de Pix dos seus '
                'bancos e monta o lançamento. Você confere os dados e '
                'confirma; nada é salvo sem a sua confirmação.\n\n'
                'O texto das notificações fica só no celular. Para a sua '
                'conta vai apenas o lançamento confirmado.\n\n'
                'Aviso para confirmar: o app avisa quando chega algo novo.\n\n'
                'Bateria sem restrição: sem isso, o celular pode desligar a '
                'leitura depois de um tempo.',
          ),
          SizedBox(width: 4),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : StreamBuilder<List<CreditCard>>(
              stream: _cardsStream,
              builder: (context, cardsSnap) => StreamBuilder<UserSettings>(
                stream: _settingsStream,
                builder: (context, settingsSnap) {
                  final cards = cardsSnap.data ?? const <CreditCard>[];
                  final settings = settingsSnap.data ?? const UserSettings();
                  return Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: Column(children: [
                        _AccessPanel(
                          access: _access,
                          onListener: _service.openListenerSettings,
                          onPost: () async {
                            await _service.requestPostPermission();
                            await Future<void>.delayed(
                                const Duration(milliseconds: 600));
                            await _reload();
                          },
                          onBattery: _service.openBatterySettings,
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                          child: Row(children: [
                            Text('Para confirmar (${pending.length})',
                                style: theme.textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w800)),
                          ]),
                        ),
                        Expanded(
                          child: _confirmTab(pending, cards, settings),
                        ),
                      ]),
                    ),
                  );
                },
              ),
            ),
    );
  }

  Widget _confirmTab(
      List<InboxEntry> pending, List<CreditCard> cards, UserSettings settings) {
    if (pending.isEmpty) {
      return _Empty(
        icon: Icons.check_circle_outline_rounded,
        text: _access.listener
            ? 'Nada para confirmar. Quando chegar uma notificação de compra '
                'ou Pix de um banco, ela aparece aqui.'
            : 'Ative o acesso às notificações acima para o app começar a '
                'ler as compras e os Pix dos seus bancos.',
      );
    }
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          if (pending.length > 1)
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                onPressed: _confirmAll,
                icon: const Icon(Icons.done_all_rounded),
                label: Text('Confirmar todos (${pending.length})'),
              ),
            ),
          for (final e in pending)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: _ConfirmCard(
                key: _confirmKeys.putIfAbsent(
                    e.notification.id, () => GlobalKey<_ConfirmCardState>()),
                entry: e,
                cards: cards,
                settings: settings,
                existing: _existing,
                onConfirm: (tx) => _confirm(e, tx),
                onDiscard: () => _discard(e),
                onDeleteTx: (tx) async {
                  final delete = widget.deleteTx ?? TxService().deleteOne;
                  await delete(tx.id!);
                  await _discard(e);
                  if (mounted) _toast('Lançamento excluído.');
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Empty({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 44, color: const Color(0xFFFBBF24)),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center),
        ]),
      );
}

/// Acesso às notificações, aviso de confirmação e bateria.
class _AccessPanel extends StatelessWidget {
  final NotificationAccess access;
  final VoidCallback onListener;
  final VoidCallback onPost;
  final VoidCallback onBattery;

  const _AccessPanel({
    required this.access,
    required this.onListener,
    required this.onPost,
    required this.onBattery,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget row(bool ok, String title, String help, String action,
            VoidCallback onTap) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Icon(ok ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                size: 20,
                color: ok ? const Color(0xFF4ADE80) : const Color(0xFFFBBF24)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  // Com tudo certo, só o título; a explicação fica no "i".
                  if (!ok) Text(help, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            if (!ok) TextButton(onPressed: onTap, child: Text(action)),
          ]),
        );
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(children: [
        row(
          access.listener,
          access.listener ? 'Lendo as notificações' : 'Leitura desligada',
          access.listener
              ? 'Compras e Pix dos bancos viram lançamentos para confirmar.'
              : 'Libere o ControlFin em "Acesso a notificações".',
          'Ativar',
          onListener,
        ),
        if (access.listener) ...[
          row(
            access.post,
            'Aviso para confirmar',
            access.post
                ? 'Você recebe um aviso quando chega algo para confirmar.'
                : 'Permita para ser avisado a cada compra ou Pix.',
            'Permitir',
            onPost,
          ),
          row(
            access.battery,
            'Bateria sem restrição',
            access.battery
                ? 'O celular não vai desligar a leitura.'
                : 'Na Samsung, escolha "Sem restrições" para o ControlFin, '
                    'senão a leitura para depois de um tempo.',
            'Ajustar',
            onBattery,
          ),
        ],
      ]),
    );
  }
}

/// Um lançamento para confirmar, com tudo editável.
class _ConfirmCard extends StatefulWidget {
  final InboxEntry entry;
  final List<CreditCard> cards;
  final UserSettings settings;
  final List<Tx> existing;
  final ValueChanged<Tx> onConfirm;
  final VoidCallback onDiscard;
  final ValueChanged<Tx> onDeleteTx;

  const _ConfirmCard({
    super.key,
    required this.entry,
    required this.cards,
    required this.settings,
    required this.existing,
    required this.onConfirm,
    required this.onDiscard,
    required this.onDeleteTx,
  });

  @override
  State<_ConfirmCard> createState() => _ConfirmCardState();
}

class _ConfirmCardState extends State<_ConfirmCard> {
  ParsedNotification get _p => widget.entry.parsed;
  CapturedNotification get _n => widget.entry.notification;

  late TxType _type =
      _p.kind == NotificationKind.pixIn ? TxType.income : TxType.expense;
  late PaymentMethod _payment = _p.kind == NotificationKind.creditPurchase
      ? PaymentMethod.credit
      : PaymentMethod.debit;
  late String? _cardId = matchCard(widget.cards,
          bank: bankByName(_n.bankName)?.name ?? _n.bankName, last4: _p.last4)
      ?.id;
  late final _desc = TextEditingController(text: _p.description);
  late final _amount = TextEditingController(
      text: _p.amount == null
          ? ''
          : _p.amount!.toStringAsFixed(2).replaceAll('.', ','));
  late DateTime _date = _p.date;
  late String _category = _suggest();
  bool _manualCategory = false;
  String? _error;

  String _suggest() =>
      suggestCategory(_type, _desc.text, extra: widget.settings.expenseTypes)
          ?.name ??
      (_type == TxType.income && _p.kind == NotificationKind.pixIn
          ? 'Extra'
          : 'Outros');

  @override
  void didUpdateWidget(covariant _ConfirmCard old) {
    super.didUpdateWidget(old);
    // Os cartões chegam depois do primeiro desenho.
    if (_cardId == null && widget.cards.isNotEmpty && old.cards.isEmpty) {
      _cardId = matchCard(widget.cards,
              bank: bankByName(_n.bankName)?.name ?? _n.bankName,
              last4: _p.last4)
          ?.id;
    }
  }

  @override
  void dispose() {
    _desc.dispose();
    _amount.dispose();
    super.dispose();
  }

  CreditCard? get _card {
    for (final c in widget.cards) {
      if (c.id == _cardId) return c;
    }
    return null;
  }

  bool get _isCredit =>
      _type == TxType.expense && _payment == PaymentMethod.credit;

  /// Lançamento pronto, ou nulo (e a mensagem do que falta).
  Tx? buildTx() {
    final value = parseMoney(_amount.text);
    if (value == null || value <= 0) {
      setState(() => _error = 'Informe o valor.');
      return null;
    }
    if (_isCredit && _card == null) {
      setState(() => _error = 'Escolha o cartão da compra.');
      return null;
    }
    final day = DateTime(_date.year, _date.month, _date.day);
    final text = _desc.text.trim();
    return Tx(
      type: _type,
      amount: value,
      category: _category,
      description: text.isEmpty ? _n.bankName : text,
      date: day,
      payment: _type == TxType.expense ? _payment : null,
      cardId: _isCredit ? _cardId : null,
      billDate: _isCredit ? _card!.dueForPurchase(day) : null,
    );
  }

  /// Lançamento já salvo no mesmo dia com o mesmo valor.
  Tx? get _duplicate {
    final value = parseMoney(_amount.text);
    if (value == null) return null;
    for (final t in widget.existing) {
      if (DateUtils.isSameDay(t.date, _date) &&
          (t.amount - value).abs() < 0.005) {
        return t;
      }
    }
    return null;
  }

  /// Para um cancelamento: lançamentos salvos que podem ser a compra.
  List<Tx> get _cancelCandidates => [
        for (final t in widget.existing)
          if (t.type == TxType.expense &&
              _p.amount != null &&
              (t.amount - _p.amount!).abs() < 0.005)
            t,
      ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final kind = _p.kind;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: kind == NotificationKind.cancel
          ? _cancelBody(theme)
          : _movementBody(theme),
    );
  }

  Widget _header(ThemeData theme, String title) => Row(children: [
        BankBadge(
            bank: _n.bankName,
            color: bankByName(_n.bankName)?.color ?? customBankColor,
            size: 30),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
              Text('${_n.bankName} • ${_when.format(_n.postedAt)}',
                  style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ]);

  Widget _cancelBody(ThemeData theme) {
    final candidates = _cancelCandidates;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _header(theme, 'Compra cancelada'),
      const SizedBox(height: 8),
      Text(_n.text),
      const SizedBox(height: 8),
      Text(
        candidates.isEmpty
            ? 'Não achei um lançamento salvo com esse valor nos últimos dias.'
            : 'Se você já tinha salvo a compra, exclua o lançamento:',
        style: theme.textTheme.bodySmall,
      ),
      for (final t in candidates)
        ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(t.description.isEmpty ? t.category : t.description),
          subtitle: Text('${_day.format(t.date)} • ${_fmt(t.amount)}'),
          trailing: TextButton(
            onPressed: () => widget.onDeleteTx(t),
            child: const Text('Excluir'),
          ),
        ),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          onPressed: widget.onDiscard,
          child: const Text('Ok, dispensar'),
        ),
      ),
    ]);
  }

  Widget _movementBody(ThemeData theme) {
    final unknown = _p.kind == NotificationKind.unknown;
    final cats = categoriesFor(_type, extra: widget.settings.expenseTypes);
    final duplicate = _duplicate;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _header(theme, unknown ? 'Não entendi esta notificação' : _p.kind.label),
      if (unknown) ...[
        const SizedBox(height: 8),
        Text('"${[_n.title, _n.text].where((s) => s.isNotEmpty).join(' — ')}"',
            style: theme.textTheme.bodySmall),
        const SizedBox(height: 4),
        Text('Se for uma movimentação, confira os dados e confirme.',
            style: theme.textTheme.bodySmall),
        const SizedBox(height: 8),
        SegmentedButton<TxType>(
          segments: const [
            ButtonSegment(value: TxType.expense, label: Text('Gasto')),
            ButtonSegment(value: TxType.income, label: Text('Ganho')),
          ],
          selected: {_type},
          onSelectionChanged: (s) => setState(() {
            _type = s.first;
            if (!_manualCategory) _category = _suggest();
          }),
        ),
      ],
      const SizedBox(height: 12),
      Row(children: [
        Expanded(
          flex: 3,
          child: TextField(
            controller: _desc,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Descrição',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (_) {
              if (!_manualCategory) setState(() => _category = _suggest());
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Valor',
              prefixText: r'R$ ',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),
      ]),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          icon: const Icon(Icons.calendar_today_rounded, size: 16),
          label: Text(_day.format(_date)),
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
      ),
      // Linha própria: ao lado da data não cabe em celular estreito.
      if (_type == TxType.expense)
        SegmentedButton<PaymentMethod>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(
                value: PaymentMethod.debit,
                icon: Icon(Icons.bolt_rounded),
                label: Text('Débito/Pix')),
            ButtonSegment(
                value: PaymentMethod.credit,
                icon: Icon(Icons.credit_card_rounded),
                label: Text('Crédito')),
          ],
          selected: {_payment},
          onSelectionChanged: (s) => setState(() {
            _payment = s.first;
            _error = null;
          }),
        ),
      if (_isCredit) ...[
        const SizedBox(height: 6),
        if (widget.cards.isEmpty)
          Text(
              'Cadastre o cartão em Conta > Meus cartões para lançar no '
              'crédito.',
              style: theme.textTheme.bodySmall)
        else
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final c in widget.cards)
              ChoiceChip(
                avatar: BankBadge(bank: c.bank, color: c.color, size: 20),
                label: Text(c.label),
                selected: _cardId == c.id,
                onSelected: (_) => setState(() {
                  _cardId = c.id;
                  _error = null;
                }),
              ),
          ]),
        if (_card != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Vai para a fatura que vence em '
              '${_day.format(_card!.dueForPurchase(_date))}.',
              style: theme.textTheme.bodySmall,
            ),
          ),
      ],
      const SizedBox(height: 10),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final c in cats)
          ChoiceChip(
            avatar: Icon(c.icon, size: 16, color: c.color),
            label: Text(c.name, style: const TextStyle(fontSize: 12)),
            selected: _category == c.name,
            onSelected: (_) => setState(() {
              _category = c.name;
              _manualCategory = true;
            }),
          ),
      ]),
      if (duplicate != null) ...[
        const SizedBox(height: 8),
        Row(children: [
          Icon(Icons.info_outline_rounded,
              size: 16, color: theme.colorScheme.tertiary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Parece já lançado: "${duplicate.description}" no mesmo dia e '
              'valor.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.tertiary),
            ),
          ),
        ]),
      ],
      if (_error != null) ...[
        const SizedBox(height: 8),
        Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
      ],
      const SizedBox(height: 10),
      Row(children: [
        TextButton(onPressed: widget.onDiscard, child: const Text('Descartar')),
        const Spacer(),
        FilledButton.icon(
          onPressed: () {
            final tx = buildTx();
            if (tx != null) widget.onConfirm(tx);
          },
          icon: const Icon(Icons.check_rounded),
          label: const Text('Confirmar'),
        ),
      ]),
    ]);
  }
}
