import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../models/bank_notification.dart';
import '../pages/bank_notifications_page.dart';
import '../services/bank_notification_service.dart';
import '../services/notification_samples_service.dart';

/// Aviso na Início: movimentações das notificações dos bancos esperando
/// confirmação. Some quando não há nada (e fora do Android).
class BankInboxBanner extends StatefulWidget {
  final BankNotificationService? service;

  const BankInboxBanner({super.key, this.service});

  @override
  State<BankInboxBanner> createState() => _BankInboxBannerState();
}

class _BankInboxBannerState extends State<BankInboxBanner>
    with WidgetsBindingObserver {
  late final BankNotificationService _service =
      widget.service ?? BankNotificationService();
  int _pending = 0;

  @override
  void initState() {
    super.initState();
    if (!BankNotificationService.supported && widget.service == null) return;
    WidgetsBinding.instance.addObserver(this);
    BankNotificationService.openInboxRequests.addListener(_openFromPrompt);
    _start();
  }

  Future<void> _start() async {
    await _refresh();
    // Aberto pelo aviso "Confirme no ControlFin".
    if (await _service.takeOpenInbox()) _open();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    BankNotificationService.openInboxRequests.removeListener(_openFromPrompt);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  void _openFromPrompt() => _open();

  Future<void> _refresh() async {
    final items = await _service.list();
    if (widget.service == null) {
      // Textos novos vão (com os dados trocados) para a revisão.
      unawaited(NotificationSamplesService()
          .reportNew(items, _service)
          .catchError((Object _) {}));
    }
    final pending =
        buildInbox(items).where((e) => e.state == InboxState.pending).length;
    if (mounted && pending != _pending) setState(() => _pending = pending);
  }

  Future<void> _open() async {
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => BankNotificationsPage(service: widget.service)));
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    if (_pending == 0) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: const Color(0xFFFBBF24).withValues(alpha: 0.12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
              color: const Color(0xFFFBBF24).withValues(alpha: 0.45)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _open,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
            child: Row(children: [
              const Icon(Icons.notifications_active_rounded,
                  color: Color(0xFFFBBF24)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _pending == 1
                      ? '1 movimentação dos bancos para confirmar'
                      : '$_pending movimentações dos bancos para confirmar',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              TextButton(onPressed: _open, child: const Text('Revisar')),
            ]),
          ),
        ),
      ),
    );
  }
}
