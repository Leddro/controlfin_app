import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../services/community_report_service.dart';
import '../widgets/app_header.dart';
import 'community_reports_page.dart';

final _when = DateFormat("dd/MM/yyyy 'às' HH:mm", 'pt_BR');

/// Regras do Firestore para os reports. [uid] é o do desenvolvedor.
String reportsRules(String uid) => '''
match /community_reports/{id} {
  function isDev() {
    return request.auth != null && request.auth.uid == '$uid';
  }
  allow create: if request.auth != null
    && request.resource.data.uid == request.auth.uid
    && request.resource.data.keys().hasOnly(['uid', 'name', 'email', 'kind',
         'text', 'platform', 'appVersion', 'createdAt', 'status'])
    && request.resource.data.email == request.auth.token.email
    && request.resource.data.name is string
    && request.resource.data.name.size() <= 100
    && request.resource.data.platform is string
    && request.resource.data.platform.size() <= 20
    && request.resource.data.appVersion is string
    && request.resource.data.appVersion.size() <= 20
    && request.resource.data.kind in ['bug', 'idea']
    && request.resource.data.status == 'new'
    && request.resource.data.text is string
    && request.resource.data.text.size() > 0
    && request.resource.data.text.size() <= $reportMaxLength
    && request.resource.data.createdAt == request.time;
  allow read: if isDev()
    || (request.auth != null && resource.data.uid == request.auth.uid);
  allow update, delete: if isDev();
}''';

/// Área do desenvolvedor: problemas e sugestões de todos os usuários, com
/// nome e e-mail de quem mandou, status e resposta.
class ReportsAdminPage extends StatefulWidget {
  // Trocáveis nos testes (o padrão usa o Firebase).
  final Stream<List<CommunityReport>>? reports;
  final Future<void> Function(String id, ReportStatus status)? onStatus;
  final Future<void> Function(String id, String text)? onReply;
  final Future<void> Function(String id)? onDelete;
  final Widget? avatar;

  const ReportsAdminPage({
    super.key,
    this.reports,
    this.onStatus,
    this.onReply,
    this.onDelete,
    this.avatar,
  });

  @override
  State<ReportsAdminPage> createState() => _ReportsAdminPageState();
}

class _ReportsAdminPageState extends State<ReportsAdminPage> {
  late final Stream<List<CommunityReport>> _stream =
      widget.reports ?? CommunityReportService().watchAll();
  final _service = CommunityReportService();

  /// Status mostrado; nulo = todos.
  ReportStatus? _status = ReportStatus.received;
  ReportKind? _kind;

  void _toast(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    try {
      await action();
      if (mounted) _toast(done);
    } catch (_) {
      if (mounted) _toast('Não foi possível salvar. Tente de novo.');
    }
  }

  Future<void> _setStatus(CommunityReport r, ReportStatus s) => _run(
      () => (widget.onStatus ?? _service.setStatus)(r.id, s),
      'Marcado como ${s.label.toLowerCase()}.');

  Future<void> _reply(CommunityReport r) async {
    final controller = TextEditingController(text: r.reply);
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Responder'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('${r.name.isEmpty ? 'O usuário' : r.name} vê a resposta em '
              'Problemas e sugestões > Meus reports.'),
          const SizedBox(height: 12),
          TextField(
            key: const Key('reply-text'),
            controller: controller,
            autofocus: true,
            minLines: 3,
            maxLines: 6,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Enviar resposta')),
        ],
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    if (text == null) return;
    await _run(() => (widget.onReply ?? _service.reply)(r.id, text),
        text.trim().isEmpty ? 'Resposta apagada.' : 'Resposta enviada.');
    // Respondeu algo ainda não visto: passa para "em análise".
    if (text.trim().isNotEmpty && r.status == ReportStatus.received) {
      await (widget.onStatus ?? _service.setStatus)(
          r.id, ReportStatus.inReview);
    }
  }

  Future<void> _delete(CommunityReport r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Apagar este report?'),
        content: const Text('Ele some também da lista do usuário.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Apagar')),
        ],
      ),
    );
    if (ok != true) return;
    await _run(
        () => (widget.onDelete ?? _service.delete)(r.id), 'Report apagado.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppHeader(title: 'Reports da comunidade', avatar: widget.avatar),
      body: StreamBuilder<List<CommunityReport>>(
        stream: _stream,
        builder: (context, snap) {
          if (snap.hasError) return _SetupHelp(error: snap.error);
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: _list(snap.data!),
            ),
          );
        },
      ),
    );
  }

  Widget _list(List<CommunityReport> all) {
    final theme = Theme.of(context);
    final byKind =
        _kind == null ? all : all.where((r) => r.kind == _kind).toList();
    final shown =
        byKind.where((r) => _status == null || r.status == _status).toList();
    int count(ReportStatus? s) =>
        byKind.where((r) => s == null || r.status == s).length;

    Widget chip(String label, ReportStatus? value) => ChoiceChip(
          label: Text('$label (${count(value)})'),
          selected: _status == value,
          onSelected: (_) => setState(() => _status = value),
        );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Text(
          'Problemas e sugestões de todos os usuários. Cada um vê só os '
          'próprios reports, com o status e a sua resposta.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        // Wrap (e não rolagem lateral): todos os filtros à vista no celular.
        Wrap(spacing: 8, runSpacing: 4, children: [
          chip('Novos', ReportStatus.received),
          chip('Em análise', ReportStatus.inReview),
          chip('Resolvidos', ReportStatus.done),
          chip('Todos', null),
        ]),
        const SizedBox(height: 4),
        Wrap(spacing: 8, runSpacing: 4, children: [
          for (final k in [null, ...ReportKind.values])
            FilterChip(
              avatar: k == null ? null : Icon(reportKindIcon(k), size: 16),
              label: Text(k == null ? 'Tudo' : k.plural),
              selected: _kind == k,
              onSelected: (_) => setState(() => _kind = k),
            ),
        ]),
        if (shown.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 48),
            child: Column(children: [
              const Icon(Icons.inbox_rounded,
                  size: 44, color: Color(0xFFFBBF24)),
              const SizedBox(height: 12),
              Text(
                all.isEmpty
                    ? 'Nenhum report ainda. Eles chegam quando alguém usa o '
                        'botão de problemas e sugestões na Início.'
                    : 'Nada neste filtro.',
                textAlign: TextAlign.center,
              ),
            ]),
          ),
        for (final r in shown)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: _AdminCard(
              report: r,
              onStatus: (s) => _setStatus(r, s),
              onReply: () => _reply(r),
              onDelete: () => _delete(r),
              onCopyEmail: () async {
                await Clipboard.setData(ClipboardData(text: r.email));
                if (mounted) _toast('E-mail copiado.');
              },
            ),
          ),
      ],
    );
  }
}

class _AdminCard extends StatelessWidget {
  final CommunityReport report;
  final ValueChanged<ReportStatus> onStatus;
  final VoidCallback onReply;
  final VoidCallback onDelete;
  final VoidCallback onCopyEmail;

  const _AdminCard({
    required this.report,
    required this.onStatus,
    required this.onReply,
    required this.onDelete,
    required this.onCopyEmail,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall;
    final r = report;
    final kindColor = r.kind == ReportKind.bug
        ? const Color(0xFFF87171)
        : const Color(0xFFFBBF24);
    return Container(
      key: Key('admin-report-${r.id}'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: reportStatusColor(r.status).withValues(
                alpha: r.status == ReportStatus.received ? 0.6 : 0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          ReportTag(r.kind.label, kindColor, icon: reportKindIcon(r.kind)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              r.createdAt == null ? 'agora' : _when.format(r.createdAt!),
              style: small,
            ),
          ),
          IconButton(
            tooltip: 'Apagar',
            visualDensity: VisualDensity.compact,
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline_rounded, size: 20),
          ),
        ]),
        const SizedBox(height: 4),
        Text(r.name.isEmpty ? 'Sem nome' : r.name,
            style: const TextStyle(fontWeight: FontWeight.w700)),
        Row(children: [
          Expanded(
            child: SelectableText(r.email.isEmpty ? 'sem e-mail' : r.email,
                style: small),
          ),
          if (r.email.isNotEmpty)
            IconButton(
              tooltip: 'Copiar e-mail',
              visualDensity: VisualDensity.compact,
              onPressed: onCopyEmail,
              icon: const Icon(Icons.copy_rounded, size: 18),
            ),
        ]),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(10),
          ),
          child: SelectableText(r.text),
        ),
        if (r.platform.isNotEmpty || r.version.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              [
                if (r.platform.isNotEmpty) r.platform,
                if (r.version.isNotEmpty) 'versão ${r.version}',
              ].join(' • '),
              style: small,
            ),
          ),
        if (r.reply != null) ...[
          const SizedBox(height: 8),
          Text('Sua resposta:', style: theme.textTheme.labelMedium),
          const SizedBox(height: 2),
          Text(r.reply!),
        ],
        const SizedBox(height: 12),
        SegmentedButton<ReportStatus>(
          showSelectedIcon: false,
          segments: [
            for (final s in ReportStatus.values)
              ButtonSegment(value: s, label: Text(s.label)),
          ],
          selected: {r.status},
          onSelectionChanged: (s) => onStatus(s.first),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: onReply,
          icon: const Icon(Icons.reply_rounded, size: 18),
          label: Text(r.reply == null ? 'Responder' : 'Editar resposta'),
        ),
      ]),
    );
  }
}

/// Sem acesso à coleção: mostra as regras para colar no console.
class _SetupHelp extends StatelessWidget {
  final Object? error;
  const _SetupHelp({this.error});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'SEU_UID';
    final rules = reportsRules(uid);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Icon(Icons.lock_outline_rounded,
            size: 44, color: Color(0xFFFBBF24)),
        const SizedBox(height: 12),
        Text('Falta liberar os reports no Firestore',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        const Text(
          'No console do Firebase, abra Firestore Database > Regras e cole o '
          'bloco abaixo dentro de "match /databases/{database}/documents { }", '
          'ao lado das outras regras. Depois toque em Publicar.',
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(10),
          ),
          child: SelectableText(rules,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: rules));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Regras copiadas.')));
            }
          },
          icon: const Icon(Icons.copy_rounded),
          label: const Text('Copiar regras'),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text('Erro: $error', style: theme.textTheme.bodySmall),
          ),
      ],
    );
  }
}
