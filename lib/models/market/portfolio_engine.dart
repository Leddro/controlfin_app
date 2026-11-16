/// Monta a carteira sugerida a partir do perfil e dos dados de mercado.
///
/// Retorno esperado de cada classe (média das "visões" de cada modelo):
/// * Renda fixa: Selic.
/// * Ações (CAPM com prêmio de risco de Damodaran, inspirado no valor
///   presente de Williams): (Selic − spread de default) + β × prêmio Brasil.
/// * Small caps e dividendos: CAPM + prêmio de tamanho / valor de Fama-French,
///   estimado com SMAL11 e DIVO11 contra BOVA11.
/// * Dividendos e FIIs: também Gordon & Shapiro, DY × (1 + g) + g.
/// * Exterior: juros dos EUA + prêmio maduro de Damodaran + desvalorização
///   esperada do real (diferença de inflação).
///
/// Os pesos saem de Markowitz (média-variância) com o γ de Arrow-Pratt do
/// perfil e limites por perfil. Bitcoin entra à parte (satélite), ajustado
/// pelo sinal de Metcalfe.
library;

import 'dart:math' as math;

import '../investor_profile.dart';
import 'market_data.dart';
import 'portfolio_math.dart';

/// Premissas fixas, com fonte e data. Revisar de tempos em tempos.
class Assumptions {
  /// Damodaran, "Country Default Spreads and Risk Premiums", 05/01/2026.
  static const brazilTotalErp = 0.0747;
  static const brazilDefaultSpread = 0.0213;
  static const matureMarketErp = 0.0423;
  static const damodaranDate = 'jan/2026';

  /// Mediana do dividend yield de 12 meses (Yahoo Finance, 15/11/2026):
  /// 15 ações pagadoras e 10 FIIs grandes.
  static const referenceDyDividends = 0.072;
  static const referenceDyReits = 0.105;
  static const referenceDyDate = '15/11/2026';

  /// Inflação de longo prazo esperada nos EUA, para a paridade de poder de
  /// compra (desvalorização esperada do real ≈ IPCA − inflação dos EUA).
  static const usInflation = 0.025;

  /// Fração dos prêmios de Fama-French estimados que entra no retorno
  /// esperado (os prêmios históricos são ruidosos) e o limite de cada um.
  static const factorShrink = 0.5;
  static const factorCap = 0.03;

  /// Volatilidade anual atribuída à renda fixa pós-fixada.
  static const fixedIncomeVol = 0.01;

  /// Volatilidade anual usada para o Bitcoin nas contas da carteira.
  static const bitcoinVol = 0.60;
}

enum AssetClass {
  fixedIncome,
  brStocks,
  smallCaps,
  dividends,
  reits,
  global,
  bitcoin
}

extension AssetClassInfo on AssetClass {
  String get label => switch (this) {
        AssetClass.fixedIncome => 'Renda fixa pós-fixada',
        AssetClass.brStocks => 'Ações Brasil',
        AssetClass.smallCaps => 'Small caps',
        AssetClass.dividends => 'Ações de dividendos',
        AssetClass.reits => 'Fundos imobiliários',
        AssetClass.global => 'Exterior',
        AssetClass.bitcoin => 'Bitcoin',
      };

  String get examples => switch (this) {
        AssetClass.fixedIncome => 'Tesouro Selic, CDB 100% do CDI',
        AssetClass.brStocks => 'BOVA11 (Ibovespa)',
        AssetClass.smallCaps => 'SMAL11',
        AssetClass.dividends => 'DIVO11',
        AssetClass.reits => 'XFIX11 (IFIX)',
        AssetClass.global => 'IVVB11 (S&P 500 em reais)',
        AssetClass.bitcoin => 'QBTC11 ou BITH11 (ETFs de bitcoin)',
      };

  /// Símbolo na Alpha Vantage (nulo: sem série de preço).
  String? get symbol => switch (this) {
        AssetClass.brStocks => 'BOVA11.SAO',
        AssetClass.smallCaps => 'SMAL11.SAO',
        AssetClass.dividends => 'DIVO11.SAO',
        AssetClass.reits => 'XFIX11.SAO',
        AssetClass.global => 'IVVB11.SAO',
        _ => null,
      };
}

/// ETF sugerido para comprar em cada classe (nulo: compra fora da bolsa).
String? productFor(AssetClass c) => switch (c) {
      AssetClass.brStocks => 'BOVA11',
      AssetClass.smallCaps => 'SMAL11',
      AssetClass.dividends => 'DIVO11',
      AssetClass.reits => 'XFIX11',
      AssetClass.global => 'IVVB11',
      AssetClass.bitcoin => 'QBTC11',
      AssetClass.fixedIncome => null,
    };

/// ETFs que a carteira usa (BOVA11 também é o "mercado" dos betas).
final etfSymbols = [
  for (final c in AssetClass.values)
    if (c.symbol != null) c.symbol!,
];

/// Uma estimativa de retorno feita por um modelo.
class ModelView {
  final String model;
  final double value;

  const ModelView(this.model, this.value);
}

class ClassEstimate {
  final AssetClass assetClass;
  final List<ModelView> views;
  final double volatility;
  final double? beta;

  const ClassEstimate({
    required this.assetClass,
    required this.views,
    required this.volatility,
    this.beta,
  });

  double get expectedReturn =>
      views.map((v) => v.value).reduce((a, b) => a + b) / views.length;
}

class FrontierPoint {
  final double volatility;
  final double expectedReturn;

  const FrontierPoint(this.volatility, this.expectedReturn);
}

enum BitcoinSignal { cheap, fair, expensive }

class StockIdea {
  final StockQuote quote;
  final double beta;
  final double requiredReturn;
  final double? gordonFairPrice;
  final double score;

  const StockIdea({
    required this.quote,
    required this.beta,
    required this.requiredReturn,
    required this.gordonFairPrice,
    required this.score,
  });

  double? get upside =>
      gordonFairPrice == null ? null : gordonFairPrice! / quote.price - 1;
}

class PortfolioPlan {
  final Map<AssetClass, double> weights;
  final List<ClassEstimate> estimates;
  final double gamma;
  final double expectedReturn;
  final double volatility;
  final double riskFree;
  final List<FrontierPoint> frontier;
  final FrontierPoint userPoint;
  final BitcoinSignal? bitcoinSignal;
  final List<StockIdea> stocks;

  /// Explicações para mostrar junto da carteira.
  final List<String> notes;

  const PortfolioPlan({
    required this.weights,
    required this.estimates,
    required this.gamma,
    required this.expectedReturn,
    required this.volatility,
    required this.riskFree,
    required this.frontier,
    required this.userPoint,
    required this.bitcoinSignal,
    required this.stocks,
    required this.notes,
  });
}

/// γ representativo de cada faixa de aversão ao risco do questionário.
double gammaFor(RiskAversionClass c) => switch (c) {
      RiskAversionClass.veryHigh => 8,
      RiskAversionClass.high => 4,
      RiskAversionClass.moderate => 2,
      RiskAversionClass.low => 1.2,
    };

/// Limites por classe de acordo com o perfil: (mínimo, máximo).
(double, double) boundsFor(InvestorType type, AssetClass c) {
  if (c == AssetClass.fixedIncome) {
    return switch (type) {
      InvestorType.conservative => (0.60, 1.0),
      InvestorType.moderate => (0.30, 1.0),
      InvestorType.aggressive => (0.05, 1.0),
    };
  }
  final reits = c == AssetClass.reits;
  return switch (type) {
    InvestorType.conservative => (0.0, 0.10),
    InvestorType.moderate => (0.0, reits ? 0.15 : 0.20),
    InvestorType.aggressive => (0.0, reits ? 0.20 : 0.35),
  };
}

/// Teto de Bitcoin por perfil, antes do sinal de Metcalfe.
double bitcoinCap(InvestorType type) => switch (type) {
      InvestorType.conservative => 0,
      InvestorType.moderate => 0.03,
      InvestorType.aggressive => 0.06,
    };

BitcoinSignal bitcoinSignalFor(double metcalfeRatio) => metcalfeRatio < 0.9
    ? BitcoinSignal.cheap
    : metcalfeRatio <= 1.4
        ? BitcoinSignal.fair
        : BitcoinSignal.expensive;

double _bitcoinMultiplier(BitcoinSignal s) => switch (s) {
      BitcoinSignal.cheap => 1.0,
      BitcoinSignal.fair => 0.7,
      BitcoinSignal.expensive => 0.35,
    };

class PortfolioEngine {
  /// Nulo quando faltam os dados mínimos (Selic e a série do BOVA11).
  static PortfolioPlan? build(InvestorProfile profile, MarketData data) {
    final macro = data.macro;
    final market = data.etfs[AssetClass.brStocks.symbol];
    if (macro == null || market == null) return null;

    final rf = macro.selic / 100;
    final rfBase = rf - Assumptions.brazilDefaultSpread;
    final g = macro.ipcaLongTerm / 100;
    final notes = <String>[];

    // Classes com série disponível (BOVA11 sempre, pois é o mercado).
    final risky = [
      for (final c in AssetClass.values)
        if (c.symbol != null && data.etfs[c.symbol] != null) c,
    ];
    final returns =
        alignedMonthlyReturns([for (final c in risky) data.etfs[c.symbol]!]);
    final marketIdx = risky.indexOf(AssetClass.brStocks);
    final mkt = returns[marketIdx];

    double factorPremium(AssetClass c) {
      final i = risky.indexOf(c);
      if (i < 0) return 0;
      final spread = [
        for (var k = 0; k < mkt.length; k++) returns[i][k] - mkt[k],
      ];
      return (mean(spread) * 12 * Assumptions.factorShrink)
          .clamp(-Assumptions.factorCap, Assumptions.factorCap);
    }

    final estimates = <ClassEstimate>[
      ClassEstimate(
        assetClass: AssetClass.fixedIncome,
        views: [ModelView('Selic', rf)],
        volatility: Assumptions.fixedIncomeVol,
      ),
    ];

    for (var i = 0; i < risky.length; i++) {
      final c = risky[i];
      final b = c == AssetClass.brStocks ? 1.0 : beta(returns[i], mkt);
      final capm = rfBase + b * Assumptions.brazilTotalErp;
      final vol = math.sqrt(covariance(returns[i], returns[i]) * 12);
      final views = <ModelView>[];
      switch (c) {
        case AssetClass.brStocks:
          views.add(ModelView('CAPM (Damodaran)', capm));
        case AssetClass.smallCaps:
          views.add(ModelView('CAPM + tamanho (Fama-French)',
              capm + factorPremium(AssetClass.smallCaps)));
        case AssetClass.dividends:
          views
            ..add(ModelView('CAPM + valor (Fama-French)',
                capm + factorPremium(AssetClass.dividends)))
            ..add(ModelView(
                'Gordon', Assumptions.referenceDyDividends * (1 + g) + g));
        case AssetClass.reits:
          views
            ..add(ModelView('CAPM (Damodaran)', capm))
            ..add(ModelView(
                'Gordon', Assumptions.referenceDyReits * (1 + g) + g));
        case AssetClass.global:
          // Retorno em dólar (Damodaran: juros dos EUA + prêmio maduro) mais
          // a desvalorização esperada do real, por duas visões:
          // paridade de inflação (IPCA − inflação dos EUA) e paridade de
          // juros (Selic − juros dos EUA).
          final us = (macro.usTreasury10y ?? 4.0) / 100;
          final usd = us + Assumptions.matureMarketErp;
          views
            ..add(ModelView('Damodaran + câmbio (inflação)',
                usd + (g - Assumptions.usInflation)))
            ..add(ModelView('Damodaran + câmbio (juros)', usd + (rf - us)));
        default:
          break;
      }
      estimates.add(
          ClassEstimate(assetClass: c, views: views, volatility: vol, beta: b));
    }

    // Covariância: renda fixa sem correlação, ETFs pelos retornos mensais.
    final riskyCov = annualCovariance(returns);
    final n = estimates.length;
    final cov = [
      for (var i = 0; i < n; i++)
        [
          for (var j = 0; j < n; j++)
            i == 0 || j == 0
                ? (i == j
                    ? math.pow(Assumptions.fixedIncomeVol, 2).toDouble()
                    : 0.0)
                : riskyCov[i - 1][j - 1],
        ],
    ];
    final mu = [for (final e in estimates) e.expectedReturn];
    final gamma = gammaFor(profile.riskAversion);
    final type = profile.type;

    // Fronteira eficiente sem os limites do perfil (só sem venda a descoberto).
    final frontier = <FrontierPoint>[];
    for (var k = 0; k <= 24; k++) {
      final gk = 0.3 * math.pow(200, k / 24);
      final w = optimizeMeanVariance(
        mu: mu,
        cov: cov,
        gamma: gk.toDouble(),
        lower: List.filled(n, 0),
        upper: List.filled(n, 1),
        iterations: 1500,
      );
      frontier.add(
          FrontierPoint(portfolioVolatility(w, cov), portfolioReturn(w, mu)));
    }
    frontier.sort((a, b) => a.volatility.compareTo(b.volatility));

    // Carteira do perfil.
    late List<double> w;
    if (profile.conservativeCap != null) {
      w = [1.0, ...List.filled(n - 1, 0.0)];
      notes.add('${profile.conservativeCap} Por isso a sugestão é 100% em '
          'renda fixa com liquidez diária, como o Tesouro Selic.');
    } else {
      final bounds = [for (final e in estimates) boundsFor(type, e.assetClass)];
      w = optimizeMeanVariance(
        mu: mu,
        cov: cov,
        gamma: gamma,
        lower: [for (final b in bounds) b.$1],
        upper: [for (final b in bounds) b.$2],
      );
    }
    final expected = portfolioReturn(w, mu);
    var vol = portfolioVolatility(w, cov);

    final weights = <AssetClass, double>{
      for (var i = 0; i < n; i++) estimates[i].assetClass: w[i],
    };

    // Bitcoin como satélite.
    BitcoinSignal? signal;
    final btc = data.bitcoin;
    if (btc != null) {
      signal = bitcoinSignalFor(btc.metcalfeRatio);
      final cap = profile.conservativeCap != null ? 0.0 : bitcoinCap(type);
      final b = cap * _bitcoinMultiplier(signal);
      if (b > 0) {
        weights.updateAll((_, v) => v * (1 - b));
        weights[AssetClass.bitcoin] = b;
        vol = math.sqrt(math.pow((1 - b) * vol, 2) +
            math.pow(b * Assumptions.bitcoinVol, 2));
      }
    }

    // Arredonda para pontos percentuais inteiros sem perder a soma de 100%.
    _roundWeights(weights);

    return PortfolioPlan(
      weights: weights,
      estimates: estimates,
      gamma: gamma,
      expectedReturn: expected,
      volatility: vol,
      riskFree: rf,
      frontier: frontier,
      userPoint:
          FrontierPoint(portfolioVolatility(w, cov), portfolioReturn(w, mu)),
      bitcoinSignal: signal,
      stocks: rankStocks(data.stocks, market, macro),
      notes: notes,
    );
  }

  /// Ranking educativo de ações: Gordon (preço justo com o retorno exigido
  /// pelo CAPM) + fatores de Fama-French (valor pelo dividend yield e
  /// tamanho pelo valor de mercado).
  static List<StockIdea> rankStocks(
      List<StockQuote> stocks, PriceSeries market, MacroSnapshot macro) {
    if (stocks.isEmpty) return const [];
    final rfBase = macro.selic / 100 - Assumptions.brazilDefaultSpread;
    final g = macro.ipcaLongTerm / 100;

    final raw = <(StockQuote, double, double, double?)>[];
    for (final s in stocks) {
      final r = alignedMonthlyReturns([s.history, market]);
      final b = r.isNotEmpty && r[0].length >= 24
          ? beta(r[0], r[1]).clamp(0.4, 2.0).toDouble()
          : 1.0;
      final k = rfBase + b * Assumptions.brazilTotalErp;
      final d1 = s.dividends12m * (1 + g);
      final fair = s.dividends12m > 0 && k - g > 0.02 ? d1 / (k - g) : null;
      raw.add((s, b, k, fair));
    }

    List<double> z(List<double> xs) {
      final m = mean(xs);
      final sd = math.sqrt(covariance(xs, xs));
      return [for (final x in xs) sd == 0 ? 0 : ((x - m) / sd).clamp(-2, 2)];
    }

    final upsides = [
      for (final r in raw) r.$4 == null ? -0.5 : r.$4! / r.$1.price - 1,
    ];
    final values = [for (final r in raw) r.$1.dividendYield];
    final caps = [for (final r in raw) r.$1.marketCap].whereType<double>();
    final medianCap =
        caps.isEmpty ? 1.0 : (caps.toList()..sort())[caps.length ~/ 2];
    final sizes = [
      for (final r in raw) -math.log(r.$1.marketCap ?? medianCap),
    ];
    final zu = z(upsides), zv = z(values), zs = z(sizes);

    final ideas = [
      for (var i = 0; i < raw.length; i++)
        StockIdea(
          quote: raw[i].$1,
          beta: raw[i].$2,
          requiredReturn: raw[i].$3,
          gordonFairPrice: raw[i].$4,
          score: 0.5 * zu[i] + 0.25 * zv[i] + 0.25 * zs[i],
        ),
    ]..sort((a, b) => b.score.compareTo(a.score));
    return ideas;
  }

  static void _roundWeights(Map<AssetClass, double> weights) {
    final keys = weights.keys.toList();
    final pts = {for (final k in keys) k: (weights[k]! * 100).floor()};
    var missing = 100 - pts.values.fold(0, (a, b) => a + b);
    final byRemainder = keys.toList()
      ..sort((a, b) =>
          (weights[b]! * 100 - pts[b]!).compareTo(weights[a]! * 100 - pts[a]!));
    for (final k in byRemainder) {
      if (missing <= 0) break;
      pts[k] = pts[k]! + 1;
      missing--;
    }
    for (final k in keys) {
      weights[k] = pts[k]! / 100;
    }
    weights.removeWhere((_, v) => v == 0);
  }
}
