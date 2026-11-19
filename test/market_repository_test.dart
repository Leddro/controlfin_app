import 'package:financas_app/models/market/market_data.dart';
import 'package:financas_app/models/market/portfolio_engine.dart';
import 'package:financas_app/services/market/market_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'portfolio_test.dart' show profile, syntheticMarket;

void main() {
  test('lê ETFs, cotações e horário dos documentos do robô', () {
    final base = syntheticMarket();
    final at = DateTime.utc(2026, 11, 19, 13, 52).toLocal();
    final macro = base.macro!.toJson()
      // Formato antigo do robô: horário UTC sem "Z".
      ..['fetchedAt'] = '2026-11-19T13:51:56.529221';
    final data = MarketRepository.fromDocs({
      'macro': (macro, at),
      'etfs': (
        {for (final e in base.etfs.entries) e.key: e.value.toJson()},
        at
      ),
      'quotes': ({'BOVA11': 120.5, 'PETR4': 43.17}, at),
    }, now: at);

    expect(data.etfs.keys, containsAll(base.etfs.keys));
    expect(data.quotes['PETR4'], 43.17);
    expect(data.quotes.containsKey('fetchedAt'), isFalse);
    expect(data.macro!.fetchedAt.isAtSameMomentAs(at), isTrue,
        reason: 'vale o horário da gravação, não o do conteúdo');
    expect(data.warnings, isEmpty);
    expect(PortfolioEngine.build(profile({}), data), isNotNull);
  });

  test('documento com problema some sozinho e avisa dado antigo', () {
    final at = DateTime(2026, 11, 10);
    final data = MarketRepository.fromDocs({
      'etfs': ('quebrado', at),
      'quotes': ({'PETR4': 43.17}, at),
    }, now: DateTime(2026, 11, 19));
    expect(data.etfs, isEmpty);
    expect(data.quotes['PETR4'], 43.17);
    expect(data.warnings.single, contains('9 dias'));
  });

  test('sem documentos: ainda não gerados', () {
    expect(MarketRepository.fromDocs({}).warnings.single,
        contains('ainda não foram gerados'));
    expect(const MarketData().macro, isNull);
  });
}
