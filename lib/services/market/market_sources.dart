/// Chamadas às APIs de mercado. Cada função devolve dados já resumidos,
/// prontos para o cache. Erros viram [MarketSourceException].
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../../models/market/market_data.dart';

/// Chaves das APIs. Só o robô de atualização (tool/update_market.dart)
/// preenche; o app não tem chaves e só lê os dados já gravados no Firestore.
class MarketKeys {
  final String alphaVantage;
  final String brapi;

  const MarketKeys({this.alphaVantage = '', this.brapi = ''});
}

MarketKeys marketKeys = const MarketKeys();

class MarketSourceException implements Exception {
  final String message;

  /// Cota da API esgotada (vale a pena usar dado antigo do cache).
  final bool quota;

  const MarketSourceException(this.message, {this.quota = false});

  @override
  String toString() => message;
}

const _timeout = Duration(seconds: 20);

Future<Object?> _getJson(Uri uri, {Map<String, String>? headers}) async {
  final http.Response res;
  try {
    res = await http.get(uri, headers: headers).timeout(_timeout);
  } catch (_) {
    throw MarketSourceException('Sem resposta de ${uri.host}.');
  }
  if (res.statusCode == 429) {
    throw MarketSourceException('Limite de requisições de ${uri.host}.',
        quota: true);
  }
  if (res.statusCode != 200) {
    throw MarketSourceException('${uri.host} respondeu ${res.statusCode}.');
  }
  return jsonDecode(utf8.decode(res.bodyBytes));
}

String _monthKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}';

// ---------------------------------------------------------------- Banco Central

Future<double> _bcbLast(int series) async {
  final data = await _getJson(Uri.parse(
      'https://api.bcb.gov.br/dados/serie/bcdata.sgs.$series/dados/ultimos/1?formato=json'));
  if (data is! List || data.isEmpty) {
    throw MarketSourceException('Série $series do Banco Central vazia.');
  }
  return double.parse((data.last as Map)['valor'].toString());
}

/// Mediana mais recente do Focus para o IPCA de daqui a 2 anos.
Future<double> _focusIpcaLongTerm() async {
  final target = DateTime.now().year + 2;
  final uri = Uri.parse(
      'https://olinda.bcb.gov.br/olinda/servico/Expectativas/versao/v1/odata/'
      'ExpectativasMercadoAnuais?\$top=1&\$format=json'
      '&\$filter=${Uri.encodeComponent("Indicador eq 'IPCA' and DataReferencia eq '$target'")}'
      '&\$orderby=Data%20desc&\$select=Mediana');
  final data = await _getJson(uri);
  final list = (data as Map)['value'] as List;
  if (list.isEmpty) throw const MarketSourceException('Focus sem IPCA.');
  return ((list.first as Map)['Mediana'] as num).toDouble();
}

// ---------------------------------------------------------------- Alpha Vantage

DateTime? _lastAlphaCall;

/// Respeita o limite de 1 requisição por segundo do plano gratuito.
Future<Map<String, dynamic>> _alpha(Map<String, String> params) async {
  if (marketKeys.alphaVantage.isEmpty) {
    throw const MarketSourceException(
        'Chave da Alpha Vantage não configurada.');
  }
  final last = _lastAlphaCall;
  if (last != null) {
    final wait =
        const Duration(milliseconds: 1300) - DateTime.now().difference(last);
    if (!wait.isNegative) await Future.delayed(wait);
  }
  _lastAlphaCall = DateTime.now();
  final data = await _getJson(Uri.https('www.alphavantage.co', '/query',
      {...params, 'apikey': marketKeys.alphaVantage}));
  final map = Map<String, dynamic>.from(data as Map);
  if (map.containsKey('Information') || map.containsKey('Note')) {
    throw const MarketSourceException('Cota diária da Alpha Vantage esgotada.',
        quota: true);
  }
  if (map.containsKey('Error Message')) {
    throw MarketSourceException('Alpha Vantage: ${map['Error Message']}');
  }
  return map;
}

Future<PriceSeries> alphaMonthlyAdjusted(String symbol) async {
  final map = await _alpha(
      {'function': 'TIME_SERIES_MONTHLY_ADJUSTED', 'symbol': symbol});
  final ts = map['Monthly Adjusted Time Series'] as Map?;
  if (ts == null) throw MarketSourceException('Sem série para $symbol.');
  final monthly = <String, double>{};
  for (final e in ts.entries) {
    final close = double.tryParse(
        ((e.value as Map)['5. adjusted close'] ?? '').toString());
    if (close != null && close > 0) {
      monthly[(e.key as String).substring(0, 7)] = close;
    }
  }
  // Guarda só os últimos 10 anos (o suficiente e cabe bem no cache).
  final keys = monthly.keys.toList()..sort();
  for (final k in keys.take(math.max(0, keys.length - 120))) {
    monthly.remove(k);
  }
  return PriceSeries(symbol, monthly);
}

Future<double> _alphaUsdBrl() async {
  final map = await _alpha({
    'function': 'CURRENCY_EXCHANGE_RATE',
    'from_currency': 'USD',
    'to_currency': 'BRL',
  });
  final rate =
      (map['Realtime Currency Exchange Rate'] as Map?)?['5. Exchange Rate'];
  final v = double.tryParse('$rate');
  if (v == null) throw const MarketSourceException('Dólar indisponível.');
  return v;
}

Future<double> _alphaTreasury10y() async {
  final map = await _alpha({
    'function': 'TREASURY_YIELD',
    'interval': 'monthly',
    'maturity': '10year',
  });
  final data = map['data'] as List?;
  for (final row in data ?? const []) {
    final v = double.tryParse('${(row as Map)['value']}');
    if (v != null) return v;
  }
  throw const MarketSourceException('Juros dos EUA indisponíveis.');
}

// ---------------------------------------------------------------- brapi

Future<Map<String, dynamic>> _brapiQuote(String symbol) async {
  final data = await _getJson(Uri.https('brapi.dev', '/api/quote/$symbol', {
    if (marketKeys.brapi.isNotEmpty) 'token': marketKeys.brapi,
  }));
  final results = (data as Map)['results'] as List?;
  if (results == null || results.isEmpty) {
    throw MarketSourceException('brapi sem dados de $symbol.');
  }
  return Map<String, dynamic>.from(results.first as Map);
}

/// Último preço de um ticker da B3 (brapi grátis).
Future<double?> brapiPrice(String symbol) async {
  try {
    final q = await _brapiQuote(symbol);
    return (q['regularMarketPrice'] as num?)?.toDouble();
  } on MarketSourceException {
    return null;
  }
}

/// Valor de mercado (brapi grátis traz preço e valor de mercado).
Future<double?> brapiMarketCap(String symbol) async {
  try {
    final q = await _brapiQuote(symbol);
    return (q['marketCap'] as num?)?.toDouble();
  } on MarketSourceException {
    return null;
  }
}

// ---------------------------------------------------------------- Macro

/// Selic, IPCA e Focus (obrigatórios); dólar, juros dos EUA e Ibovespa
/// (opcionais: se falharem, a tela segue sem eles).
Future<MacroSnapshot> fetchMacro() async {
  final selic = await _bcbLast(432);
  final ipca12m = await _bcbLast(13522);
  double ipcaLong;
  try {
    ipcaLong = await _focusIpcaLongTerm();
  } on MarketSourceException {
    ipcaLong = ipca12m;
  }
  Future<double?> optional(Future<double> Function() f) async {
    try {
      return await f();
    } on MarketSourceException {
      return null;
    }
  }

  final usd = await optional(_alphaUsdBrl);
  final us10 = await optional(_alphaTreasury10y);
  double? ibov, ibovChange;
  try {
    final q = await _brapiQuote('^BVSP');
    ibov = (q['regularMarketPrice'] as num?)?.toDouble();
    ibovChange = (q['regularMarketChangePercent'] as num?)?.toDouble();
  } on MarketSourceException {
    // Segue sem o Ibovespa.
  }
  return MacroSnapshot(
    selic: selic,
    ipca12m: ipca12m,
    ipcaLongTerm: ipcaLong,
    usdBrl: usd,
    usTreasury10y: us10,
    ibovespa: ibov,
    ibovespaChange: ibovChange,
    fetchedAt: DateTime.now(),
  );
}

// ---------------------------------------------------------------- Bitcoin

/// Rede do Bitcoin (CoinMetrics, plano comunitário) e os sinais de
/// Metcalfe e stock-to-flow.
Future<BitcoinSnapshot> fetchBitcoin() async {
  final start = DateTime.now().subtract(const Duration(days: 4 * 365));
  final data = await _getJson(Uri.https(
      'community-api.coinmetrics.io', '/v4/timeseries/asset-metrics', {
    'assets': 'btc',
    'metrics': 'AdrActCnt,CapMrktCurUSD,SplyCur,PriceUSD',
    'frequency': '1d',
    'start_time': start.toIso8601String().substring(0, 10),
    'page_size': '10000',
  }));
  final rows = ((data as Map)['data'] as List?) ?? const [];
  final points = <BtcDay>[];
  for (final r in rows) {
    final m = r as Map;
    final adr = double.tryParse('${m['AdrActCnt']}');
    final cap = double.tryParse('${m['CapMrktCurUSD']}');
    final supply = double.tryParse('${m['SplyCur']}');
    final price = double.tryParse('${m['PriceUSD']}');
    if (adr == null || cap == null || supply == null || price == null) {
      continue;
    }
    points.add(
        BtcDay(DateTime.parse(m['time'] as String), adr, cap, supply, price));
  }
  if (points.length < 400) {
    throw const MarketSourceException('Histórico do Bitcoin incompleto.');
  }
  return bitcoinFromHistory(points);
}

class BtcDay {
  final DateTime day;
  final double activeAddresses;
  final double marketCapUsd;
  final double supply;
  final double priceUsd;

  const BtcDay(this.day, this.activeAddresses, this.marketCapUsd, this.supply,
      this.priceUsd);
}

/// Metcalfe: valor ∝ n². Calibra k pela mediana de valor/n² no histórico
/// (com n = média de 30 dias de endereços ativos) e compara com hoje.
/// Stock-to-flow: oferta ÷ emissão dos últimos 365 dias; preço do modelo de
/// PlanB (2019): ln(valor de mercado) = 3,3·ln(S2F) + 14,6.
BitcoinSnapshot bitcoinFromHistory(List<BtcDay> days) {
  days.sort((a, b) => a.day.compareTo(b.day));
  final ratios = <double>[];
  double avgAdr(int end) {
    final from = math.max(0, end - 29);
    var s = 0.0;
    for (var i = from; i <= end; i++) {
      s += days[i].activeAddresses;
    }
    return s / (end - from + 1);
  }

  for (var i = 29; i < days.length; i++) {
    final n = avgAdr(i);
    ratios.add(days[i].marketCapUsd / (n * n));
  }
  final sorted = [...ratios]..sort();
  final k = sorted[sorted.length ~/ 2];
  final last = days.last;
  final n = avgAdr(days.length - 1);
  final metcalfe = last.marketCapUsd / (k * n * n);

  final yearAgo = days.lastWhere(
      (d) => !d.day.isAfter(last.day.subtract(const Duration(days: 365))),
      orElse: () => days.first);
  final flow = last.supply - yearAgo.supply;
  final s2f = flow > 0 ? last.supply / flow : 0.0;
  final modelCap = s2f > 0 ? math.exp(3.3 * math.log(s2f) + 14.6) : 0.0;

  return BitcoinSnapshot(
    priceUsd: last.priceUsd,
    marketCapUsd: last.marketCapUsd,
    activeAddresses: n,
    metcalfeRatio: metcalfe,
    stockToFlow: s2f,
    s2fModelPriceUsd: modelCap / last.supply,
    fetchedAt: DateTime.now(),
  );
}

// ---------------------------------------------------------------- Yahoo Finance

/// Ações do ranking: pagadoras de dividendos e empresas grandes da B3.
const stockUniverse = [
  'PETR4',
  'VALE3',
  'ITUB4',
  'BBDC4',
  'BBAS3',
  'ITSA4',
  'TAEE11',
  'EGIE3',
  'CMIG4',
  'SAPR11',
  'BBSE3',
  'ABEV3',
  'WEGE3',
  'VIVT3',
  'KLBN11',
  'CSMG3',
  'CXSE3',
  'B3SA3',
];

/// Preço, proventos de 12 meses e histórico mensal pelo Yahoo Finance
/// (endpoint público não documentado: pode mudar sem aviso e não funciona
/// no navegador, que bloqueia a chamada).
Future<Map> _yahooChart(String ticker, String range,
    {bool dividends = false}) async {
  final data = await _getJson(
    Uri.https('query1.finance.yahoo.com', '/v8/finance/chart/$ticker.SA', {
      'range': range,
      'interval': '1mo',
      if (dividends) 'events': 'div',
    }),
    headers: const {'User-Agent': 'Mozilla/5.0'},
  );
  final result = (((data as Map)['chart'] as Map?)?['result'] as List?);
  if (result == null || result.isEmpty) {
    throw MarketSourceException('Yahoo sem dados de $ticker.');
  }
  return result.first as Map;
}

/// Último preço pelo Yahoo Finance (sem chave; não funciona na web).
Future<double?> yahooPrice(String ticker) async {
  try {
    final r = await _yahooChart(ticker, '5d');
    return ((r['meta'] as Map)['regularMarketPrice'] as num?)?.toDouble();
  } catch (_) {
    return null;
  }
}

Future<StockQuote> yahooStock(String ticker) async {
  // Duas chamadas: com 5 anos o Yahoo agrupa os proventos por mês e a soma
  // dos últimos 12 meses sai errada; com 1 ano cada evento vem certo.
  final recent = await _yahooChart(ticker, '1y', dividends: true);
  final history = await _yahooChart(ticker, '5y');

  final price =
      ((recent['meta'] as Map)['regularMarketPrice'] as num).toDouble();
  final cut = DateTime.now()
          .subtract(const Duration(days: 365))
          .millisecondsSinceEpoch ~/
      1000;
  final divs = ((recent['events'] as Map?)?['dividends'] as Map?) ?? const {};
  var total = 0.0;
  for (final d in divs.values) {
    final m = d as Map;
    if ((m['date'] as num) > cut) total += (m['amount'] as num).toDouble();
  }

  final stamps = (history['timestamp'] as List?) ?? const [];
  final adj = ((((history['indicators'] as Map)['adjclose'] as List?)?.first
          as Map?)?['adjclose'] as List?) ??
      const [];
  final monthly = <String, double>{};
  for (var i = 0; i < stamps.length && i < adj.length; i++) {
    final v = adj[i];
    if (v is num && v > 0) {
      monthly[_monthKey(DateTime.fromMillisecondsSinceEpoch(
          (stamps[i] as num).toInt() * 1000))] = v.toDouble();
    }
  }
  return StockQuote(
    symbol: ticker,
    price: price,
    dividends12m: total,
    history: PriceSeries(ticker, monthly),
  );
}
