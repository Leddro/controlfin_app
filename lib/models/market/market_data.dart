/// Dados de mercado usados na tela de investimentos.
///
/// Cada bloco vem de uma fonte e tem a própria validade no cache
/// (ver MarketRepository). Todos viram JSON para ficar no Firestore.
library;

double? _d(Object? v) => v is num ? v.toDouble() : null;

/// Juros, inflação, câmbio e bolsa do dia.
class MacroSnapshot {
  /// Meta da Selic, % ao ano (Banco Central, série 432).
  final double selic;

  /// IPCA acumulado em 12 meses, % (Banco Central, série 13522).
  final double ipca12m;

  /// Mediana do Focus para o IPCA de longo prazo (2 anos à frente), %.
  final double ipcaLongTerm;

  /// Dólar em reais (Alpha Vantage).
  final double? usdBrl;

  /// Juros de 10 anos dos EUA, % ao ano (Alpha Vantage, TREASURY_YIELD).
  final double? usTreasury10y;

  /// Ibovespa em pontos e variação do dia em % (brapi).
  final double? ibovespa;
  final double? ibovespaChange;

  final DateTime fetchedAt;

  const MacroSnapshot({
    required this.selic,
    required this.ipca12m,
    required this.ipcaLongTerm,
    this.usdBrl,
    this.usTreasury10y,
    this.ibovespa,
    this.ibovespaChange,
    required this.fetchedAt,
  });

  factory MacroSnapshot.fromJson(Map<String, dynamic> j) => MacroSnapshot(
        selic: _d(j['selic'])!,
        ipca12m: _d(j['ipca12m'])!,
        ipcaLongTerm: _d(j['ipcaLongTerm'])!,
        usdBrl: _d(j['usdBrl']),
        usTreasury10y: _d(j['usTreasury10y']),
        ibovespa: _d(j['ibovespa']),
        ibovespaChange: _d(j['ibovespaChange']),
        fetchedAt: DateTime.parse(j['fetchedAt'] as String),
      );

  Map<String, dynamic> toJson() => {
        'selic': selic,
        'ipca12m': ipca12m,
        'ipcaLongTerm': ipcaLongTerm,
        'usdBrl': usdBrl,
        'usTreasury10y': usTreasury10y,
        'ibovespa': ibovespa,
        'ibovespaChange': ibovespaChange,
        'fetchedAt': fetchedAt.toIso8601String(),
      };
}

/// Fechamentos mensais ajustados (com proventos) de um ativo.
/// Chave "aaaa-mm", em ordem crescente.
class PriceSeries {
  final String symbol;
  final Map<String, double> monthly;

  const PriceSeries(this.symbol, this.monthly);

  List<String> get months => monthly.keys.toList()..sort();

  double? get last {
    final m = months;
    return m.isEmpty ? null : monthly[m.last];
  }

  factory PriceSeries.fromJson(Map<String, dynamic> j) => PriceSeries(
        j['symbol'] as String,
        {
          for (final e in (j['monthly'] as Map).entries)
            e.key as String: (e.value as num).toDouble(),
        },
      );

  Map<String, dynamic> toJson() => {'symbol': symbol, 'monthly': monthly};
}

/// Bitcoin: preço, rede e os sinais de Metcalfe e stock-to-flow.
class BitcoinSnapshot {
  final double priceUsd;
  final double marketCapUsd;

  /// Endereços ativos por dia (média de 30 dias).
  final double activeAddresses;

  /// Valor de mercado ÷ valor "justo" de Metcalfe (k·n²) calibrado com o
  /// histórico. Acima de 1: caro frente à rede; abaixo: barato.
  final double metcalfeRatio;

  /// Oferta atual ÷ emissão dos últimos 12 meses.
  final double stockToFlow;

  /// Preço pelo modelo de PlanB (2019): ln(valor) = 3,3·ln(S2F) + 14,6.
  final double s2fModelPriceUsd;

  final DateTime fetchedAt;

  const BitcoinSnapshot({
    required this.priceUsd,
    required this.marketCapUsd,
    required this.activeAddresses,
    required this.metcalfeRatio,
    required this.stockToFlow,
    required this.s2fModelPriceUsd,
    required this.fetchedAt,
  });

  factory BitcoinSnapshot.fromJson(Map<String, dynamic> j) => BitcoinSnapshot(
        priceUsd: _d(j['priceUsd'])!,
        marketCapUsd: _d(j['marketCapUsd'])!,
        activeAddresses: _d(j['activeAddresses'])!,
        metcalfeRatio: _d(j['metcalfeRatio'])!,
        stockToFlow: _d(j['stockToFlow'])!,
        s2fModelPriceUsd: _d(j['s2fModelPriceUsd'])!,
        fetchedAt: DateTime.parse(j['fetchedAt'] as String),
      );

  Map<String, dynamic> toJson() => {
        'priceUsd': priceUsd,
        'marketCapUsd': marketCapUsd,
        'activeAddresses': activeAddresses,
        'metcalfeRatio': metcalfeRatio,
        'stockToFlow': stockToFlow,
        's2fModelPriceUsd': s2fModelPriceUsd,
        'fetchedAt': fetchedAt.toIso8601String(),
      };
}

/// Dados de uma ação para o ranking (Yahoo Finance + brapi).
class StockQuote {
  final String symbol;
  final double price;

  /// Proventos pagos por ação nos últimos 12 meses (dividendos + JCP).
  final double dividends12m;

  /// Valor de mercado em reais (brapi), para o fator tamanho.
  final double? marketCap;

  /// Fechamentos mensais ajustados, para o beta.
  final PriceSeries history;

  const StockQuote({
    required this.symbol,
    required this.price,
    required this.dividends12m,
    this.marketCap,
    required this.history,
  });

  double get dividendYield => price > 0 ? dividends12m / price : 0;

  factory StockQuote.fromJson(Map<String, dynamic> j) => StockQuote(
        symbol: j['symbol'] as String,
        price: _d(j['price'])!,
        dividends12m: _d(j['dividends12m']) ?? 0,
        marketCap: _d(j['marketCap']),
        history: PriceSeries.fromJson(
            Map<String, dynamic>.from(j['history'] as Map)),
      );

  Map<String, dynamic> toJson() => {
        'symbol': symbol,
        'price': price,
        'dividends12m': dividends12m,
        'marketCap': marketCap,
        'history': history.toJson(),
      };
}

/// Tudo o que a tela precisa. Cada parte pode faltar se a fonte falhar.
class MarketData {
  final MacroSnapshot? macro;
  final Map<String, PriceSeries> etfs;
  final BitcoinSnapshot? bitcoin;
  final List<StockQuote> stocks;

  /// Último preço por ticker da B3 (ações, FIIs e ETFs das carteiras).
  final Map<String, double> quotes;

  /// Avisos para mostrar (fonte fora do ar, cota esgotada, dado antigo).
  final List<String> warnings;

  const MarketData({
    this.macro,
    this.etfs = const {},
    this.bitcoin,
    this.stocks = const [],
    this.quotes = const {},
    this.warnings = const [],
  });
}
