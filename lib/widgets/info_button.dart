import 'package:material_ui/material_ui.dart';

/// Botão "i" ao lado de um título. As explicações ficam escondidas aqui, e a
/// tela mostra só os dados. O toque abre uma folha de baixo com [text]
/// (parágrafos separados por linha em branco) e, se houver, [sections].
class InfoButton extends StatelessWidget {
  final String title;
  final String? text;
  final List<InfoSection> sections;

  /// Linha pequena no fim (fontes, aviso de conteúdo educativo).
  final String? footer;

  const InfoButton({
    super.key,
    required this.title,
    this.text,
    this.sections = const [],
    this.footer,
  });

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'Mais informações',
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 32, height: 32),
        iconSize: 20,
        color: Theme.of(context).colorScheme.outline,
        onPressed: () => showInfoSheet(
          context,
          title: title,
          text: text,
          sections: sections,
          footer: footer,
        ),
        icon: const Icon(Icons.info_outline_rounded),
      );
}

/// Um tópico da explicação: título em negrito e o texto embaixo.
class InfoSection {
  final String title;
  final String body;

  const InfoSection(this.title, this.body);
}

Future<void> showInfoSheet(
  BuildContext context, {
  required String title,
  String? text,
  List<InfoSection> sections = const [],
  String? footer,
}) {
  final theme = Theme.of(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    backgroundColor: const Color(0xFF1A1A1A),
    constraints: BoxConstraints(
      maxWidth: 720,
      maxHeight: MediaQuery.sizeOf(context).height * 0.85,
    ),
    builder: (context) => SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.info_outline_rounded,
                size: 20, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(title,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ),
          ]),
          const SizedBox(height: 12),
          if (text != null)
            for (final p in text.split('\n\n'))
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(p, style: theme.textTheme.bodyMedium),
              ),
          for (final s in sections)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.title,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(s.body, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          if (footer != null) ...[
            const Divider(height: 20),
            Text(footer, style: theme.textTheme.bodySmall),
          ],
        ],
      ),
    ),
  );
}

/// Título de cartão com o botão "i" à direita (sem [info], só o título).
class InfoTitle extends StatelessWidget {
  final String title;
  final TextStyle? style;
  final InfoButton? info;

  const InfoTitle(this.title, {super.key, this.style, this.info});

  @override
  Widget build(BuildContext context) {
    final text = Text(title,
        style: style ??
            Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700));
    if (info == null) return text;
    return Row(children: [
      Expanded(child: text),
      const SizedBox(width: 4),
      info!,
    ]);
  }
}
