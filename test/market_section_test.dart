import 'package:financas_app/models/market/market_data.dart';
import 'package:financas_app/widgets/invest/market_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'portfolio_test.dart' show profile, synthetic, syntheticMarket;

void main() {
  setUpAll(() => initializeDateFormatting('pt_BR'));

  testWidgets('seção de mercado cabe num celular e mostra os cartões',
      (tester) async {
    tester.view.physicalSize = const Size(400, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final base = syntheticMarket(
      bitcoin: BitcoinSnapshot(
        priceUsd: 64000,
        marketCapUsd: 1.28e12,
        activeAddresses: 640000,
        metcalfeRatio: 1.06,
        stockToFlow: 123,
        s2fModelPriceUsd: 865000,
        fetchedAt: DateTime(2026, 11, 15, 21, 30),
      ),
    );
    final data = MarketData(
      macro: MacroSnapshot(
        selic: 13.75,
        ipca12m: 4.63,
        ipcaLongTerm: 4.0,
        usdBrl: 5.67,
        usTreasury10y: 5.13,
        ibovespa: 172457.77,
        ibovespaChange: 0.66,
        fetchedAt: DateTime(2026, 11, 15, 21, 30),
      ),
      etfs: base.etfs,
      bitcoin: base.bitcoin,
      stocks: [
        for (final (s, p, d, c, seed) in [
          ('AAAA3', 10.0, 1.2, 5e9, 11),
          ('BBBB4', 40.0, 2.0, 80e9, 12),
          ('CCCC3', 25.0, 0.0, 20e9, 13),
          ('DDDD11', 30.0, 2.5, 15e9, 14),
          ('EEEE3', 60.0, 3.0, 200e9, 15),
          ('FFFF4', 15.0, 0.9, 9e9, 16),
        ])
          StockQuote(
            symbol: s,
            price: p,
            dividends12m: d,
            marketCap: c,
            history: synthetic(s, 0.01, 1, 0.03, seed: seed),
          ),
      ],
      warnings: const ['Cota diária da Alpha Vantage esgotada.'],
    );

    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: MarketSection(
              profile: profile({}),
              loader: () async => data,
              showContribution: false),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    for (final title in [
      'Mercado hoje',
      'Carteira-alvo do seu perfil',
      'Fronteira eficiente',
      'Bitcoin: rede e escassez',
      'Ações em destaque',
      'Como a carteira foi calculada',
    ]) {
      expect(find.text(title), findsOneWidget, reason: title);
    }
    expect(find.text('Renda fixa pós-fixada'), findsWidgets);
    expect(find.text('AAAA3'), findsOneWidget);
    expect(find.textContaining('Cota diária'), findsOneWidget);

    await tester.tap(find.text('Como a carteira foi calculada'));
    await tester.pumpAndSettle();
    expect(find.text('Harry Markowitz (1952)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
