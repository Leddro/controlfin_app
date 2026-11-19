import 'package:financas_app/models/market/contribution.dart';
import 'package:financas_app/models/market/market_data.dart';
import 'package:financas_app/widgets/invest/market_section.dart';
import 'package:material_ui/material_ui.dart';
import 'package:financas_app/models/market/portfolio_engine.dart';
import 'package:financas_app/services/market/market_repository.dart';
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
              planner: (p, d) async => PortfolioEngine.build(p, d),
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
      'Ações para a sua carteira',
      'Como a carteira foi calculada',
    ]) {
      expect(find.text(title), findsOneWidget, reason: title);
    }
    expect(find.text('Renda fixa pós-fixada'), findsWidgets);
    // Só Gordon e Selic alta: nenhuma passa, e a tela diz isso.
    expect(find.text('Mais bem avaliadas'), findsOneWidget);
    expect(find.textContaining('Nenhuma empresa do ranking'), findsOneWidget);
    expect(find.textContaining('Ranking completo (6 ações)'), findsOneWidget);
    expect(find.textContaining('Cota diária'), findsOneWidget);

    await tester.tap(find.text('Como a carteira foi calculada'));
    await tester.pumpAndSettle();
    expect(find.text('Harry Markowitz (1952)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('leitura bloqueada mostra o motivo, não a falta da Selic',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        body: SingleChildScrollView(
          child: MarketSection(
              profile: profile({}),
              loader: () async => const MarketData(
                  warnings: [MarketRepository.permissionDeniedWarning]),
              planner: (p, d) async => PortfolioEngine.build(p, d),
              showContribution: false),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('Sem permissão para ler'), findsWidgets);
    expect(find.textContaining('faltam a Selic'), findsNothing);
  });

  testWidgets('sem a Selic, diz exatamente o que falta', (tester) async {
    final base = syntheticMarket();
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        body: SingleChildScrollView(
          child: MarketSection(
              profile: profile({}),
              loader: () async => MarketData(etfs: base.etfs),
              planner: (p, d) async => PortfolioEngine.build(p, d),
              showContribution: false),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('falta a Selic.'), findsOneWidget);
  });

  testWidgets('avalia as ações que o usuário tem e busca as que faltam',
      (tester) async {
    tester.view.physicalSize = const Size(400, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    StockQuote q(String s, double price, double ni, double eq, int seed) =>
        StockQuote(
          symbol: s,
          price: price,
          dividends12m: price * 0.05,
          marketCap: price * 1e9,
          netIncome: ni,
          equity: eq,
          history: synthetic(s, 0.01, 1, 0.03, seed: seed),
        );
    final base = syntheticMarket();
    final data = MarketData(
      macro: base.macro,
      etfs: base.etfs,
      stocks: [
        q('BARA3', 10, 3e9, 20e9, 11), // Graham ≈ 36,7: bem barata
        q('CARA4', 40, 1e9, 4e9, 12), // Graham ≈ 9,5: cara
        q('OUTR3', 20, 4e9, 30e9, 13),
        q('MAIS3', 15, 2e9, 18e9, 14),
      ],
      quotes: const {'BARA3': 10, 'CARA4': 40},
    );
    final fetched = <String>[];

    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: MarketSection(
            profile: profile({}),
            loader: () async => data,
            planner: (p, d) async => PortfolioEngine.build(p, d),
            showContribution: false,
            holdings: Stream.value(const [
              Holding(
                  ticker: 'BARA3',
                  assetClass: AssetClass.brStocks,
                  quantity: 100),
              Holding(
                  ticker: 'CARA4',
                  assetClass: AssetClass.brStocks,
                  quantity: 10),
              // Fora do robô: buscada na hora.
              Holding(
                  ticker: 'NOVA3',
                  assetClass: AssetClass.brStocks,
                  quantity: 10),
              // ETF e FII não entram na análise de ações.
              Holding(
                  ticker: 'BOVA11',
                  assetClass: AssetClass.brStocks,
                  quantity: 5),
              Holding(
                  ticker: 'HGLG11', assetClass: AssetClass.reits, quantity: 5),
            ]),
            stockFetcher: (t, usd) async {
              fetched.add(t);
              return q(t, 12, 2e9, 15e9, 20);
            },
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(fetched, ['NOVA3']);
    expect(find.text('Suas ações'), findsOneWidget);
    expect(find.text('Para diversificar'), findsOneWidget);
    for (final t in ['BARA3', 'CARA4', 'NOVA3']) {
      expect(find.byKey(Key('held-$t')), findsOneWidget, reason: t);
    }
    expect(find.byKey(const Key('held-BOVA11')), findsNothing);
    expect(find.byKey(const Key('held-HGLG11')), findsNothing);
    expect(
        find.descendant(
            of: find.byKey(const Key('held-CARA4')),
            matching: find.text('Não aumentar')),
        findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const Key('held-NOVA3')),
            matching: find.textContaining('Graham R\$')),
        findsOneWidget);
    // Quem já está na carteira não aparece como sugestão.
    expect(find.byKey(const Key('suggest-BARA3')), findsNothing);
    expect(find.byKey(const Key('suggest-OUTR3')), findsOneWidget);
  });
}
