import 'package:material_ui/material_ui.dart';

import '../models/investor_profile.dart';
import '../services/investor_profile_service.dart';
import '../widgets/invest/market_section.dart';
import '../widgets/app_header.dart';
import 'investor_profile_page.dart';

/// Aba Investimentos: perfil de investidor (faixa no topo, que abre o perfil
/// completo), foco do mês, carteira atual, mercado e carteira-alvo.
class InvestmentsPage extends StatefulWidget {
  /// Permite trocar o Firestore nos testes.
  final Stream<InvestorProfile?>? profile;

  /// Corpo abaixo da faixa do perfil (padrão: a seção de mercado).
  final Widget Function(InvestorProfile profile)? body;

  /// Foto do topo (os testes passam uma sem Firebase).
  final Widget? avatar;

  const InvestmentsPage({super.key, this.profile, this.body, this.avatar});

  @override
  State<InvestmentsPage> createState() => _InvestmentsPageState();
}

class _InvestmentsPageState extends State<InvestmentsPage> {
  late final _stream = widget.profile ?? InvestorProfileService().watch();

  /// Perfil completo; sem perfil, abre direto nas perguntas.
  void _openProfile({bool quiz = false}) =>
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => InvestorProfilePage(startQuiz: quiz),
      ));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppHeader(title: 'Investimentos', avatar: widget.avatar),
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
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  if (profile == null)
                    _NeedsProfile(onOpenProfile: () => _openProfile(quiz: true))
                  else ...[
                    ProfileStrip(profile: profile, onTap: _openProfile),
                    const SizedBox(height: 16),
                    // Recria a seção quando o perfil é refeito.
                    widget.body?.call(profile) ??
                        MarketSection(
                          key: ValueKey(profile.createdAt),
                          profile: profile,
                        ),
                    const SizedBox(height: 8),
                    Text(
                      'Conteúdo educativo, não é recomendação de '
                      'investimento.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Faixa curta com o perfil de investidor; o toque abre o perfil completo.
class ProfileStrip extends StatelessWidget {
  final InvestorProfile profile;
  final VoidCallback onTap;

  const ProfileStrip({super.key, required this.profile, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = investorColor(profile.type);
    return Material(
      key: const Key('profile-strip'),
      color: color.withValues(alpha: 0.10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: color.withValues(alpha: 0.4)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
          child: Row(children: [
            Icon(Icons.insights_rounded, color: color, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text('Perfil de investidor',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium),
            ),
            const SizedBox(width: 8),
            Text(profile.type.label,
                style: TextStyle(color: color, fontWeight: FontWeight.w800)),
            Icon(Icons.chevron_right_rounded, color: color),
          ]),
        ),
      ),
    );
  }
}

class _NeedsProfile extends StatelessWidget {
  final VoidCallback onOpenProfile;

  const _NeedsProfile({required this.onOpenProfile});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.insights_rounded,
              size: 40, color: theme.colorScheme.primary),
          const SizedBox(height: 12),
          Text('Primeiro, seu perfil de investidor',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const Text(
            'Para dizer quanto do salário vai para a reserva e quanto para '
            'cada investimento, o app precisa saber seu objetivo e o quanto '
            'você aceita de risco. São 11 perguntas rápidas.',
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const Key('profile-start'),
            onPressed: onOpenProfile,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Montar meu perfil'),
          ),
        ],
      ),
    );
  }
}
