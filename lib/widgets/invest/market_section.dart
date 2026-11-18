import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';

import '../../models/investor_profile.dart';
import '../../models/market/market_data.dart';
import '../../models/market/portfolio_engine.dart';
import '../../services/market/market_repository.dart';
import 'contribution_section.dart';

const _cardColor = Color(0xFF1A1A1A);
final _brl = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
final _brl0 =
    NumberFormat.currency(locale: 'pt_BR', symbol: r'R$', decimalDigits: 0);
final _usd0 =
    NumberFormat.currency(locale: 'pt_BR', symbol: r'US$', decimalDigits: 0);
final _int = NumberFormat.decimalPattern('pt_BR');

String _pct(double v, {int digits = 1}) =>
    '${(v * 100).toStringAsFixed(digits).replaceAll('.', ',')}%';

Color classColor(AssetClass c) => switch (c) {
      AssetClass.fixedIncome => const Color(0xFF38BDF8),
      AssetClass.brStocks => const Color(0xFF4ADE80),
      AssetClass.smallCaps => const Color(0xFFA3E635),
      AssetClass.dividends => const Color(0xFFFBBF24),
      AssetClass.reits => const Color(0xFFF472B6),
      AssetClass.global => const Color(0xFFA78BFA),
      AssetClass.bitcoin => const Color(0xFFFB923C),
    };

/// Mercado, carteira sugerida e ranking de ações para o perfil.
class MarketSection extends StatefulWidget {
  final InvestorProfile profile;

  /// Permite trocar a fonte nos testes.
  final Future<MarketData> Function()? loader;

  /// Aporte do mês e carteira atual (usam o Firebase; desligado nos testes).
  final bool showContribution;

  /// Calcula a carteira-alvo. Padrão: em outro isolate. Os testes passam
  /// um cálculo direto, porque o relógio simulado não espera o isolate.
  final Future<PortfolioPlan?> Function(InvestorProfile, MarketData)? planner;

  const MarketSection({
    super.key,
    required this.profile,
    this.loader,
    this.showContribution = true,
    this.planner,
  });

  @override
  State<MarketSection> createState() => _MarketSectionState();
}

/// Calcula a carteira-alvo. Função de topo para rodar em outro isolate.
PortfolioPlan? _buildPlan((InvestorProfile, MarketData) args) =>
    PortfolioEngine.build(args.$1, args.$2);

class _MarketSectionState extends State<MarketSection> {
  late Future<(MarketData, PortfolioPlan?)> _future = _load();

  /// Busca o mercado e calcula a carteira uma vez só. A otimização leva
  /// centenas de milissegundos: roda fora da thread da interface para a
  /// tela não travar (no web, o compute roda na mesma thread).
  Future<(MarketData, PortfolioPlan?)> _load() async {
    final data = await (widget.loader ?? MarketRepository().load).call();
    final planner = widget.planner;
    final plan = planner != null
        ? await planner(widget.profile, data)
        : await compute(_buildPlan, (widget.profile, data));
    return (data, plan);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(MarketData, PortfolioPlan?)>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const _Card(
            title: 'Mercado e carteira',
            child: Row(children: [
              SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 12),
              Expanded(child: Text('Buscando dados do mercado...')),
            ]),
          );
        }
        final (data, plan) = snap.data ?? (const MarketData(), null);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.showContribution) ...[
              ContributionSection(
                profile: widget.profile,
                plan: plan,
                etfs: data.etfs,
                quotes: data.quotes,
              ),
              const SizedBox(height: 16),
            ],
            if (data.macro != null) ...[
              _MarketToday(macro: data.macro!, bitcoin: data.bitcoin),
              const SizedBox(height: 16),
            ],
            if (plan == null)
              const _Card(
                title: 'Carteira-alvo do seu perfil',
                child: Text(
                  'Não foi possível montar a carteira agora: faltam a Selic '
                  'ou o histórico do Ibovespa. Tente atualizar mais tarde.',
                ),
              )
            else ...[
              _PortfolioCard(plan: plan),
              const SizedBox(height: 16),
              _FrontierCard(plan: plan),
              if (data.bitcoin != null) ...[
                const SizedBox(height: 16),
                _BitcoinCard(
                  bitcoin: data.bitcoin!,
                  usdBrl: data.macro?.usdBrl,
                  plan: plan,
                ),
              ],
              if (plan.stocks.isNotEmpty) ...[
                const SizedBox(height: 16),
                _StocksCard(plan: plan),
              ],
              const SizedBox(height: 16),
              _MethodCard(plan: plan, macro: data.macro!),
            ],
            if (data.warnings.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (final w in data.warnings)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(children: [
                    const Icon(Icons.info_outline_rounded, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                        child: Text(w,
                            style: Theme.of(context).textTheme.bodySmall)),
                  ]),
                ),
            ],
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => setState(() => _future = _load()),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Atualizar dados'),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Card extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;

  const _Card({required this.title, this.subtitle, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Material (e não Container colorido) para os efeitos de toque dos
    // itens expansíveis aparecerem sobre o fundo do cartão.
    return Material(
      color: _cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(subtitle!, style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Mercado hoje

class _MarketToday extends StatelessWidget {
  final MacroSnapshot macro;
  final BitcoinSnapshot? bitcoin;

  const _MarketToday({required this.macro, this.bitcoin});

  @override
  Widget build(BuildContext context) {
    final tiles = <(String, String, String?)>[
      if (macro.ibovespa != null)
        (
          'Ibovespa',
          '${_int.format(macro.ibovespa!.round())} pts',
          macro.ibovespaChange == null
              ? null
              : '${macro.ibovespaChange! >= 0 ? '+' : ''}'
                  '${macro.ibovespaChange!.toStringAsFixed(2).replaceAll('.', ',')}% no dia',
        ),
      ('Selic', _pct(macro.selic / 100, digits: 2), 'ao ano'),
      (
        'IPCA 12 meses',
        _pct(macro.ipca12m / 100, digits: 2),
        'Focus longo prazo: ${_pct(macro.ipcaLongTerm / 100)}'
      ),
      if (macro.usdBrl != null) ('Dólar', _brl.format(macro.usdBrl), null),
      if (bitcoin != null)
        (
          'Bitcoin',
          macro.usdBrl != null
              ? _brl0.format(bitcoin!.priceUsd * macro.usdBrl!)
              : _usd0.format(bitcoin!.priceUsd),
          null,
        ),
      if (macro.usTreasury10y != null)
        (
          'Juros EUA 10 anos',
          _pct(macro.usTreasury10y! / 100, digits: 2),
          null
        ),
    ];
    final theme = Theme.of(context);
    return _Card(
      title: 'Mercado hoje',
      subtitle: 'Atualizado em '
          '${DateFormat("dd/MM 'às' HH:mm").format(macro.fetchedAt)}',
      child: LayoutBuilder(builder: (context, c) {
        final width = (c.maxWidth - 12) / 2;
        return Wrap(spacing: 12, runSpacing: 12, children: [
          for (final (label, value, hint) in tiles)
            SizedBox(
              width: width,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: theme.textTheme.bodySmall),
                  Text(value,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  if (hint != null)
                    Text(hint, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
        ]);
      }),
    );
  }
}

// ---------------------------------------------------------------- Carteira

class _PortfolioCard extends StatelessWidget {
  final PortfolioPlan plan;

  const _PortfolioCard({required this.plan});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = plan.weights.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return _Card(
      title: 'Carteira-alvo do seu perfil',
      subtitle: 'Markowitz com a sua aversão ao risco (γ = '
          '${plan.gamma.toString().replaceAll('.', ',')}) e os limites do '
          'seu perfil.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 180,
            child: PieChart(PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 48,
              sections: [
                for (final e in entries)
                  PieChartSectionData(
                    value: e.value,
                    color: classColor(e.key),
                    radius: 36,
                    title: e.value >= 0.06 ? _pct(e.value, digits: 0) : '',
                    titleStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0A0A0A)),
                  ),
              ],
            )),
          ),
          const SizedBox(height: 16),
          for (final e in entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                      color: classColor(e.key), shape: BoxShape.circle),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(e.key.label,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(e.key.examples, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                Text(_pct(e.value, digits: 0),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ]),
            ),
          const Divider(height: 24),
          Text(
            'Retorno esperado: ${_pct(plan.expectedReturn)} ao ano'
            '${plan.weights.containsKey(AssetClass.bitcoin) ? ' (sem o Bitcoin)' : ''}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          Text(
              'Oscilação típica (volatilidade): ${_pct(plan.volatility)} ao ano'),
          Text('Referência sem risco (Selic): ${_pct(plan.riskFree)} ao ano',
              style: theme.textTheme.bodySmall),
          for (final note in plan.notes) ...[
            const SizedBox(height: 8),
            Text(note),
          ],
          const SizedBox(height: 8),
          Text(
            'Estimativas, não promessas: o retorno real pode ser bem diferente, '
            'principalmente em prazos curtos.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Fronteira

class _FrontierCard extends StatelessWidget {
  final PortfolioPlan plan;

  const _FrontierCard({required this.plan});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final frontier = [
      for (final p in plan.frontier)
        FlSpot(p.volatility * 100, p.expectedReturn * 100),
    ];
    final assets = [
      for (final e in plan.estimates)
        (e.assetClass, FlSpot(e.volatility * 100, e.expectedReturn * 100)),
    ];
    final user = FlSpot(
        plan.userPoint.volatility * 100, plan.userPoint.expectedReturn * 100);
    final allY = [...frontier.map((s) => s.y), ...assets.map((a) => a.$2.y)];
    final allX = [...frontier.map((s) => s.x), ...assets.map((a) => a.$2.x)];
    // Limites em múltiplos dos intervalos (2 e 5) para os rótulos dos
    // eixos não se sobreporem no fim.
    final minY = ((allY.reduce(math.min) - 1) / 2).floorToDouble() * 2;
    final maxY = ((allY.reduce(math.max) + 1) / 2).ceilToDouble() * 2;
    final maxX = ((allX.reduce(math.max) + 1) / 5).ceilToDouble() * 5;

    return _Card(
      title: 'Fronteira eficiente',
      subtitle: 'Cada ponto da linha é a carteira de maior retorno esperado '
          'para aquele risco. O ponto branco é a sua.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 220,
            child: LineChart(LineChartData(
              minX: 0,
              maxX: maxX,
              minY: minY,
              maxY: maxY,
              gridData: FlGridData(
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) => FlLine(
                    color: Colors.white.withValues(alpha: 0.06),
                    strokeWidth: 1),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                  axisNameWidget:
                      Text('Retorno % a.a.', style: theme.textTheme.bodySmall),
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 32,
                    interval: 2,
                    getTitlesWidget: (v, _) => Text(v.toStringAsFixed(0),
                        style: theme.textTheme.bodySmall),
                  ),
                ),
                bottomTitles: AxisTitles(
                  axisNameWidget: Text('Risco (volatilidade) % a.a.',
                      style: theme.textTheme.bodySmall),
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 24,
                    interval: 5,
                    getTitlesWidget: (v, _) => Text(v.toStringAsFixed(0),
                        style: theme.textTheme.bodySmall),
                  ),
                ),
              ),
              lineTouchData: const LineTouchData(enabled: false),
              lineBarsData: [
                LineChartBarData(
                  spots: frontier,
                  isCurved: true,
                  color: const Color(0xFFFBBF24),
                  barWidth: 3,
                  dotData: const FlDotData(show: false),
                ),
                for (final (c, spot) in assets)
                  LineChartBarData(
                    spots: [spot],
                    barWidth: 0,
                    dotData: FlDotData(
                      getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                          radius: 5, color: classColor(c), strokeWidth: 0),
                    ),
                  ),
                LineChartBarData(
                  spots: [user],
                  barWidth: 0,
                  dotData: FlDotData(
                    getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                        radius: 7,
                        color: Colors.white,
                        strokeWidth: 3,
                        strokeColor: const Color(0xFFFBBF24)),
                  ),
                ),
              ],
            )),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 12, runSpacing: 6, children: [
            for (final (c, _) in assets)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                        color: classColor(c), shape: BoxShape.circle)),
                const SizedBox(width: 4),
                Text(c.label, style: theme.textTheme.bodySmall),
              ]),
          ]),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Bitcoin

class _BitcoinCard extends StatelessWidget {
  final BitcoinSnapshot bitcoin;
  final double? usdBrl;
  final PortfolioPlan plan;

  const _BitcoinCard(
      {required this.bitcoin, required this.usdBrl, required this.plan});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final signal =
        plan.bitcoinSignal ?? bitcoinSignalFor(bitcoin.metcalfeRatio);
    final (label, color, text) = switch (signal) {
      BitcoinSignal.cheap => (
          'Barato frente à rede',
          const Color(0xFF4ADE80),
          'O valor de mercado está abaixo do que o tamanho da rede '
              'costuma sustentar.'
        ),
      BitcoinSignal.fair => (
          'Perto do valor da rede',
          const Color(0xFFFBBF24),
          'O valor de mercado está próximo do que o tamanho da rede '
              'costuma sustentar.'
        ),
      BitcoinSignal.expensive => (
          'Caro frente à rede',
          const Color(0xFFF87171),
          'O valor de mercado está bem acima do que o tamanho da rede '
              'costuma sustentar.'
        ),
    };
    final weight = plan.weights[AssetClass.bitcoin];
    String price(double usd) =>
        usdBrl != null ? _brl0.format(usd * usdBrl!) : _usd0.format(usd);

    return _Card(
      title: 'Bitcoin: rede e escassez',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Preço: ${price(bitcoin.priceUsd)}',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(label,
                style: TextStyle(color: color, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 8),
          Text('Metcalfe / Burniske: $text Razão atual: '
              '${bitcoin.metcalfeRatio.toStringAsFixed(2).replaceAll('.', ',')} '
              '(1 = média histórica), com ${_int.format(bitcoin.activeAddresses.round())} '
              'endereços ativos por dia.'),
          const SizedBox(height: 8),
          Text(
            weight == null
                ? 'Seu perfil não inclui Bitcoin na carteira.'
                : 'Na sua carteira: ${_pct(weight, digits: 0)}, ajustado por '
                    'esse sinal.',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const Divider(height: 24),
          Text(
            'Stock-to-flow (PlanB, inspirado em Ammous): estoque ÷ emissão '
            'anual = ${bitcoin.stockToFlow.toStringAsFixed(0)}. O modelo '
            'aponta ${price(bitcoin.s2fModelPriceUsd)} por bitcoin.',
          ),
          const SizedBox(height: 4),
          Text(
            'Só informativo: o modelo errou por larga margem desde 2021 e não '
            'altera a carteira.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Ações

class _StocksCard extends StatelessWidget {
  final PortfolioPlan plan;

  const _StocksCard({required this.plan});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final top = plan.stocks.take(5).toList();
    final rest = plan.stocks.skip(5).toList();
    final noStocks = !plan.weights.keys.any((c) =>
        c == AssetClass.brStocks ||
        c == AssetClass.smallCaps ||
        c == AssetClass.dividends);
    return _Card(
      title: 'Ações em destaque',
      subtitle: 'Ranking por preço justo de Gordon (com o retorno exigido '
          'pelo CAPM) e pelos fatores valor e tamanho de Fama-French.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (noStocks)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Sua carteira sugerida não tem ações agora. O ranking fica '
                'como estudo.',
                style: theme.textTheme.bodySmall,
              ),
            ),
          for (var i = 0; i < top.length; i++)
            _StockRow(rank: i + 1, idea: top[i]),
          if (rest.isNotEmpty)
            Theme(
              data: theme.copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text('Ver as outras ${rest.length}',
                    style: theme.textTheme.bodyMedium),
                children: [
                  for (var i = 0; i < rest.length; i++)
                    _StockRow(rank: i + 6, idea: rest[i]),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Text(
            'Preço justo de Gordon = proventos de 12 meses × (1 + g) ÷ (k − g), '
            'com g = IPCA esperado de longo prazo e k = Selic − spread + β × '
            'prêmio Brasil. Com juros altos, poucas ações passam nesse teste. '
            'Dados do Yahoo Finance e da brapi. Não é recomendação de compra.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _StockRow extends StatelessWidget {
  final int rank;
  final StockIdea idea;

  const _StockRow({required this.rank, required this.idea});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final up = idea.upside;
    final upColor = up == null
        ? theme.colorScheme.outline
        : up >= 0
            ? const Color(0xFF4ADE80)
            : const Color(0xFFF87171);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 24,
          child: Text('$rank', style: theme.textTheme.bodySmall),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(idea.quote.symbol,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(
                '${_brl.format(idea.quote.price)} • DY '
                '${_pct(idea.quote.dividendYield)} • β '
                '${idea.beta.toStringAsFixed(2).replaceAll('.', ',')}',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(
            idea.gordonFairPrice == null
                ? 'Sem proventos'
                : 'Justo ${_brl.format(idea.gordonFairPrice)}',
            style: theme.textTheme.bodySmall,
          ),
          if (up != null)
            Text(
              '${up >= 0 ? '+' : ''}${_pct(up, digits: 0)}',
              style: TextStyle(color: upColor, fontWeight: FontWeight.w700),
            ),
        ]),
      ]),
    );
  }
}

// ---------------------------------------------------------------- Método

class _MethodCard extends StatelessWidget {
  final PortfolioPlan plan;
  final MacroSnapshot macro;

  const _MethodCard({required this.plan, required this.macro});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget section(String title, String body) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(body, style: theme.textTheme.bodySmall),
            ],
          ),
        );

    return Material(
      color: _cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          title: const Text('Como a carteira foi calculada',
              style: TextStyle(fontWeight: FontWeight.w700)),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Retorno esperado e risco de cada classe',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            for (final e in plan.estimates)
              section(
                '${e.assetClass.label}: ${_pct(e.expectedReturn)} ao ano, '
                'volatilidade ${_pct(e.volatility)}',
                [
                  for (final v in e.views) '${v.model}: ${_pct(v.value)}',
                  if (e.beta != null)
                    'β contra o Ibovespa: ${e.beta!.toStringAsFixed(2).replaceAll('.', ',')}',
                ].join(' • '),
              ),
            const Divider(height: 24),
            section(
              'Harry Markowitz (1952)',
              'Escolhe os pesos que maximizam retorno esperado − (γ/2) × '
                  'variância, considerando como as classes oscilam juntas '
                  '(covariâncias de até 5 anos de preços mensais). O γ vem das '
                  'suas respostas sobre troca de emprego (Arrow-Pratt).',
            ),
            section(
              'John Burr Williams (1938) e Aswath Damodaran',
              'O valor de um ativo é o valor presente dos fluxos futuros, '
                  'descontados pelo retorno exigido. Retorno exigido das ações '
                  '= Selic − spread de default do Brasil '
                  '(${_pct(Assumptions.brazilDefaultSpread, digits: 2)}) + β × '
                  'prêmio de risco do Brasil '
                  '(${_pct(Assumptions.brazilTotalErp, digits: 2)}, Damodaran, '
                  '${Assumptions.damodaranDate}).',
            ),
            section(
              'Eugene Fama e Kenneth French (1993)',
              'Empresas menores e mais baratas tendem a render mais no longo '
                  'prazo. Os prêmios de tamanho (SMAL11 − BOVA11) e de valor '
                  '(DIVO11 − BOVA11) são estimados com os dados e reduzidos à '
                  'metade por cautela. No ranking de ações, valor = dividend '
                  'yield e tamanho = valor de mercado.',
            ),
            section(
              'Myron Gordon e Eli Shapiro (1956)',
              'Retorno = dividend yield × (1 + g) + g, com g = IPCA esperado '
                  'de longo prazo (${_pct(macro.ipcaLongTerm / 100)}, Focus). '
                  'Yields de referência: ações pagadoras '
                  '${_pct(Assumptions.referenceDyDividends)} e FIIs '
                  '${_pct(Assumptions.referenceDyReits)} (medianas, '
                  '${Assumptions.referenceDyDate}).',
            ),
            section(
              'Robert Metcalfe e Chris Burniske (2017)',
              'O valor de uma rede cresce com o quadrado dos usuários. O '
                  'valor do Bitcoin é comparado a k × (endereços ativos)², com '
                  'k calibrado nos últimos 4 anos.',
            ),
            section(
              'PlanB (2019), inspirado em Saifedean Ammous',
              'Stock-to-flow mede a escassez (estoque ÷ emissão anual). '
                  'Mostrado como curiosidade: as previsões do modelo falharam '
                  'desde 2021.',
            ),
            const Divider(height: 24),
            Text(
              'Fontes: Banco Central (Selic, IPCA, Focus), Alpha Vantage '
              '(ETFs, dólar, juros dos EUA), brapi (Ibovespa, valor de '
              'mercado), Yahoo Finance (ações e proventos) e CoinMetrics '
              '(rede do Bitcoin). Conteúdo educativo, não é recomendação de '
              'investimento (Resolução CVM 20/2021).',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
