/// Coleta os dados de mercado para gravar no Firestore. Roda só no robô
/// (tool/update_market.dart, via GitHub Actions), que tem as chaves.
/// Sem Flutter: só Dart puro.
///
/// Dois modos:
/// * completo ([collectMarket]): uma vez por dia, depois do fechamento.
/// * rápido ([collectQuick]): durante o pregão, só cotações, Ibovespa e o
///   preço das ações do ranking. Não usa a Alpha Vantage (25 consultas por
///   dia no plano grátis), por isso pode rodar várias vezes.
library;

import '../../models/market/market_data.dart';
import '../../models/market/portfolio_engine.dart';
import '../../models/market/tickers.dart';
import 'market_sources.dart';

/// Documentos da coleção "market": nome → conteúdo (vira JSON no campo
/// payload). Uma parte que falhar fica de fora (o app usa a versão anterior)
/// e entra em [errors].
class CollectedMarket {
  final Map<String, Object> docs;
  final List<String> errors;

  const CollectedMarket(this.docs, this.errors);
}

typedef _Step = Future<void> Function(String name, Future<Object> Function());

_Step _stepper(Map<String, Object> docs, List<String> errors,
        void Function(String)? log) =>
    (name, f) async {
      try {
        docs[name] = await f();
        log?.call('ok: $name');
      } catch (e) {
        errors.add('$name: $e');
        log?.call('falhou: $name ($e)');
      }
    };

/// Tudo que aparece nas carteiras e nas sugestões de compra.
Set<String> _quoteTickers(Iterable<String> holdingTickers) => {
      ...holdingTickers.map((t) => t.toUpperCase()),
      ...stockUniverse,
      for (final c in AssetClass.values)
        if (productFor(c) != null) productFor(c)!,
    };

Future<Map<String, double>> _quotes(Set<String> tickers) async {
  final quotes = <String, double>{};
  for (final t in tickers) {
    final p = await brapiPrice(t) ?? await yahooPrice(t);
    if (p != null && p > 0) quotes[t] = p;
  }
  if (quotes.isEmpty) {
    throw const MarketSourceException('Nenhuma cotação disponível.');
  }
  return quotes;
}

/// [fallbackUsdBrl]: dólar da última coleta, para converter os balanços em
/// dólar (Petrobras, Vale) se o macro de hoje falhar.
Future<CollectedMarket> collectMarket({
  Iterable<String> holdingTickers = const [],
  double? fallbackUsdBrl,
  void Function(String)? log,
}) async {
  final docs = <String, Object>{};
  final errors = <String>[];
  final step = _stepper(docs, errors, log);

  await step('macro', () async => (await fetchMacro()).toJson());
  await step(
      'etfs',
      () async => {
            for (final s in etfSymbols)
              s: (await alphaMonthlyAdjusted(s)).toJson(),
          });
  await step('bitcoin', () async => (await fetchBitcoin()).toJson());
  // Universo do ranking + ações de empresas das carteiras, para avaliar o
  // que cada usuário já tem. O câmbio converte balanços em dólar.
  final usdBrl = (docs['macro'] as Map?)?['usdBrl'] as num?;
  await step(
      'stocks',
      () async => [
            for (final s in await _stocks(
              {
                ...stockUniverse,
                ...holdingTickers
                    .map((t) => t.toUpperCase())
                    .where(isCompanyStock),
              },
              usdBrl?.toDouble() ?? fallbackUsdBrl,
            ))
              s.toJson(),
          ]);
  await step('quotes', () => _quotes(_quoteTickers(holdingTickers)));

  return CollectedMarket(docs, errors);
}

/// Modo rápido. [previousMacro] e [previousStocks] são os documentos já
/// gravados: recebem só o Ibovespa e os preços novos (sem eles, só as
/// cotações são gravadas).
Future<CollectedMarket> collectQuick({
  Iterable<String> holdingTickers = const [],
  Map<String, dynamic>? previousMacro,
  List<dynamic>? previousStocks,
  void Function(String)? log,
}) async {
  final docs = <String, Object>{};
  final errors = <String>[];
  final step = _stepper(docs, errors, log);

  await step('quotes', () => _quotes(_quoteTickers(holdingTickers)));
  final quotes = docs['quotes'] as Map<String, double>?;

  if (previousMacro != null) {
    await step('macro', () async {
      final (ibov, change) = await fetchIbovespa();
      return withIbovespa(previousMacro, ibov, change, DateTime.now());
    });
  }
  if (previousStocks != null && quotes != null) {
    await step('stocks', () async => repriceStocks(previousStocks, quotes));
  }
  return CollectedMarket(docs, errors);
}

/// Macro gravado com o Ibovespa do momento (o resto não muda no dia).
Map<String, dynamic> withIbovespa(Map<String, dynamic> macro, double ibov,
        double? change, DateTime now) =>
    {
      ...macro,
      'ibovespa': ibov,
      'ibovespaChange': change,
      'fetchedAt': now.toUtc().toIso8601String(),
    };

/// Ações do ranking com o preço novo. O valor de mercado sobe e desce junto
/// com o preço: o lucro por ação (lucro × preço ÷ valor de mercado) e o
/// preço justo de Graham ficam iguais, e o desconto passa a usar o preço
/// do momento.
List<Map<String, dynamic>> repriceStocks(
    List<dynamic> stocks, Map<String, double> quotes) {
  if (stocks.isEmpty) {
    throw const MarketSourceException('Sem ações gravadas para atualizar.');
  }
  return [
    for (final raw in stocks)
      () {
        final s = Map<String, dynamic>.from(raw as Map);
        final old = (s['price'] as num?)?.toDouble();
        final now = quotes[s['symbol']];
        if (old == null || old <= 0 || now == null) return s;
        final cap = (s['marketCap'] as num?)?.toDouble();
        return {
          ...s,
          'price': now,
          if (cap != null) 'marketCap': cap * now / old,
        };
      }(),
  ];
}

Future<List<StockQuote>> _stocks(Set<String> tickers, double? usdBrl) async {
  final out = <StockQuote>[];
  for (final t in tickers) {
    try {
      out.add(await fetchStockQuote(t, usdBrl: usdBrl));
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
