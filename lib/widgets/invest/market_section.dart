import 'dart:async';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart' show compute, kIsWeb;
import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';

import '../../models/investor_profile.dart';
import '../../models/market/contribution.dart';
import '../../models/market/market_data.dart';
import '../../models/market/portfolio_engine.dart';
import '../../models/market/stock_advice.dart';
import '../../services/holdings_service.dart';
import '../../services/market/market_repository.dart';
import '../../services/market/market_sources.dart';
import '../info_button.dart';
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

  /// Carteira atual, para avaliar as ações que o usuário já tem. Padrão: a
  /// do Firestore quando [showContribution]; sem ela, carteira vazia.
  final Stream<List<Holding>>? holdings;

  /// Busca no Yahoo os dados de ações da carteira que o robô ainda não
  /// coletou. Padrão: só no celular (o navegador bloqueia o Yahoo).
  final Future<StockQuote> Function(String ticker, double? usdBrl)?
      stockFetcher;

  const MarketSection({
    super.key,
    required this.profile,
    this.loader,
    this.showContribution = true,
    this.planner,
    this.holdings,
    this.stockFetcher,
  });

  @override
  State<MarketSection> createState() => _MarketSectionState();
}

/// Por que a carteira-alvo não saiu, com o motivo real: erro no cálculo,
/// leitura bloqueada, robô sem dados ou só a Selic/Ibovespa faltando.
String _whyNoPlan(Object? error, MarketData data) {
  if (error != null) {
    return 'Não foi possível calcular a carteira agora. Toque em atualizar '
        'para tentar de novo.';
  }
  if (data.macro == null && data.etfs.isEmpty && data.warnings.isNotEmpty) {
    return data.warnings.first;
  }
  final missing = [
    if (data.macro == null) 'a Selic',
    if (data.etfs[AssetClass.brStocks.symbol] == null)
      'o histórico do Ibovespa (BOVA11)',
  ];
  return 'Não foi possível montar a carteira agora: falta${missing.length > 1 ? 'm' : ''} '
      '${missing.isEmpty ? 'parte dos dados de mercado' : missing.join(' e ')}. '
      'Tente atualizar mais tarde.';
}

/// Calcula a carteira-alvo. Função de topo para rodar em outro isolate.
PortfolioPlan? _buildPlan((InvestorProfile, MarketData) args) =>
    PortfolioEngine.build(args.$1, args.$2);

class _MarketSectionState extends State<MarketSection> {
  late Future<(MarketData, PortfolioPlan?)> _future = _load();

  List<Holding> _holdings = const [];
  StreamSubscription<List<Holding>>? _holdingsSub;

  @override
  void initState() {
    super.initState();
    final stream = widget.holdings ??
        (widget.showContribution ? HoldingsService().watch() : null);
    _holdingsSub = stream?.listen((h) {
      if (mounted) setState(() => _holdings = h);
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _holdingsSub?.cancel();
    super.dispose();
  }

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
              _Card(
                title: 'Carteira-alvo do seu perfil',
                child: Text(_whyNoPlan(snap.error, data)),
              )
            else ...[
              _PortfolioCard(plan: plan, macro: data.macro!),
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
              _StocksCard(
                plan: plan,
                data: data,
                holdings: _holdings,
                fetcher: widget.stockFetcher ??
                    (kIsWeb
                        ? null
                        : (t, usd) => fetchStockQuote(t, usdBrl: usd)),
              ),
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
  final InfoButton? info;
  final Widget child;

  const _Card(
      {required this.title, this.subtitle, this.info, required this.child});

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
            InfoTitle(title, info: info),
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
      info: const InfoButton(
        title: 'Mercado hoje',
        text: 'Os principais números do mercado, usados para calcular a '
            'sua carteira. Os dados são atualizados 4 vezes durante o pregão '
            'e uma vez depois do fechamento.\n\n'
            'Selic: juros básicos do Brasil, a referência da renda fixa. '
            'IPCA: inflação dos últimos 12 meses; o Focus é o que o mercado '
            'espera para os próximos anos.',
        footer: 'Fontes: Banco Central (Selic, IPCA, Focus), brapi '
            '(Ibovespa), Alpha Vantage (dólar e juros dos EUA) e CoinMetrics '
            '(Bitcoin).',
      ),
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
  final MacroSnapshot macro;

  const _PortfolioCard({required this.plan, required this.macro});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = plan.weights.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return _Card(
      title: 'Carteira-alvo do seu perfil',
      info: InfoButton(
        key: const Key('info-portfolio'),
        title: 'Como a carteira foi calculada',
        text: 'Pelo método de Markowitz, com a sua aversão ao risco (γ = '
            '${plan.gamma.toString().replaceAll('.', ',')}) e os limites do '
            'seu perfil.\n\n'
            'Estimativas, não promessas: o retorno real pode ser bem '
            'diferente, principalmente em prazos curtos.',
        sections: _methodSections(plan, macro),
        footer: _sources,
      ),
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
      info: const InfoButton(
        title: 'Fronteira eficiente',
        text: 'Cada ponto da linha amarela é a carteira de maior retorno '
            'esperado para aquele risco. O ponto branco é a sua carteira-alvo, '
            'e os pontos coloridos são as classes de investimento sozinhas.\n\n'
            'Quanto mais à direita, mais a carteira oscila; quanto mais alto, '
            'mais ela deve render.',
      ),
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
    final (label, color, signalText) = switch (signal) {
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

    final small = theme.textTheme.bodySmall;
    return _Card(
      title: 'Bitcoin: rede e escassez',
      info: InfoButton(
        title: 'Bitcoin: rede e escassez',
        text: 'Metcalfe / Burniske: o valor de uma rede cresce com o '
            'quadrado dos usuários. O app compara o valor de mercado do '
            'Bitcoin com o tamanho da rede (endereços ativos por dia). Razão '
            '1 = média histórica. $signalText\n\n'
            'O peso do Bitcoin na sua carteira é ajustado por esse sinal.\n\n'
            'Stock-to-flow (PlanB, inspirado em Ammous): estoque ÷ emissão '
            'anual, uma medida de escassez. Só informativo: o modelo errou '
            'por larga margem desde 2021 e não altera a carteira.',
      ),
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
          Text(
            'Razão de Metcalfe: '
            '${bitcoin.metcalfeRatio.toStringAsFixed(2).replaceAll('.', ',')} • '
            '${_int.format(bitcoin.activeAddresses.round())} endereços ativos '
            'por dia',
            style: small,
          ),
          Text(
            'Stock-to-flow: ${bitcoin.stockToFlow.toStringAsFixed(0)} • '
            'modelo: ${price(bitcoin.s2fModelPriceUsd)}',
            style: small,
          ),
          const SizedBox(height: 8),
          Text(
            weight == null
                ? 'Seu perfil não inclui Bitcoin na carteira.'
                : 'Na sua carteira: ${_pct(weight, digits: 0)}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Ações

/// Ações de empresas da carteira (pelas classes de ações) e o valor de cada.
Map<String, double> heldStockValues(
    List<Holding> holdings, double? Function(String) priceOf) {
  const stockClasses = {
    AssetClass.brStocks,
    AssetClass.smallCaps,
    AssetClass.dividends,
  };
  final out = <String, double>{};
  for (final h in holdings) {
    if (!h.isTicker ||
        !isCompanyStock(h.ticker) ||
        !stockClasses.contains(h.assetClass)) {
      continue;
    }
    out[h.ticker] = (out[h.ticker] ?? 0) + h.value(priceOf(h.ticker));
  }
  return out;
}

class _StocksCard extends StatefulWidget {
  final PortfolioPlan plan;
  final MarketData data;
  final List<Holding> holdings;
  final Future<StockQuote> Function(String ticker, double? usdBrl)? fetcher;

  const _StocksCard({
    required this.plan,
    required this.data,
    required this.holdings,
    required this.fetcher,
  });

  @override
  State<_StocksCard> createState() => _StocksCardState();
}

class _StocksCardState extends State<_StocksCard> {
  /// Ações da carteira buscadas na hora (nulo: buscando ou falhou).
  final Map<String, StockQuote?> _live = {};

  List<StockIdea>? _ideas;
  String _ideasKey = '';

  void _fetchMissing(Iterable<String> tickers) {
    final fetcher = widget.fetcher;
    if (fetcher == null) return;
    final known = {for (final s in widget.data.stocks) s.symbol};
    final missing = tickers
        .where((t) => !known.contains(t) && !_live.containsKey(t))
        .toList();
    if (missing.isEmpty) return;
    for (final t in missing) {
      _live[t] = null;
    }
    () async {
      for (final t in missing) {
        StockQuote? q;
        try {
          q = await fetcher(t, widget.data.macro?.usdBrl);
        } catch (_) {
          // Fica "sem dados" até o robô coletar.
        }
        if (!mounted) return;
        if (q != null) setState(() => _live[t] = q);
      }
    }();
  }

  /// Ranking do robô; com ações buscadas na hora, refaz o ranking (é rápido:
  /// não tem otimização).
  List<StockIdea> _rank() {
    final extra = [
      for (final q in _live.values)
        if (q != null) q,
    ];
    if (extra.isEmpty) return widget.plan.stocks;
    final key = extra.map((q) => q.symbol).join(',');
    if (_ideas != null && key == _ideasKey) return _ideas!;
    final market = widget.data.etfs[AssetClass.brStocks.symbol];
    final macro = widget.data.macro;
    if (market == null || macro == null) return widget.plan.stocks;
    _ideasKey = key;
    return _ideas = PortfolioEngine.rankStocks(
        [...widget.data.stocks, ...extra], market, macro);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final quotes = widget.data.quotes;
    final ideas = _rank();
    final byTicker = {for (final i in ideas) i.quote.symbol: i};
    final held = heldStockValues(
        widget.holdings, (t) => quotes[t] ?? byTicker[t]?.quote.price);
    _fetchMissing(held.keys);
    if (ideas.isEmpty && held.isEmpty) return const SizedBox.shrink();

    final targetHasStocks = widget.plan.weights.keys.any((c) =>
        c == AssetClass.brStocks ||
        c == AssetClass.smallCaps ||
        c == AssetClass.dividends);
    final advice = adviseStocks(
      ideas: ideas,
      heldValues: held,
      targetHasStocks: targetHasStocks,
    );
    Widget header(String text) => Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 10),
          child: Text(text,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
        );

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: _Card(
        title: 'Ações para a sua carteira',
        info: InfoButton(
          key: const Key('info-stocks'),
          title: 'Ações para a sua carteira',
          text: '${advice.summary}\n\n'
              'O preço justo de cada empresa é a média de dois métodos: '
              'Graham (lucro e patrimônio) e Gordon (proventos). A '
              'porcentagem ao lado de cada ação compara o preço de hoje com '
              'esse valor.',
          sections: const [
            InfoSection(
                'Graham',
                '√(22,5 × lucro por ação × patrimônio por ação): no máximo '
                    'P/L 15 e P/VP 1,5. Ele pedia 25% de desconto como margem '
                    'de segurança. Ignora os juros.'),
            InfoSection(
                'Gordon',
                'Proventos de 12 meses × (1 + g) ÷ (k − g), com g = IPCA de '
                    'longo prazo e k pelo CAPM. Pesa os juros altos.'),
          ],
          footer: 'Dados do Yahoo Finance e da brapi. Não é recomendação de '
              'compra.',
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (advice.held.isNotEmpty) ...[
              header('Suas ações'),
              for (final r in advice.held) _HeldRow(review: r),
            ],
            if (ideas.isNotEmpty) ...[
              header(advice.held.isEmpty
                  ? 'Mais bem avaliadas'
                  : 'Para diversificar'),
              for (final s in advice.suggestions) _SuggestionRow(item: s),
              if (advice.suggestions.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Nenhuma empresa do ranking está perto do preço justo '
                    'agora. Fique com os ETFs da carteira-alvo.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
            ],
            if (ideas.isNotEmpty)
              Theme(
                data: theme.copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text('Ranking completo (${ideas.length} ações)',
                      style: theme.textTheme.bodyMedium),
                  children: [
                    for (var i = 0; i < ideas.length; i++)
                      _StockRow(
                        rank: i + 1,
                        idea: ideas[i],
                        owned: held.containsKey(ideas[i].quote.symbol),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String _signedPct(double v) => '${v >= 0 ? '+' : ''}${_pct(v, digits: 0)}';

/// "Graham R$ 39,71 (+181%) • Gordon R$ 12,00 (-15%)".
String _fairLine(StockIdea i) {
  final graham = i.grahamFairPrice != null
      ? 'Graham ${_brl.format(i.grahamFairPrice)} '
          '(${_signedPct(i.grahamUpside!)})'
      : i.hasLoss
          ? 'Graham: teve prejuízo'
          : 'Graham: sem dados';
  final gordon = i.gordonFairPrice != null
      ? 'Gordon ${_brl.format(i.gordonFairPrice)} '
          '(${_signedPct(i.gordonUpside!)})'
      : 'Gordon: sem proventos';
  return '$graham • $gordon';
}

Color _upColor(BuildContext context, double? up) => up == null
    ? Theme.of(context).colorScheme.outline
    : up >= 0
        ? const Color(0xFF4ADE80)
        : const Color(0xFFF87171);

class _Chip extends StatelessWidget {
  final String label;
  final Color color;

  const _Chip(this.label, this.color);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: TextStyle(
                color: color, fontWeight: FontWeight.w700, fontSize: 12)),
      );
}

class _HeldRow extends StatelessWidget {
  final HeldStockReview review;

  const _HeldRow({required this.review});

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    final (label, color) = switch (review.verdict) {
      HeldVerdict.reinforce => ('Reforçar', const Color(0xFF4ADE80)),
      HeldVerdict.keep => ('Manter', const Color(0xFFFBBF24)),
      HeldVerdict.hold => ('Não aumentar', const Color(0xFFF87171)),
      HeldVerdict.noData => ('Sem dados', const Color(0xFFA1A1AA)),
    };
    final idea = review.idea;
    return Padding(
      key: Key('held-${review.ticker}'),
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(review.ticker,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            _Chip(label, color),
          ]),
          Text(
            review.value > 0
                ? '${_brl.format(review.value)} • '
                    '${_pct(review.share, digits: 0)} das suas ações'
                : 'Sem cotação para calcular o valor',
            style: small,
          ),
          if (idea != null) Text(_fairLine(idea), style: small),
          const SizedBox(height: 2),
          Text(review.reason),
        ],
      ),
    );
  }
}

class _SuggestionRow extends StatelessWidget {
  final StockSuggestion item;

  const _SuggestionRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    final idea = item.idea;
    final up = idea.upside;
    return Padding(
      key: Key('suggest-${idea.quote.symbol}'),
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(idea.quote.symbol,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            if (up != null)
              Text(_signedPct(up),
                  style: TextStyle(
                      color: _upColor(context, up),
                      fontWeight: FontWeight.w700)),
          ]),
          Text(_brl.format(idea.quote.price), style: small),
          Text(_fairLine(idea), style: small),
          for (final r in item.reasons)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('• $r'),
            ),
        ],
      ),
    );
  }
}

class _StockRow extends StatelessWidget {
  final int rank;
  final StockIdea idea;
  final bool owned;

  const _StockRow({required this.rank, required this.idea, this.owned = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final up = idea.upside;
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
              Row(children: [
                Text(idea.quote.symbol,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                if (owned) ...[
                  const SizedBox(width: 6),
                  const _Chip('Você tem', Color(0xFF38BDF8)),
                ],
              ]),
              Text(
                '${_brl.format(idea.quote.price)} • DY '
                '${_pct(idea.quote.dividendYield)} • β '
                '${idea.beta.toStringAsFixed(2).replaceAll('.', ',')}',
                style: theme.textTheme.bodySmall,
              ),
              Text(_fairLine(idea), style: theme.textTheme.bodySmall),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          up == null ? '—' : _signedPct(up),
          style: TextStyle(
              color: _upColor(context, up), fontWeight: FontWeight.w700),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------- Método

const _sources = 'Fontes: Banco Central (Selic, IPCA, Focus), Alpha Vantage '
    '(ETFs, dólar, juros dos EUA), brapi (Ibovespa, valor de mercado), Yahoo '
    'Finance (ações, proventos, lucro e patrimônio) e CoinMetrics (rede do '
    'Bitcoin). Conteúdo educativo, não é recomendação de investimento '
    '(Resolução CVM 20/2021).';

/// Estimativas de cada classe e os autores do método, mostrados no "i" da
/// carteira-alvo.
List<InfoSection> _methodSections(PortfolioPlan plan, MacroSnapshot macro) => [
      for (final e in plan.estimates)
        InfoSection(
          '${e.assetClass.label}: ${_pct(e.expectedReturn)} ao ano, '
          'volatilidade ${_pct(e.volatility)}',
          [
            for (final v in e.views) '${v.model}: ${_pct(v.value)}',
            if (e.beta != null)
              'β contra o Ibovespa: ${e.beta!.toStringAsFixed(2).replaceAll('.', ',')}',
          ].join(' • '),
        ),
      const InfoSection(
        'Harry Markowitz (1952)',
        'Escolhe os pesos que maximizam retorno esperado − (γ/2) × '
            'variância, considerando como as classes oscilam juntas '
            '(covariâncias de até 5 anos de preços mensais). O γ vem das '
            'suas respostas sobre troca de emprego (Arrow-Pratt).',
      ),
      InfoSection(
        'John Burr Williams (1938) e Aswath Damodaran',
        'O valor de um ativo é o valor presente dos fluxos futuros, '
            'descontados pelo retorno exigido. Retorno exigido das ações '
            '= Selic − spread de default do Brasil '
            '(${_pct(Assumptions.brazilDefaultSpread, digits: 2)}) + β × '
            'prêmio de risco do Brasil '
            '(${_pct(Assumptions.brazilTotalErp, digits: 2)}, Damodaran, '
            '${Assumptions.damodaranDate}).',
      ),
      const InfoSection(
        'Eugene Fama e Kenneth French (1993)',
        'Empresas menores e mais baratas tendem a render mais no longo '
            'prazo. Os prêmios de tamanho (SMAL11 − BOVA11) e de valor '
            '(DIVO11 − BOVA11) são estimados com os dados e reduzidos à '
            'metade por cautela. No ranking de ações, valor = dividend '
            'yield e tamanho = valor de mercado.',
      ),
      InfoSection(
        'Benjamin Graham (1949)',
        'Em "O Investidor Inteligente", Graham só pagava até 15 vezes o '
            'lucro e 1,5 vez o patrimônio: preço justo = √(22,5 × LPA × '
            'VPA). Empresa com prejuízo fica de fora. Ele pedia ainda '
            '${_pct(Assumptions.marginOfSafety, digits: 0)} de desconto '
            '(margem de segurança) para comprar. No ranking de ações, o '
            'preço justo é a média de Graham e Gordon.',
      ),
      InfoSection(
        'Myron Gordon e Eli Shapiro (1956)',
        'Retorno = dividend yield × (1 + g) + g, com g = IPCA esperado '
            'de longo prazo (${_pct(macro.ipcaLongTerm / 100)}, Focus). '
            'Yields de referência: ações pagadoras '
            '${_pct(Assumptions.referenceDyDividends)} e FIIs '
            '${_pct(Assumptions.referenceDyReits)} (medianas, '
            '${Assumptions.referenceDyDate}).',
      ),
      const InfoSection(
        'Robert Metcalfe e Chris Burniske (2017)',
        'O valor de uma rede cresce com o quadrado dos usuários. O '
            'valor do Bitcoin é comparado a k × (endereços ativos)², com '
            'k calibrado nos últimos 4 anos.',
      ),
      const InfoSection(
        'PlanB (2019), inspirado em Saifedean Ammous',
        'Stock-to-flow mede a escassez (estoque ÷ emissão anual). '
            'Mostrado como curiosidade: as previsões do modelo falharam '
            'desde 2021.',
      ),
    ];
