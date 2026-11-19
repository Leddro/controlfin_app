import 'package:financas_app/models/market/market_data.dart';
import 'package:financas_app/models/market/portfolio_engine.dart';
import 'package:financas_app/services/market/market_collector.dart';
import 'package:financas_app/services/market/market_sources.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('modo rápido', () {
    test('troca só o Ibovespa e o horário do macro', () {
      final now = DateTime.utc(2026, 11, 19, 16);
      final m = withIbovespa(
          {'selic': 13.75, 'ibovespa': 170000.0, 'usdBrl': 5.3},
          172500,
          1.2,
          now);
      expect(m['selic'], 13.75);
      expect(m['usdBrl'], 5.3);
      expect(m['ibovespa'], 172500);
      expect(m['ibovespaChange'], 1.2);
      expect(m['fetchedAt'], '2026-11-19T16:00:00.000Z');
    });

    test('preço novo mantém o preço justo de Graham', () {
      const before = StockQuote(
        symbol: 'ITUB4',
        price: 40,
        dividends12m: 2,
        marketCap: 440e9,
        netIncome: 48e9,
        equity: 229e9,
        history: PriceSeries('ITUB4', {'2026-10': 39}),
      );
      final after = StockQuote.fromJson(repriceStocks([
        before.toJson(),
      ], {
        'ITUB4': 44,
      }).single);
      expect(after.price, 44);
      expect(after.marketCap, closeTo(484e9, 1));
      final g0 =
          grahamFairPrice(before.earningsPerShare, before.bookValuePerShare)!;
      final g1 =
          grahamFairPrice(after.earningsPerShare, after.bookValuePerShare)!;
      expect(g1, closeTo(g0, 1e-6));
      expect(after.dividends12m, 2);
      expect(after.history.monthly, {'2026-10': 39});
    });

    test('ação sem cotação nova fica como estava; lista vazia falha', () {
      final s = {'symbol': 'XXXX3', 'price': 10.0, 'marketCap': 1e9};
      expect(repriceStocks([s], {'ITUB4': 44}).single, s);
      expect(
          () => repriceStocks([], {}), throwsA(isA<MarketSourceException>()));
    });
  });
}
