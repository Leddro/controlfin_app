import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../models/bank_notification.dart';
import '../services/notification_samples_service.dart';
import '../widgets/app_header.dart';

final _money = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
final _when = DateFormat("dd/MM 'às' HH:mm", 'pt_BR');

String _fmt(double v) => _money.format(v);

/// Regras do Firestore para a coleção da revisão. [uid] é o do
/// desenvolvedor, o único que lê.
String samplesRules(String uid) => '''
match /notification_samples/{id} {
  function isDev() {
    return request.auth != null && request.auth.uid == '$uid';
  }
  allow read, delete: if isDev();
  allow create: if request.auth != null
    && request.resource.data.keys().hasOnly(
         ['package', 'bank', 'title', 'text', 'deviceKind', 'count', 'lastSeen'])
    && request.resource.data.title.size() < 300
    && request.resource.data.text.size() < 1000;
  allow update: if isDev() || (request.auth != null
    && request.resource.data.diff(resource.data).affectedKeys()
         .hasOnly(['count', 'lastSeen', 'deviceKind']));
}''';

/// Área do desenvolvedor: textos de notificação enviados pelos celulares
/// (com os dados trocados) e o que o leitor atual entende de cada um.
class DevReviewPage extends StatefulWidget {
  // Trocáveis nos testes (o padrão usa o Firebase).
  final Stream<List<NotificationSample>>? samples;
  final Future<void> Function(String id, String? review, {String? note})?
      onReview;
  final Widget? avatar;

  const DevReviewPage({super.key, this.samples, this.onReview, this.avatar});

  @override
  State<DevReviewPage> createState() => _DevReviewPageState();
}

class _DevReviewPageState extends State<DevReviewPage> {
  late final Stream<List<NotificationSample>> _stream =
      widget.samples ?? NotificationSamplesService().watch();

  /// 'todo' (para revisar), 'wrong', 'ok' ou 'all'.
  String _filter = 'todo';
  String? _bank;

  void _toast(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _review(NotificationSample s, String value) async {
    String? note;
    if (value == 'wrong') {
      note = await _askWhatsWrong(s);
      if (note == null) return;
    }
    final next = s.review == value && value == 'ok' ? null : value;
    final save = widget.onReview ?? NotificationSamplesService().review;
    await save(s.id, next, note: note);
  }

  Future<String?> _askWhatsWrong(NotificationSample s) {
    final controller = TextEditingController(text: s.note);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('O que o leitor entendeu errado?'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Ex.: "é compra no débito", "o estabelecimento é X", '
              '"é propaganda, devia ignorar".'),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            autofocus: true,
            maxLines: 3,
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Marcar como errado')),
        ],
      ),
    );
  }

  /// Texto pronto para colar na conversa de ajuste do leitor.
  String _report(NotificationSample s) => [
        '[${s.bank}] ${s.package} • ${s.count}x',
        'Título: ${s.title}',
        'Texto: ${s.text}',
        'Leitura atual: ${parseBankNotification(s.asNotification).summary(_fmt)}',
        if (s.review == 'wrong') 'Errado${s.note != null ? ': ${s.note}' : ''}',
      ].join('\n');

  Future<void> _copy(List<NotificationSample> list) async {
    await Clipboard.setData(
        ClipboardData(text: list.map(_report).join('\n\n')));
    if (mounted) {
      _toast(list.length == 1
          ? 'Texto copiado.'
          : '${list.length} textos copiados.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar:
          AppHeader(title: 'Revisão das notificações', avatar: widget.avatar),
      body: StreamBuilder<List<NotificationSample>>(
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

  Widget _list(List<NotificationSample> all) {
    final theme = Theme.of(context);
    final banks = {for (final s in all) s.bank}.toList()..sort();
    final byBank =
        _bank == null ? all : all.where((s) => s.bank == _bank).toList();
    final shown = byBank.where((s) => switch (_filter) {
          'todo' => s.review == null,
          'wrong' => s.review == 'wrong',
          'ok' => s.review == 'ok',
          _ => true,
        });
    final wrong = byBank.where((s) => s.review == 'wrong').toList();
    int count(String f) => byBank
        .where((s) => switch (f) {
              'todo' => s.review == null,
              _ => s.review == f,
            })
        .length;

    Widget chip(String label, String value) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            label: Text(label),
            selected: _filter == value,
            onSelected: (_) => setState(() => _filter = value),
          ),
        );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Text(
          'Só chegam aqui os textos com dúvida: formato desconhecido, banco '
          'ainda não conferido ou propaganda que fala de compra ou Pix. Os '
          'formatos conferidos passam direto e o que claramente não é '
          'movimentação nem vem. Os dados pessoais chegam trocados e textos '
          'iguais aparecem uma vez só. A leitura é a do leitor deste app.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            chip('Para revisar (${count('todo')})', 'todo'),
            chip('Erradas (${count('wrong')})', 'wrong'),
            chip('Certas (${count('ok')})', 'ok'),
            chip('Todas (${byBank.length})', 'all'),
          ]),
        ),
        if (banks.length > 1) ...[
          const SizedBox(height: 4),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final b in [null, ...banks])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(b ?? 'Todos os bancos'),
                    selected: _bank == b,
                    onSelected: (_) => setState(() => _bank = b),
                  ),
                ),
            ]),
          ),
        ],
        if (wrong.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _copy(wrong),
              icon: const Icon(Icons.copy_all_rounded, size: 18),
              label: Text('Copiar todas as erradas (${wrong.length})'),
            ),
          ),
        if (shown.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 48),
            child: Column(children: [
              const Icon(Icons.fact_check_outlined,
                  size: 44, color: Color(0xFFFBBF24)),
              const SizedBox(height: 12),
              Text(
                all.isEmpty
                    ? 'Nenhum texto recebido ainda. Eles chegam quando um '
                        'celular com a leitura ligada abre o app.'
                    : 'Nada neste filtro.',
                textAlign: TextAlign.center,
              ),
            ]),
          ),
        for (final s in shown)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: _SampleCard(
              sample: s,
              onRight: () => _review(s, 'ok'),
              onWrong: () => _review(s, 'wrong'),
              onCopy: () => _copy([s]),
            ),
          ),
      ],
    );
  }
}

/// Sem acesso à coleção: mostra o UID e as regras para colar no console.
class _SetupHelp extends StatelessWidget {
  final Object? error;
  const _SetupHelp({this.error});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'SEU_UID';
    final rules = samplesRules(uid);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Icon(Icons.lock_outline_rounded,
            size: 44, color: Color(0xFFFBBF24)),
        const SizedBox(height: 12),
        Text('Falta liberar a revisão no Firestore',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        const Text(
          'No console do Firebase, abra Firestore Database > Regras e cole o '
          'bloco abaixo dentro de "match /databases/{database}/documents { }", '
          'ao lado da regra de users. Depois toque em Publicar.',
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
        const SizedBox(height: 12),
        Text('Seu UID: $uid', style: theme.textTheme.bodySmall),
        if (error != null)
          Text('Erro: $error', style: theme.textTheme.bodySmall),
      ],
    );
  }
}

class _SampleCard extends StatelessWidget {
  final NotificationSample sample;
  final VoidCallback onRight;
  final VoidCallback onWrong;
  final VoidCallback onCopy;

  const _SampleCard({
    required this.sample,
    required this.onRight,
    required this.onWrong,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = sample;
    final p = parseBankNotification(s.asNotification);
    final (icon, color) = switch (p.kind) {
      NotificationKind.ignored => (
          Icons.block_rounded,
          theme.colorScheme.outline
        ),
      NotificationKind.unknown => (
          Icons.help_outline_rounded,
          const Color(0xFFFBBF24)
        ),
      NotificationKind.cancel => (Icons.undo_rounded, const Color(0xFFF87171)),
      NotificationKind.pixIn => (
          Icons.south_west_rounded,
          const Color(0xFF4ADE80)
        ),
      _ => (Icons.north_east_rounded, const Color(0xFFF87171)),
    };
    final deviceDiffers = s.deviceKind != null && s.deviceKind != p.kind.name;
    final deviceLabel = NotificationKind.values
        .where((k) => k.name == s.deviceKind)
        .map((k) => k.label)
        .firstOrNull;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: s.review == 'ok'
              ? const Color(0xFF4ADE80).withValues(alpha: 0.5)
              : s.review == 'wrong'
                  ? const Color(0xFFF87171).withValues(alpha: 0.6)
                  : Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Text(s.bank, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text('${s.count}x', style: theme.textTheme.labelSmall),
          ),
          const Spacer(),
          if (s.lastSeen != null)
            Text(_when.format(s.lastSeen!), style: theme.textTheme.bodySmall),
        ]),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(10),
          ),
          child: SelectableText.rich(TextSpan(children: [
            if (s.title.isNotEmpty)
              TextSpan(
                  text: '${s.title}\n',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            TextSpan(text: s.text),
          ])),
        ),
        const SizedBox(height: 10),
        Text('Leitura atual:', style: theme.textTheme.labelMedium),
        const SizedBox(height: 2),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(p.summary(_fmt),
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ]),
        if (deviceDiffers && deviceLabel != null)
          Padding(
            padding: const EdgeInsets.only(top: 2, left: 24),
            child: Text('No celular do usuário (versão anterior): $deviceLabel',
                style: theme.textTheme.bodySmall),
          ),
        if (s.review == 'wrong' && s.note != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 24),
            child: Text('Observação: ${s.note}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: const Color(0xFFF87171))),
          ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: _ReviewButton(
              selected: s.review == 'ok',
              color: const Color(0xFF4ADE80),
              icon: Icons.check_rounded,
              label: 'Certo',
              onTap: onRight,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _ReviewButton(
              selected: s.review == 'wrong',
              color: const Color(0xFFF87171),
              icon: Icons.close_rounded,
              label: 'Errado',
              onTap: onWrong,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Copiar texto e leitura',
            onPressed: onCopy,
            icon: const Icon(Icons.copy_rounded, size: 20),
          ),
        ]),
      ]),
    );
  }
}

class _ReviewButton extends StatelessWidget {
  final bool selected;
  final Color color;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ReviewButton({
    required this.selected,
    required this.color,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: selected ? Colors.black : color,
          backgroundColor: selected ? color : null,
          side: BorderSide(color: color.withValues(alpha: 0.6)),
        ),
      );
}
