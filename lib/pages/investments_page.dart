import 'package:flutter/material.dart';

import '../models/investor_profile.dart';
import '../services/investor_profile_service.dart';
import '../widgets/invest/market_section.dart';

/// Aba Investimentos: o que fazer com o dinheiro (foco do mês, carteira atual,
/// mercado e carteira-alvo). Depende do perfil de investidor, que fica na
/// aba Perfil.
class InvestmentsPage extends StatefulWidget {
  /// Abre a aba Perfil para montar o perfil de investidor.
  final VoidCallback onOpenProfile;

  const InvestmentsPage({super.key, required this.onOpenProfile});

  @override
  State<InvestmentsPage> createState() => _InvestmentsPageState();
}

class _InvestmentsPageState extends State<InvestmentsPage> {
  late final _stream = InvestorProfileService().watch();

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
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  if (profile == null)
                    _NeedsProfile(onOpenProfile: widget.onOpenProfile)
                  else ...[
                    // Recria a seção quando o perfil é refeito.
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
            onPressed: onOpenProfile,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Montar meu perfil'),
          ),
        ],
      ),
    );
  }
}
