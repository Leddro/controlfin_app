/// Classificação de tickers da B3. Dart puro: o robô também usa para saber
/// quais tickers das carteiras são ações de empresas.
library;

import 'portfolio_engine.dart';

/// ETFs conhecidos e a classe de cada um.
const etfClasses = {
  'BOVA11': AssetClass.brStocks,
  'BOVV11': AssetClass.brStocks,
  'BOVB11': AssetClass.brStocks,
  'PIBB11': AssetClass.brStocks,
  'SMAL11': AssetClass.smallCaps,
  'SMAC11': AssetClass.smallCaps,
  'DIVO11': AssetClass.dividends,
  'NDIV11': AssetClass.dividends,
  'XFIX11': AssetClass.reits,
  'IVVB11': AssetClass.global,
  'SPXI11': AssetClass.global,
  'NASD11': AssetClass.global,
  'WRLD11': AssetClass.global,
  'QBTC11': AssetClass.bitcoin,
  'BITH11': AssetClass.bitcoin,
  'HASH11': AssetClass.bitcoin,
};

/// Units de empresas que terminam em 11 mas são ações, não FIIs.
const stockUnits = {
  'TAEE11',
  'KLBN11',
  'SAPR11',
  'SANB11',
  'ALUP11',
  'BPAC11',
  'ENGI11',
  'TIET11',
  'SULA11',
  'IGTI11',
  'CPLE11',
  'BRBI11',
  'AESB11',
};

/// Palpite da classe pelo ticker (o usuário pode trocar).
AssetClass guessAssetClass(String ticker) {
  final t = ticker.trim().toUpperCase();
  final etf = etfClasses[t];
  if (etf != null) return etf;
  if (t.endsWith('11') && !stockUnits.contains(t)) return AssetClass.reits;
  return AssetClass.brStocks;
}

final _shareTicker = RegExp(r'^[A-Z]{4}[3-8]$');

/// Ação de uma empresa (ON, PN ou unit conhecida), não ETF, FII nem BDR.
/// É o que dá para avaliar por Graham e Gordon.
bool isCompanyStock(String ticker) {
  final t = ticker.trim().toUpperCase();
  return _shareTicker.hasMatch(t) || stockUnits.contains(t);
}
