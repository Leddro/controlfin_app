import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/investor_profile.dart';
import '../services/investor_profile_service.dart';
import '../widgets/investor_quiz.dart';

const _cardColor = Color(0xFF1A1A1A);

class InvestPage extends StatefulWidget {
  const InvestPage({super.key});

  @override
  State<InvestPage> createState() => _InvestPageState();
}

class _InvestPageState extends State<InvestPage> {
  final _service = InvestorProfileService();
  late final _stream = _service.watch();
  bool _quizOpen = false;
  bool _saving = false;
  String? _error;

  Future<void> _save(InvestorProfile profile) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _service.save(profile);
      if (!mounted) return;
      setState(() => _quizOpen = false);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Não foi possível salvar seu perfil. '
          'Verifique sua conexão e tente de novo.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Investimentos')),
      body: StreamBuilder<InvestorProfile?>(
        stream: _stream,
        builder: (context, snap) {
          if (snap.hasError) {
            return const Center(
                child: Text('Não foi possível carregar seu perfil.'));
          }
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final profile = snap.data;
          Widget child;
          if (_saving) {
            child = const Center(child: CircularProgressIndicator());
          } else if (_quizOpen) {
            child = InvestorQuiz(
              onDone: _save,
              onCancel: () => setState(() => _quizOpen = false),
            );
          } else if (profile == null) {
            child = _Intro(
              error: _error,
              onStart: () => setState(() => _quizOpen = true),
            );
          } else {
            child = InvestorProfileView(
              profile: profile,
              onRedo: () => setState(() => _quizOpen = true),
            );
          }
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: child,
            ),
          );
        },
      ),
    );
  }
}

class _Intro extends StatelessWidget {
  final VoidCallback onStart;
  final String? error;

  const _Intro({required this.onStart, this.error});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _cardColor,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.insights_rounded,
                  size: 40, color: theme.colorScheme.primary),
              const SizedBox(height: 12),
              Text('Monte seu perfil de investidor',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              const Text(
                'Antes das dicas, precisamos entender seu objetivo e o quanto '
                'você está disposto e preparado para correr riscos. São 11 '
                'perguntas rápidas, e você pode refazer quando quiser.',
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onStart,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Começar'),
              ),
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(error!, style: TextStyle(color: theme.colorScheme.error)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

Color investorColor(InvestorType type) => switch (type) {
      InvestorType.conservative => const Color(0xFF38BDF8),
      InvestorType.moderate => const Color(0xFFFBBF24),
      InvestorType.aggressive => const Color(0xFFF87171),
    };

/// Perfil pronto: tipo, objetivo, as duas medidas e a base teórica.
class InvestorProfileView extends StatelessWidget {
  final InvestorProfile profile;
  final VoidCallback onRedo;

  const InvestorProfileView(
      {super.key, required this.profile, required this.onRedo});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final type = profile.type;
    final color = investorColor(type);
    final box = BoxDecoration(
      color: _cardColor,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
    );
    final aversion = profile.riskAversion;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: box.copyWith(
            border: Border.all(color: color.withValues(alpha: 0.5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Seu perfil de investidor',
                  style: theme.textTheme.labelLarge),
              const SizedBox(height: 4),
              Text(type.label,
                  style: theme.textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w800, color: color)),
              const SizedBox(height: 8),
              Text(type.description),
              const SizedBox(height: 16),
              Wrap(spacing: 8, runSpacing: 8, children: [
                Chip(
                  avatar: const Icon(Icons.flag_rounded, size: 18),
                  label: Text(goalOptions[profile.goal]),
                ),
                Chip(
                  avatar: const Icon(Icons.schedule_rounded, size: 18),
                  label: Text(horizonOptions[profile.horizon]),
                ),
              ]),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: box,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Como chegamos nesse perfil',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              _Meter(
                label: 'Disposição para risco',
                hint: 'O quanto você aceita oscilações (apostas, queda e '
                    'faixas de resultado).',
                value: profile.willingness,
              ),
              _Meter(
                label: 'Capacidade de correr risco',
                hint: 'O quanto sua situação aguenta oscilações (prazo, '
                    'idade, renda, reserva e experiência).',
                value: profile.capacity,
              ),
              Text(
                'Aversão ao risco (Arrow-Pratt): ${aversion.label}, '
                '${aversion.range}.',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                'Estimada pelas perguntas de troca de emprego. Quanto maior '
                'o γ, mais retorno você exige para aceitar incerteza. Com '
                'γ = 1 a pessoa segue a utilidade logarítmica de Bernoulli.',
                style: theme.textTheme.bodySmall,
              ),
              const Divider(height: 32),
              const Text('O que definiu seu perfil',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(profile.limitingFactor),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Material(
          color: _cardColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Theme(
            data: theme.copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              title: const Text('Base teórica',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (author, idea) in investorReferences)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(author,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        Text(idea, style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Este perfil é educativo e não é recomendação de investimento. '
          'Bancos e corretoras fazem a própria análise de perfil '
          '(suitability) antes de oferecer produtos.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: Text(
              'Montado em ${DateFormat('dd/MM/yyyy').format(profile.createdAt)}',
              style: theme.textTheme.bodySmall,
            ),
          ),
          OutlinedButton.icon(
            onPressed: onRedo,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Refazer perfil'),
          ),
        ]),
      ],
    );
  }
}

class _Meter extends StatelessWidget {
  final String label;
  final String hint;
  final double value;

  const _Meter({required this.label, required this.hint, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = value >= 70
        ? investorColor(InvestorType.aggressive)
        : value >= 40
            ? investorColor(InvestorType.moderate)
            : investorColor(InvestorType.conservative);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(label,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            Text('${value.round()} de 100'),
          ]),
          Text(hint, style: theme.textTheme.bodySmall),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: value / 100,
              minHeight: 8,
              color: color,
              backgroundColor: color.withValues(alpha: 0.12),
            ),
          ),
        ],
      ),
    );
  }
}
