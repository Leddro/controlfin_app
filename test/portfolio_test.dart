import 'dart:math' as math;

import 'package:financas_app/models/investor_profile.dart';
import 'package:financas_app/models/market/market_data.dart';
import 'package:financas_app/models/market/portfolio_engine.dart';
import 'package:financas_app/models/market/portfolio_math.dart';
import 'package:financas_app/services/market/market_sources.dart';
import 'package:flutter_test/flutter_test.dart';

/// Série mensal sintética: retorno = drift + sensibilidade·choque comum +
/// ruído próprio (pseudoaleatório com semente fixa).
PriceSeries synthetic(String symbol, double drift, double sens, double noise,
    {int months = 72, int seed = 1}) {
  final common = math.Random(42);
  final own = math.Random(seed);
  final monthly = <String, double>{};
  var p = 100.0;
  for (var i = 0; i < months; i++) {
    final shock = common.nextDouble() - 0.5;
    final r = drift + sens * shock * 0.12 + noise * (own.nextDouble() - 0.5);
    p *= 1 + r;
    final y = 2020 + i ~/ 12, m = i % 12 + 1;
    monthly['$y-${m.toString().padLeft(2, '0')}'] = p;
  }
  return PriceSeries(symbol, monthly);
}

MarketData syntheticMarket({BitcoinSnapshot? bitcoin}) => MarketData(
      macro: MacroSnapshot(
        selic: 13.75,
        ipca12m: 4.6,
        ipcaLongTerm: 4.0,
        usTreasury10y: 4.2,
        fetchedAt: DateTime(2026, 11, 15),
      ),
      etfs: {
        'BOVA11.SAO': synthetic('BOVA11.SAO', 0.010, 1.0, 0.02, seed: 2),
        'SMAL11.SAO': synthetic('SMAL11.SAO', 0.011, 1.3, 0.04, seed: 3),
        'DIVO11.SAO': synthetic('DIVO11.SAO', 0.011, 0.8, 0.02, seed: 4),
        'XFIX11.SAO': synthetic('XFIX11.SAO', 0.008, 0.4, 0.03, seed: 5),
        'IVVB11.SAO': synthetic('IVVB11.SAO', 0.012, 0.2, 0.05, seed: 6),
      },
      bitcoin: bitcoin,
    );

InvestorProfile profile(Map<String, int> changes) => InvestorProfile(
      answers: {
        'goal': 3,
        'horizon': 4,
        'age': 1,
        'income': 0,
        'reserve': 3,
        'dependents': 0,
        'experience': 3,
        'gamble': 1,
        'gambleFollow': 1,
        'drop': 3,
        'range': 3,
        ...changes,
      },
      createdAt: DateTime(2026, 11, 15),
    );

void main() {
  group('matemática', () {
    test('projeção respeita soma 1 e limites', () {
      final w = projectToBoxSimplex([0.9, 0.5, -0.2], [0, 0, 0.1], [0.6, 1, 1]);
      expect(w.reduce((a, b) => a + b), closeTo(1, 1e-9));
      expect(w[0], lessThanOrEqualTo(0.6 + 1e-9));
      expect(w[2], greaterThanOrEqualTo(0.1 - 1e-9));
    });

    test('dois ativos: bate com a fórmula de Merton', () {
      // Ativo sem risco (μ=10%) e arriscado (μ=16%, σ=20%), γ=3:
      // fração no arriscado = (0,16 − 0,10)/(3·0,04) = 50%.
      final w = optimizeMeanVariance(
        mu: [0.10, 0.16],
        cov: [
          [0, 0],
          [0, 0.04],
        ],
        gamma: 3,
        lower: [0, 0],
        upper: [1, 1],
      );
      expect(w[1], closeTo(0.5, 0.01));
    });

    test('beta da própria série é 1', () {
      final r = alignedMonthlyReturns([
        synthetic('A', 0.01, 1, 0.02),
        synthetic('A', 0.01, 1, 0.02),
      ]);
      expect(beta(r[0], r[1]), closeTo(1, 1e-9));
    });
  });

  group('carteira', () {
    test('soma 100% e respeita os limites do perfil arrojado', () {
      final plan = PortfolioEngine.build(profile({}), syntheticMarket())!;
      final total = plan.weights.values.reduce((a, b) => a + b);
      expect(total, closeTo(1, 1e-9));
      expect(plan.weights[AssetClass.fixedIncome] ?? 0,
          greaterThanOrEqualTo(0.05 - 1e-9));
      for (final e in plan.weights.entries) {
        if (e.key == AssetClass.fixedIncome) continue;
        expect(e.value, lessThanOrEqualTo(0.35 + 1e-9));
      }
      expect(plan.gamma, 1.2);
      expect(plan.frontier.length, greaterThan(5));
    });

    test('mais aversão ao risco: mais renda fixa', () {
      final ousado = PortfolioEngine.build(profile({}), syntheticMarket())!;
      final cauteloso = PortfolioEngine.build(
          profile({'gamble': 0, 'gambleFollow': 0, 'drop': 1, 'range': 1}),
          syntheticMarket())!;
      expect(cauteloso.weights[AssetClass.fixedIncome]!,
          greaterThan(ousado.weights[AssetClass.fixedIncome] ?? 0));
    });

    test('dinheiro para menos de 1 ano: 100% renda fixa', () {
      final plan =
          PortfolioEngine.build(profile({'horizon': 0}), syntheticMarket())!;
      expect(plan.weights, {AssetClass.fixedIncome: 1.0});
      expect(plan.notes.single, contains('Tesouro Selic'));
    });

    test('retornos esperados seguem os modelos', () {
      final plan = PortfolioEngine.build(profile({}), syntheticMarket())!;
      ClassEstimate e(AssetClass c) =>
          plan.estimates.firstWhere((x) => x.assetClass == c);
      // Renda fixa = Selic.
      expect(e(AssetClass.fixedIncome).expectedReturn, closeTo(0.1375, 1e-9));
      // BOVA11 = (Selic − spread) + prêmio total de Damodaran.
      expect(e(AssetClass.brStocks).expectedReturn,
          closeTo(0.1375 - 0.0213 + 0.0747, 1e-9));
      // FIIs: média de CAPM e Gordon (10,5% × 1,04 + 4%).
      final reits = e(AssetClass.reits);
      expect(reits.views.map((v) => v.model), contains('Gordon'));
      expect(reits.views.last.value, closeTo(0.105 * 1.04 + 0.04, 1e-9));
      // Exterior: 4,2% + 4,23%, mais a média das duas visões de câmbio:
      // inflação (4% − 2,5%) e juros (13,75% − 4,2%).
      expect(e(AssetClass.global).expectedReturn,
          closeTo(0.042 + 0.0423 + (0.015 + (0.1375 - 0.042)) / 2, 1e-9));
    });

    test('sem Selic ou sem BOVA11 não monta carteira', () {
      expect(PortfolioEngine.build(profile({}), const MarketData()), isNull);
    });
  });

  group('Bitcoin', () {
    BitcoinSnapshot btc(double metcalfe) => BitcoinSnapshot(
          priceUsd: 60000,
          marketCapUsd: 1.2e12,
          activeAddresses: 6e5,
          metcalfeRatio: metcalfe,
          stockToFlow: 120,
          s2fModelPriceUsd: 800000,
          fetchedAt: DateTime(2026, 11, 15),
        );

    test('peso cai quando está caro pela métrica de Metcalfe', () {
      final barato = PortfolioEngine.build(
          profile({}), syntheticMarket(bitcoin: btc(0.7)))!;
      final caro = PortfolioEngine.build(
          profile({}), syntheticMarket(bitcoin: btc(2.0)))!;
      expect(barato.bitcoinSignal, BitcoinSignal.cheap);
      expect(caro.bitcoinSignal, BitcoinSignal.expensive);
      expect(barato.weights[AssetClass.bitcoin], 0.06);
      expect(caro.weights[AssetClass.bitcoin], 0.02);
    });

    test('conservador não recebe Bitcoin', () {
      final plan = PortfolioEngine.build(
          profile({'gamble': 0, 'gambleFollow': 0, 'drop': 0, 'range': 0}),
          syntheticMarket(bitcoin: btc(0.5)))!;
      expect(plan.weights[AssetClass.bitcoin], isNull);
    });

    test('Metcalfe e stock-to-flow a partir do histórico', () {
      // Valor exatamente proporcional a n²: razão de Metcalfe = 1.
      final days = [
        for (var i = 0; i < 800; i++)
          BtcDay(
            DateTime(2023, 1, 1).add(Duration(days: i)),
            500000 + i * 100.0,
            2.0 * math.pow(500000 + i * 100.0, 2),
            19e6 + i * 450.0,
            60000,
          ),
      ];
      final s = bitcoinFromHistory(days);
      expect(s.metcalfeRatio, closeTo(1, 0.05));
      // Emissão de 450/dia: S2F ≈ oferta ÷ (450 × 365).
      expect(s.stockToFlow, closeTo((19e6 + 799 * 450) / (450 * 365), 1));
    });
  });

  test('ranking de ações: Gordon e fatores', () {
    final market = synthetic('BOVA11.SAO', 0.01, 1, 0.02, seed: 2);
    StockQuote q(String s, double price, double div, double cap, int seed) =>
        StockQuote(
          symbol: s,
          price: price,
          dividends12m: div,
          marketCap: cap,
          history: synthetic(s, 0.01, 1, 0.03, seed: seed),
        );
    final ideas = PortfolioEngine.rankStocks(
      [
        q('BARATA', 10, 1.5, 5e9, 7), // DY 15%, pequena
        q('CARA', 100, 2, 300e9, 8), // DY 2%, grande
        q('SEMDIV', 50, 0, 50e9, 9),
      ],
      market,
      MacroSnapshot(
        selic: 13.75,
        ipca12m: 4.6,
        ipcaLongTerm: 4.0,
        fetchedAt: DateTime(2026, 11, 15),
      ),
    );
    expect(ideas.first.quote.symbol, 'BARATA');
    expect(ideas.last.quote.symbol, isNot('BARATA'));
    final semDiv = ideas.firstWhere((i) => i.quote.symbol == 'SEMDIV');
    expect(semDiv.gordonFairPrice, isNull);
    final barata = ideas.first;
    // Preço justo = D·(1+g)/(k − g).
    expect(barata.gordonFairPrice,
        closeTo(1.5 * 1.04 / (barata.requiredReturn - 0.04), 1e-6));
  });
}
