import 'dart:math' as math;

import 'package:financas_app/models/market/market_data.dart';
import 'package:financas_app/models/market/portfolio_engine.dart';
import 'package:financas_app/models/market/stock_advice.dart';
import 'package:financas_app/models/market/tickers.dart';
import 'package:financas_app/services/market/market_sources.dart';
import 'package:flutter_test/flutter_test.dart';

import 'portfolio_test.dart' show synthetic;

/// Série que segue o "mercado" (choque comum) ou só o próprio ruído.
PriceSeries _series(String s, {required bool followsMarket, int seed = 1}) =>
    synthetic(s, 0.01, followsMarket ? 1.0 : 0.0, followsMarket ? 0.01 : 0.08,
        seed: seed);

StockIdea _idea(
  String symbol, {
  double price = 10,
  double? gordon,
  double? graham,
  double? netIncome = 1e9,
  double score = 0,
  double dividends = 0,
  bool followsMarket = true,
  int seed = 1,
}) =>
    StockIdea(
      quote: StockQuote(
        symbol: symbol,
        price: price,
        dividends12m: dividends,
        netIncome: netIncome,
        history: _series(symbol, followsMarket: followsMarket, seed: seed),
      ),
      beta: 1,
      requiredReturn: 0.15,
      gordonFairPrice: gordon,
      grahamFairPrice: graham,
      score: score,
    );

void main() {
  group('Graham', () {
    test('preço justo = √(22,5 × LPA × VPA)', () {
      expect(grahamFairPrice(2, 20), closeTo(math.sqrt(22.5 * 2 * 20), 1e-9));
      expect(grahamFairPrice(-1, 20), isNull, reason: 'prejuízo');
      expect(grahamFairPrice(2, -5), isNull, reason: 'patrimônio negativo');
      expect(grahamFairPrice(null, 20), isNull);
    });

    test('LPA e VPA pelo valor de mercado também valem para units', () {
      // Unit a R$ 30 de uma empresa de R$ 30 bi (1 bi de units): lucro de
      // R$ 3 bi = R$ 3 por unit, mesmo que a empresa tenha 3 bi de ações.
      const q = StockQuote(
        symbol: 'TAEE11',
        price: 30,
        dividends12m: 0,
        marketCap: 30e9,
        netIncome: 3e9,
        equity: 15e9,
        history: PriceSeries('TAEE11', {}),
      );
      expect(q.earningsPerShare, closeTo(3, 1e-9));
      expect(q.bookValuePerShare, closeTo(15, 1e-9));
      const semValor = StockQuote(
        symbol: 'X',
        price: 30,
        dividends12m: 0,
        netIncome: 3e9,
        history: PriceSeries('X', {}),
      );
      expect(semValor.earningsPerShare, isNull);
    });

    test('ranking usa a média de Gordon e Graham', () {
      final market = synthetic('BOVA11.SAO', 0.01, 1, 0.02, seed: 2);
      StockQuote q(String s, double price, double div, double ni, double eq,
              int seed) =>
          StockQuote(
            symbol: s,
            price: price,
            dividends12m: div,
            marketCap: price * 1e9,
            netIncome: ni,
            equity: eq,
            history: synthetic(s, 0.01, 1, 0.03, seed: seed),
          );
      final ideas = PortfolioEngine.rankStocks(
        [
          // P/L 4 e P/VP 0,8: Graham bem acima do preço.
          q('BARATA', 20, 0, 5e9, 25e9, 7),
          // P/L 50 e P/VP 10: Graham bem abaixo.
          q('CARA', 50, 0, 1e9, 5e9, 8),
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
      final barata = ideas.first;
      expect(barata.grahamFairPrice,
          closeTo(math.sqrt(22.5 * 5 * 25), 1e-6)); // LPA 5, VPA 25
      expect(barata.gordonFairPrice, isNull);
      // Sem Gordon, o desconto médio é só o de Graham.
      expect(barata.upside, closeTo(barata.grahamUpside!, 1e-9));
    });
  });

  group('tickers', () {
    test('ação de empresa: ON, PN e units conhecidas', () {
      expect(isCompanyStock('PETR4'), isTrue);
      expect(isCompanyStock('wege3'), isTrue);
      expect(isCompanyStock('TAEE11'), isTrue);
      expect(isCompanyStock('HGLG11'), isFalse, reason: 'FII');
      expect(isCompanyStock('BOVA11'), isFalse, reason: 'ETF');
      expect(isCompanyStock('AAPL34'), isFalse, reason: 'BDR');
    });
  });

  group('Yahoo: lucro e patrimônio', () {
    Map<String, Object> series(String type, List<(String, String, num)> pts) =>
        {
          'meta': {
            'type': [type]
          },
          type: [
            for (final (date, cur, v) in pts)
              {
                'asOfDate': date,
                'currencyCode': cur,
                'reportedValue': {'raw': v},
              },
          ],
        };

    test('pega o mais recente e converte dólar', () {
      final json = {
        'timeseries': {
          'result': [
            series('trailingNetIncomeCommonStockholders', [
              ('2026-09-30', 'USD', 20e9),
              ('2026-06-30', 'USD', 10e9),
            ]),
            series('quarterlyCommonStockEquity', [
              ('2026-06-30', 'USD', 90e9),
            ]),
            series('quarterlyOrdinarySharesNumber', [
              ('2026-06-30', 'USD', 13e9),
            ]),
          ],
        },
      };
      final f = parseYahooFundamentals(json, usdBrl: 5);
      expect(f.netIncome, 100e9);
      expect(f.equity, 450e9);
      expect(f.shares, 13e9, reason: 'quantidade não é dinheiro');
      expect(parseYahooFundamentals(json).netIncome, isNull,
          reason: 'sem câmbio não dá para converter');
    });

    test('em reais fica como está; resposta vazia não quebra', () {
      final f = parseYahooFundamentals({
        'timeseries': {
          'result': [
            series('trailingNetIncomeCommonStockholders',
                [('2026-09-30', 'BRL', 6.27e9)]),
            {
              'meta': {
                'type': ['quarterlyCommonStockEquity']
              },
            },
          ],
        },
      });
      expect(f.netIncome, 6.27e9);
      expect(f.equity, isNull);
      expect(parseYahooFundamentals(null).netIncome, isNull);
    });
  });

  group('ações da carteira', () {
    test('veredito de cada ação que o usuário tem', () {
      final ideas = [
        _idea('BARA3', graham: 20, gordon: 14, seed: 3), // +70%
        _idea('JUST3', graham: 11, gordon: 10, seed: 4), // +5%
        _idea('CARA3', graham: 5, gordon: 6, seed: 5), // -45%
        _idea('PREJ3', netIncome: -1e6, gordon: 30, seed: 6),
      ];
      final advice = adviseStocks(ideas: ideas, heldValues: {
        'BARA3': 1000,
        'JUST3': 1000,
        'CARA3': 1000,
        'PREJ3': 1000,
        'NOVA3': 1000,
      });
      final v = {for (final r in advice.held) r.ticker: r.verdict};
      expect(v['BARA3'], HeldVerdict.reinforce);
      expect(v['JUST3'], HeldVerdict.keep);
      expect(v['CARA3'], HeldVerdict.hold);
      expect(v['PREJ3'], HeldVerdict.hold, reason: 'Graham exige lucro');
      expect(v['NOVA3'], HeldVerdict.noData);
      expect(advice.held.first.share, closeTo(0.2, 1e-9));
    });

    test('barata mas concentrada: manter e diversificar', () {
      final advice = adviseStocks(
        ideas: [_idea('BARA3', graham: 20, seed: 3), _idea('OUTR3', seed: 4)],
        heldValues: {'BARA3': 9000, 'OUTR3': 1000},
      );
      final bara = advice.held.firstWhere((r) => r.ticker == 'BARA3');
      expect(bara.verdict, HeldVerdict.keep);
      expect(bara.reason, contains('90%'));
    });

    test(
        'sugestões: fora da carteira, sem caras nem prejuízo, e as que '
        'oscilam diferente vêm antes', () {
      final ideas = [
        _idea('TENH3', graham: 20, seed: 3),
        // Mesma nota; uma segue o mercado (como a do usuário), a outra não.
        _idea('JUNT3', graham: 20, seed: 4),
        _idea('DIFE3', graham: 20, followsMarket: false, seed: 5),
        _idea('CARA3', graham: 5, score: 3, seed: 6),
        _idea('PREJ3', netIncome: -1, gordon: 30, score: 3, seed: 7),
      ];
      final advice = adviseStocks(ideas: ideas, heldValues: {'TENH3': 1000});
      final tickers = [for (final s in advice.suggestions) s.idea.quote.symbol];
      expect(tickers, ['DIFE3', 'JUNT3']);
      final dife = advice.suggestions.first;
      expect(dife.correlation, lessThan(0.5));
      expect(dife.reasons.join(), contains('Oscila diferente'));
      expect(advice.suggestions.last.correlation, greaterThan(0.5));
    });

    test('sem ações: sugere as mais bem avaliadas e explica o ETF', () {
      final advice = adviseStocks(
        ideas: [
          _idea('AAAA3', graham: 20, score: 1, seed: 3),
          _idea('BBBB3', graham: 20, score: 2, seed: 4),
        ],
        heldValues: const {},
      );
      expect(advice.held, isEmpty);
      expect(advice.suggestions.first.idea.quote.symbol, 'BBBB3');
      expect(advice.suggestions.first.correlation, isNull);
      expect(advice.summary, contains('BOVA11'));
    });
  });
}
