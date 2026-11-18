import 'package:material_ui/material_ui.dart';

import '../models/investor_profile.dart';

/// Questionário do perfil de investidor, uma pergunta por vez.
class InvestorQuiz extends StatefulWidget {
  final ValueChanged<InvestorProfile> onDone;
  final VoidCallback? onCancel;

  const InvestorQuiz({super.key, required this.onDone, this.onCancel});

  @override
  State<InvestorQuiz> createState() => _InvestorQuizState();
}

class _InvestorQuizState extends State<InvestorQuiz> {
  final Map<String, int> _answers = {};
  int _step = 0;

  static const _total = 11;

  /// Sequência atual: a segunda aposta depende da resposta da primeira.
  List<InvestorQuestion> get _sequence {
    final gamble = _answers['gamble'];
    return [
      ...investorQuestions.take(7),
      gambleQuestion,
      gambleFollowUp(acceptedFirst: gamble == 1),
      ...investorQuestions.skip(7),
    ];
  }

  void _choose(InvestorQuestion question, int option) {
    setState(() {
      if (question.id == 'gamble' && _answers['gamble'] != option) {
        // A pergunta seguinte muda; a resposta antiga não vale mais.
        _answers.remove('gambleFollow');
      }
      _answers[question.id] = option;
    });
    if (_step < _total - 1) {
      setState(() => _step++);
      return;
    }
    widget.onDone(InvestorProfile(
      answers: Map.unmodifiable(_answers),
      createdAt: DateTime.now(),
    ));
  }

  void _back() {
    if (_step == 0) {
      widget.onCancel?.call();
      return;
    }
    setState(() => _step--);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final question = _sequence[_step];
    final selected = _answers[question.id];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Row(children: [
          if (_step > 0 || widget.onCancel != null)
            IconButton(
              tooltip: _step == 0 ? 'Cancelar' : 'Voltar',
              onPressed: _back,
              icon: Icon(
                  _step == 0 ? Icons.close_rounded : Icons.arrow_back_rounded),
            ),
          Expanded(
            child: Text('Pergunta ${_step + 1} de $_total',
                style: theme.textTheme.labelLarge),
          ),
        ]),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: (_step + 1) / _total,
            minHeight: 6,
          ),
        ),
        const SizedBox(height: 24),
        Text(question.title,
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w700)),
        if (question.help != null) ...[
          const SizedBox(height: 8),
          Text(question.help!, style: theme.textTheme.bodyMedium),
        ],
        const SizedBox(height: 20),
        for (var i = 0; i < question.options.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _Option(
              key: Key('quiz-${question.id}-$i'),
              text: question.options[i],
              selected: selected == i,
              onTap: () => _choose(question, i),
            ),
          ),
      ],
    );
  }
}

class _Option extends StatelessWidget {
  final String text;
  final bool selected;
  final VoidCallback onTap;

  const _Option({
    super.key,
    required this.text,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? scheme.primary.withValues(alpha: 0.16)
          : const Color(0xFF1A1A1A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color:
              selected ? scheme.primary : Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(children: [
            Expanded(child: Text(text)),
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 20,
              color: selected ? scheme.primary : Colors.white38,
            ),
          ]),
        ),
      ),
    );
  }
}
