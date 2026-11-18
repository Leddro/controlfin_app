import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/bank_notification.dart';
import 'bank_notification_service.dart';

/// Conta que vê a área de desenvolvedor. A proteção de verdade está nas
/// regras do Firestore (por UID); isto só decide o que aparece na tela.
const developerEmails = {'dev@exemplo.com'};

bool isDeveloper(User? user) =>
    user?.email != null &&
    developerEmails.contains(user!.email!.trim().toLowerCase());

/// Texto de notificação enviado para a revisão, já com os dados trocados.
class NotificationSample {
  final String id;
  final String package;
  final String bank;
  final String title;
  final String text;

  /// Como o celular do usuário entendeu (pode ser de uma versão antiga).
  final String? deviceKind;

  /// Quantas vezes esse mesmo texto chegou (somando todos os usuários).
  final int count;
  final DateTime? lastSeen;

  /// Revisão do desenvolvedor: 'ok' ou 'wrong'. Nulo = falta revisar.
  final String? review;
  final String? note;

  const NotificationSample({
    required this.id,
    required this.package,
    required this.bank,
    required this.title,
    required this.text,
    this.deviceKind,
    this.count = 1,
    this.lastSeen,
    this.review,
    this.note,
  });

  factory NotificationSample.fromDoc(
          DocumentSnapshot<Map<String, dynamic>> doc) =>
      NotificationSample.fromMap(doc.id, doc.data() ?? const {});

  factory NotificationSample.fromMap(String id, Map<String, dynamic> m) =>
      NotificationSample(
        id: id,
        package: (m['package'] ?? '') as String,
        bank: (m['bank'] ?? '') as String,
        title: (m['title'] ?? '') as String,
        text: (m['text'] ?? '') as String,
        deviceKind: m['deviceKind'] as String?,
        count: (m['count'] as num?)?.toInt() ?? 1,
        lastSeen: (m['lastSeen'] as Timestamp?)?.toDate(),
        review: m['review'] as String?,
        note: m['note'] as String?,
      );

  /// Como notificação, para passar pelo leitor atual.
  CapturedNotification get asNotification => CapturedNotification(
        id: id,
        package: package,
        title: title,
        text: text,
        postedAt: lastSeen ?? DateTime.now(),
      );
}

/// Coleção `notification_samples`: os celulares escrevem (com os dados
/// trocados), só o desenvolvedor lê. Regras em samplesRules (dev_review_page.dart).
class NotificationSamplesService {
  CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance.collection('notification_samples');

  /// Envia as notificações com dúvida (certeza média) ainda não enviadas e
  /// marca na fila do celular. As de certeza alta passam direto e as de
  /// certeza baixa nem vão. Sem as regras liberadas no Firestore, falha em
  /// silêncio e tenta de novo na próxima abertura.
  Future<void> reportNew(
    List<CapturedNotification> items,
    BankNotificationService device,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final pending = items
        .where((n) => !n.sent && parseBankNotification(n).needsReview)
        .take(50)
        .toList();
    for (final n in pending) {
      final clean = anonymizeNotification(n, userName: user.displayName);
      final id = sampleId(n.package, clean.title, clean.text);
      try {
        await _col.doc(id).set({
          'package': n.package,
          'bank': n.bankName,
          'title': clean.title,
          'text': clean.text,
          'deviceKind': parseBankNotification(n).kind.name,
          'count': FieldValue.increment(1),
          'lastSeen': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        await device.update(n.id, {'sent': true});
      } on FirebaseException {
        return; // regras ainda não liberadas ou sem internet
      }
    }
  }

  Stream<List<NotificationSample>> watch() => _col
      .orderBy('lastSeen', descending: true)
      .snapshots()
      .map((s) => s.docs.map(NotificationSample.fromDoc).toList());

  /// Grava a revisão. Nulo apaga.
  Future<void> review(String id, String? review, {String? note}) =>
      _col.doc(id).update({
        'review': review ?? FieldValue.delete(),
        'note': note == null || note.trim().isEmpty
            ? FieldValue.delete()
            : note.trim(),
      });

  Future<void> delete(String id) => _col.doc(id).delete();
}
