import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Versão mostrada nos reports (a mesma do pubspec.yaml).
const appVersion = '0.1.0';

/// Tamanho máximo do texto (as regras do Firestore conferem o mesmo).
const reportMaxLength = 2000;

enum ReportKind { bug, idea }

extension ReportKindInfo on ReportKind {
  String get label => switch (this) {
        ReportKind.bug => 'Problema',
        ReportKind.idea => 'Sugestão',
      };

  String get plural => switch (this) {
        ReportKind.bug => 'Problemas',
        ReportKind.idea => 'Sugestões',
      };
}

/// Gravado como 'new', 'review' e 'done'.
enum ReportStatus { received, inReview, done }

extension ReportStatusInfo on ReportStatus {
  String get label => switch (this) {
        ReportStatus.received => 'Recebido',
        ReportStatus.inReview => 'Em análise',
        ReportStatus.done => 'Resolvido',
      };

  String get code => switch (this) {
        ReportStatus.received => 'new',
        ReportStatus.inReview => 'review',
        ReportStatus.done => 'done',
      };

  static ReportStatus parse(Object? code) => switch (code) {
        'review' => ReportStatus.inReview,
        'done' => ReportStatus.done,
        _ => ReportStatus.received,
      };
}

/// Problema ou sugestão enviado por um usuário. Só ele e o desenvolvedor
/// leem; só o desenvolvedor muda o status e responde.
class CommunityReport {
  final String id;
  final String uid;
  final String name;
  final String email;
  final ReportKind kind;
  final String text;
  final String platform;
  final String version;

  /// Nulo logo depois de enviar, até o servidor carimbar a hora.
  final DateTime? createdAt;
  final ReportStatus status;
  final String? reply;
  final DateTime? repliedAt;

  const CommunityReport({
    required this.id,
    required this.uid,
    required this.name,
    required this.email,
    required this.kind,
    required this.text,
    this.platform = '',
    this.version = '',
    this.createdAt,
    this.status = ReportStatus.received,
    this.reply,
    this.repliedAt,
  });

  factory CommunityReport.fromMap(String id, Map<String, dynamic> m) {
    DateTime? time(Object? v) => v is Timestamp ? v.toDate() : null;
    final reply = (m['reply'] as String?)?.trim();
    return CommunityReport(
      id: id,
      uid: (m['uid'] ?? '') as String,
      name: (m['name'] ?? '') as String,
      email: (m['email'] ?? '') as String,
      kind: m['kind'] == 'idea' ? ReportKind.idea : ReportKind.bug,
      text: (m['text'] ?? '') as String,
      platform: (m['platform'] ?? '') as String,
      version: (m['appVersion'] ?? '') as String,
      createdAt: time(m['createdAt']),
      status: ReportStatusInfo.parse(m['status']),
      reply: reply == null || reply.isEmpty ? null : reply,
      repliedAt: time(m['repliedAt']),
    );
  }
}

/// Mais recentes primeiro; os recém-enviados (sem hora ainda) no topo.
List<CommunityReport> sortReports(Iterable<CommunityReport> reports) =>
    reports.toList()
      ..sort((a, b) {
        final x = a.createdAt, y = b.createdAt;
        if (x == null || y == null) {
          return x == null ? (y == null ? 0 : -1) : 1;
        }
        return y.compareTo(x);
      });

/// Coleção `community_reports`. Regras em `reportsRules`
/// (reports_admin_page.dart).
class CommunityReportService {
  CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance.collection('community_reports');

  String get _platform => kIsWeb ? 'web' : defaultTargetPlatform.name;

  Future<void> send(ReportKind kind, String text) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Sem login.');
    await _col.add({
      'uid': user.uid,
      'name': user.displayName ?? '',
      'email': user.email ?? '',
      'kind': kind.name,
      'text': text.trim(),
      'platform': _platform,
      'appVersion': appVersion,
      'createdAt': FieldValue.serverTimestamp(),
      'status': ReportStatus.received.code,
    });
  }

  List<CommunityReport> _list(QuerySnapshot<Map<String, dynamic>> s) =>
      sortReports(s.docs.map((d) => CommunityReport.fromMap(d.id, d.data())));

  /// Os reports do próprio usuário. Sem orderBy na consulta para não
  /// precisar de índice composto: ordena aqui.
  Stream<List<CommunityReport>> watchMine() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return Stream.value(const []);
    return _col.where('uid', isEqualTo: uid).snapshots().map(_list);
  }

  /// Todos (só o desenvolvedor tem permissão).
  Stream<List<CommunityReport>> watchAll() => _col.snapshots().map(_list);

  Future<void> setStatus(String id, ReportStatus status) =>
      _col.doc(id).update({'status': status.code});

  /// Resposta vazia apaga a resposta.
  Future<void> reply(String id, String text) => _col.doc(id).update(
        text.trim().isEmpty
            ? {'reply': FieldValue.delete(), 'repliedAt': FieldValue.delete()}
            : {
                'reply': text.trim(),
                'repliedAt': FieldValue.serverTimestamp(),
              },
      );

  Future<void> delete(String id) => _col.doc(id).delete();
}
