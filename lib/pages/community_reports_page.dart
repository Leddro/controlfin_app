import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../services/community_report_service.dart';
import '../widgets/app_header.dart';

final _when = DateFormat("dd/MM/yyyy 'às' HH:mm", 'pt_BR');

Color reportStatusColor(ReportStatus s) => switch (s) {
      ReportStatus.received => const Color(0xFF38BDF8),
      ReportStatus.inReview => const Color(0xFFFBBF24),
      ReportStatus.done => const Color(0xFF4ADE80),
    };

IconData reportKindIcon(ReportKind k) => switch (k) {
      ReportKind.bug => Icons.bug_report_rounded,
      ReportKind.idea => Icons.lightbulb_rounded,
    };

/// Etiqueta colorida (status ou tipo).
class ReportTag extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const ReportTag(this.label, this.color, {super.key, this.icon});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
          ],
          Text(label,
              style: TextStyle(
                  color: color, fontWeight: FontWeight.w700, fontSize: 12)),
        ]),
      );
}

/// Problemas e sugestões: o usuário envia e acompanha o status e a resposta
/// do desenvolvedor. Só ele e o desenvolvedor veem.
class CommunityReportsPage extends StatefulWidget {
  // Trocáveis nos testes (o padrão usa o Firebase).
  final Stream<List<CommunityReport>>? mine;
  final Future<void> Function(ReportKind kind, String text)? onSend;
  final Widget? avatar;

  const CommunityReportsPage({super.key, this.mine, this.onSend, this.avatar});

  @override
  State<CommunityReportsPage> createState() => _CommunityReportsPageState();
}

class _CommunityReportsPageState extends State<CommunityReportsPage> {
  late final Stream<List<CommunityReport>> _mine =
      widget.mine ?? CommunityReportService().watchMine();
  final _text = TextEditingController();
  ReportKind _kind = ReportKind.bug;
  bool _sending = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _text.text.trim();
    if (text.length < 5) {
      _toast('Conte um pouco mais (pelo menos 5 letras).');
      return;
    }
    setState(() => _sending = true);
    try {
      await (widget.onSend ?? CommunityReportService().send)(_kind, text);
      _text.clear();
      if (mounted) FocusScope.of(context).unfocus();
      _toast(_kind == ReportKind.bug
          ? 'Problema enviado. Obrigado por avisar!'
          : 'Sugestão enviada. Obrigado pela ideia!');
    } catch (_) {
      _toast('Não foi possível enviar agora. Confira a internet e tente de '
          'novo.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppHeader(title: 'Problemas e sugestões', avatar: widget.avatar),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              _form(theme),
              const SizedBox(height: 24),
              Text('Meus reports',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              StreamBuilder<List<CommunityReport>>(
                stream: _mine,
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Text('Não foi possível carregar seus reports agora.',
                        style: theme.textTheme.bodySmall);
                  }
                  if (!snap.hasData) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final list = snap.data!;
                  if (list.isEmpty) {
                    return Text(
                      'Você ainda não enviou nada. O que você mandar aparece '
                      'aqui, com o andamento e a resposta.',
                      style: theme.textTheme.bodySmall,
                    );
                  }
                  return Column(children: [
                    for (final r in list) _MyReportCard(report: r),
                  ]);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _form(ThemeData theme) {
    final bug = _kind == ReportKind.bug;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Ajude a melhorar o ControlFin',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
            'Encontrou algo errado ou tem uma ideia? Conte aqui: a mensagem '
            'vai direto para o desenvolvedor.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 14),
          SegmentedButton<ReportKind>(
            segments: [
              for (final k in ReportKind.values)
                ButtonSegment(
                  value: k,
                  label: Text(k.label),
                  icon: Icon(reportKindIcon(k)),
                ),
            ],
            selected: {_kind},
            onSelectionChanged: (s) => setState(() => _kind = s.first),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('report-text'),
            controller: _text,
            minLines: 4,
            maxLines: 8,
            maxLength: reportMaxLength,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              hintText: bug
                  ? 'O que aconteceu? Em qual tela? O que você esperava '
                      'que acontecesse?'
                  : 'Qual é a sua ideia? Como ela ajudaria você?',
            ),
          ),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.info_outline_rounded,
                size: 16, color: theme.colorScheme.outline),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Seu nome e e-mail vão junto, para o desenvolvedor poder '
                'responder. Só ele vê o que você enviar. Não coloque senhas '
                'nem números de cartão.',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ]),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const Key('report-send'),
            onPressed: _sending ? null : _send,
            icon: _sending
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.send_rounded),
            label: Text(bug ? 'Enviar problema' : 'Enviar sugestão'),
          ),
        ],
      ),
    );
  }
}

class _MyReportCard extends StatelessWidget {
  final CommunityReport report;

  const _MyReportCard({required this.report});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = report;
    return Container(
      key: Key('my-report-${r.id}'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            ReportTag(r.kind.label, theme.colorScheme.outline,
                icon: reportKindIcon(r.kind)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                r.createdAt == null
                    ? 'Enviando...'
                    : _when.format(r.createdAt!),
                style: theme.textTheme.bodySmall,
              ),
            ),
            ReportTag(r.status.label, reportStatusColor(r.status)),
          ]),
          const SizedBox(height: 10),
          Text(r.text),
          if (r.reply != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFBBF24).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: const Color(0xFFFBBF24).withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Resposta do desenvolvedor',
                      style: theme.textTheme.labelMedium?.copyWith(
                          color: const Color(0xFFFBBF24),
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(r.reply!),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
