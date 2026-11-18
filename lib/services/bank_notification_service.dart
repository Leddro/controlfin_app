import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/bank_notification.dart';

/// Estado das permissões no Android.
class NotificationAccess {
  /// "Acesso a notificações" liberado para o ControlFin.
  final bool listener;

  /// Pode mostrar o aviso "Confirme no ControlFin" (Android 13+).
  final bool post;

  /// Fora da economia de bateria (evita a Samsung desligar a leitura).
  final bool battery;

  const NotificationAccess(
      {this.listener = false, this.post = false, this.battery = false});
}

/// Conversa com o BankNotificationListener (Kotlin) pelo canal nativo.
/// As notificações ficam só no celular; o Firestore recebe apenas os
/// lançamentos confirmados.
class BankNotificationService {
  static const _channel = MethodChannel('controlfin/bank_notifications');

  /// Avisa quando o usuário toca no aviso "Confirme no ControlFin" com o
  /// app já aberto.
  static final openInboxRequests = ValueNotifier<int>(0);

  static bool _handlerSet = false;

  BankNotificationService() {
    if (!_handlerSet && supported) {
      _handlerSet = true;
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'openInbox') openInboxRequests.value++;
      });
    }
  }

  /// Só existe no Android (no iPhone e na web não há como ler notificações).
  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<T?> _call<T>(String method, [Object? args]) async {
    if (!supported) return null;
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on MissingPluginException {
      return null; // testes e plataformas sem o código nativo
    } on PlatformException {
      return null;
    }
  }

  Future<NotificationAccess> status() async {
    final m = await _call<Map<Object?, Object?>>('status');
    if (m == null) return const NotificationAccess();
    return NotificationAccess(
      listener: m['listener'] == true,
      post: m['post'] == true,
      battery: m['battery'] == true,
    );
  }

  Future<void> openListenerSettings() => _call<void>('openListenerSettings');
  Future<void> openBatterySettings() => _call<void>('openBatterySettings');
  Future<void> requestPostPermission() => _call<void>('requestPostPermission');

  /// O app foi aberto pelo aviso "Confirme no ControlFin" (uma vez só).
  Future<bool> takeOpenInbox() async =>
      await _call<bool>('takeOpenInbox') ?? false;

  Future<List<CapturedNotification>> list() async {
    final raw = await _call<String>('list');
    if (raw == null || raw.isEmpty) return const [];
    try {
      final data = jsonDecode(raw) as List;
      return [
        for (final item in data)
          if (item is Map)
            CapturedNotification.fromMap(Map<String, dynamic>.from(item)),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Grava a decisão ou a validação. Valor nulo apaga o campo.
  Future<void> update(String id, Map<String, Object?> fields) =>
      _call<void>('update', {'id': id, 'fields': fields});

  Future<void> remove(List<String> ids) => _call<void>('remove', {'ids': ids});
}
