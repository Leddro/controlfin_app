/// Coleta os dados de mercado para gravar no Firestore. Roda só no robô
/// diário (tool/update_market.dart, via GitHub Actions), que tem as chaves.
/// Sem Flutter: só Dart puro.
library;

import '../../models/market/market_data.dart';
import '../../models/market/portfolio_engine.dart';
import 'market_sources.dart';

/// Documentos da coleção "market": nome → conteúdo (vira JSON no campo
/// payload). Uma parte que falhar fica de fora (o app usa a versão anterior)
/// e entra em [errors].
class CollectedMarket {
  final Map<String, Object> docs;
  final List<String> errors;

  const CollectedMarket(this.docs, this.errors);
}

Future<CollectedMarket> collectMarket({
  Iterable<String> holdingTickers = const [],
  void Function(String)? log,
}) async {
  final docs = <String, Object>{};
  final errors = <String>[];

  Future<void> step(String name, Future<Object> Function() f) async {
    try {
      docs[name] = await f();
      log?.call('ok: $name');
    } catch (e) {
      errors.add('$name: $e');
      log?.call('falhou: $name ($e)');
    }
  }

  await step('macro', () async => (await fetchMacro()).toJson());
  await step(
      'etfs',
      () async => {
            for (final s in etfSymbols)
              s: (await alphaMonthlyAdjusted(s)).toJson(),
          });
  await step('bitcoin', () async => (await fetchBitcoin()).toJson());
  await step(
      'stocks',
      () async => [
            for (final s in await _stocks()) s.toJson(),
          ]);

  // Preços de tudo que aparece nas carteiras e nas sugestões de compra.
  final tickers = <String>{
    ...holdingTickers.map((t) => t.toUpperCase()),
    ...stockUniverse,
    for (final c in AssetClass.values)
      if (productFor(c) != null) productFor(c)!,
  };
  await step('quotes', () async {
    final quotes = <String, double>{};
    for (final t in tickers) {
      final p = await brapiPrice(t) ?? await yahooPrice(t);
      if (p != null && p > 0) quotes[t] = p;
    }
    if (quotes.isEmpty) {
      throw const MarketSourceException('Nenhuma cotação disponível.');
    }
    return quotes;
  });

  return CollectedMarket(docs, errors);
}

Future<List<StockQuote>> _stocks() async {
  final out = <StockQuote>[];
  for (final t in stockUniverse) {
    try {
      final q = await yahooStock(t);
      final cap = await brapiMarketCap(t);
      out.add(StockQuote(
        symbol: q.symbol,
        price: q.price,
        dividends12m: q.dividends12m,
        marketCap: cap,
        history: q.history,
      ));
    } on MarketSourceException {
      // Pula a ação que falhar; o ranking segue com as outras.
    }
  }
  if (out.length < 5) {
    throw const MarketSourceException(
        'Yahoo Finance não respondeu para as ações.');
  }
  return out;
}
