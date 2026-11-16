import 'package:financas_app/models/market/contribution.dart';
import 'package:financas_app/models/market/portfolio_engine.dart';
import 'package:financas_app/models/tx.dart';
import 'package:financas_app/models/user_settings.dart';
import 'package:financas_app/widgets/invest/contribution_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Renda 5.000, Guardar 20% = 1.000 por mês; reserva de 6 meses.
UserSettings settings({double reserve = 0}) => UserSettings(
      monthlyIncome: 5000,
      reserveSaved: reserve,
      emergencyMonths: 6,
    );

Tx expense(String category, double amount, DateTime date) => Tx(
      type: TxType.expense,
      amount: amount,
      category: category,
      description: '',
      date: date,
    );

const targets = {
  AssetClass.fixedIncome: 0.40,
  AssetClass.brStocks: 0.30,
  AssetClass.global: 0.30,
};

void main() {
  group('reserva', () {
    test('média dos gastos essenciais dos meses fechados', () {
      final txs = [
        expense('Moradia', 1500, DateTime(2026, 8, 5)),
        expense('Alimentação', 500, DateTime(2026, 8, 9)),
        expense('Lazer', 300, DateTime(2026, 8, 12)), // Desejos: fora
        expense('Moradia', 1500, DateTime(2026, 9, 5)),
        expense('Moradia', 1500, DateTime(2026, 10, 5)),
        expense('Saúde', 200, DateTime(2026, 10, 7)),
      ];
      // (2.000 + 1.500 + 1.700) / 3 meses.
      expect(essentialMonthlyAverage(txs, settings()), closeTo(5200 / 3, 1e-9));
    });

    test('meta: média > gastos do mês > 50% da renda', () {
      expect(reserveStatus(settings(), essentialAverage: 2000).target, 12000);
      expect(reserveStatus(settings(), currentMonthNeeds: 800).target, 4800);
      expect(reserveStatus(settings()).target, 15000);
      final s = reserveStatus(settings(reserve: 12000), essentialAverage: 2000);
      expect(s.complete, isTrue);
      expect(s.missing, 0);
    });
  });

  group('próximo salário', () {
    // Renda 5.000, Guardar 20% = R$ 1.000; reserva-alvo 12.000.
    SalaryPlan plan(double saved,
            {double? expenses, Map<AssetClass, double> current = const {}}) =>
        planNextSalary(
          settings: settings(reserve: saved),
          reserve:
              reserveStatus(settings(reserve: saved), essentialAverage: 2000),
          recentAverageExpenses: expenses,
          current: current,
          targetWeights: targets,
        );

    test('sem reserva: 80% para ela, 20% já vai para investimentos', () {
      final p = plan(0);
      expect(p.focus, SalaryFocus.buildReserve);
      expect(p.toReserve, closeTo(800, 1e-9));
      expect(p.toInvest, closeTo(200, 1e-9));
      expect(p.byClass.values.reduce((a, b) => a + b), closeTo(200, 1e-6));
      expect(p.share(p.toReserve), closeTo(0.16, 1e-9)); // 16% do salário
      expect(p.monthsToReserve, 15); // 12.000 / 800
    });

    test('a parte da reserva cai conforme ela enche', () {
      expect(plan(3000).toReserve, closeTo(700, 1e-9)); // 25%
      expect(plan(6000).toReserve, closeTo(600, 1e-9)); // 50%
      expect(plan(9000).toReserve, closeTo(500, 1e-9)); // 75%
    });

    test('quando falta pouco: completa a reserva e investe o resto', () {
      final p = plan(11700);
      expect(p.toReserve, closeTo(300, 1e-9));
      expect(p.toInvest, closeTo(700, 1e-9));
    });

    test('reserva completa: tudo para os investimentos', () {
      final p = plan(12000);
      expect(p.focus, SalaryFocus.invest);
      expect(p.toReserve, 0);
      expect(p.toInvest, closeTo(1000, 1e-9));
    });

    test('compara a meta com o que sobrou de verdade', () {
      expect(plan(0, expenses: 4600).goalAboveReality, isTrue); // sobrou 400
      expect(plan(0, expenses: 3500).roomForMore, isTrue); // sobrou 1.500
      final ok = plan(0, expenses: 4000);
      expect(ok.goalAboveReality || ok.roomForMore, isFalse);
      expect(plan(0).recentSurplus, isNull);
    });

    test('sem renda: pede para definir', () {
      final p = planNextSalary(
        settings: const UserSettings(),
        reserve: reserveStatus(const UserSettings()),
        recentAverageExpenses: null,
        current: const {},
        targetWeights: targets,
      );
      expect(p.focus, SalaryFocus.defineIncome);
    });

    test('média de gastos considera só meses com lançamento', () {
      expect(averageMonthlyExpenses(const []), isNull);
      expect(
        averageMonthlyExpenses([
          expense('Moradia', 1000, DateTime(2026, 9, 1)),
          expense('Lazer', 500, DateTime(2026, 9, 2)),
          expense('Moradia', 1000, DateTime(2026, 10, 1)),
        ]),
        1250,
      );
    });
  });

  group('rebalanceamento só com compras', () {
    test('a classe mais abaixo do alvo recebe tudo', () {
      // Total depois: 10.000. Alvos: RF 4.000, Ações 3.000, Exterior 3.000.
      final split = splitByDeficit(
        {
          AssetClass.fixedIncome: 4000,
          AssetClass.brStocks: 3000,
          AssetClass.global: 2000,
        },
        targets,
        1000,
      );
      expect(split, {AssetClass.global: 1000});
    });

    test('falta maior que o aporte: proporcional à falta', () {
      final split = splitByDeficit(
        {AssetClass.fixedIncome: 8000},
        targets,
        1000,
      );
      // Total 9.000: faltam 2.700 em Ações e 2.700 no Exterior.
      expect(split[AssetClass.brStocks], closeTo(500, 1e-9));
      expect(split[AssetClass.global], closeTo(500, 1e-9));
      expect(split.containsKey(AssetClass.fixedIncome), isFalse);
    });

    test('carteira vazia: segue os pesos', () {
      final split = splitByDeficit(const {}, targets, 1000);
      expect(split[AssetClass.fixedIncome], closeTo(400, 1e-9));
      expect(split[AssetClass.brStocks], closeTo(300, 1e-9));
    });

    test('classe fora do alvo não recebe e não é vendida', () {
      final split = splitByDeficit({AssetClass.bitcoin: 5000}, targets, 1000);
      expect(split.containsKey(AssetClass.bitcoin), isFalse);
      expect(split.values.reduce((a, b) => a + b), closeTo(1000, 1e-9));
    });
  });

  test('valores pequenos vão para a classe que recebe mais', () {
    final out = mergeSmallOrders({
      AssetClass.smallCaps: 288,
      AssetClass.global: 274,
      AssetClass.bitcoin: 29,
      AssetClass.fixedIncome: 9,
    });
    expect(out, {
      AssetClass.smallCaps: 297,
      AssetClass.global: 274,
      AssetClass.bitcoin: 29,
    });
  });

  test('classe pelo ticker', () {
    expect(guessAssetClass('petr4'), AssetClass.brStocks);
    expect(guessAssetClass('BOVA11'), AssetClass.brStocks);
    expect(guessAssetClass('IVVB11'), AssetClass.global);
    expect(guessAssetClass('HGLG11'), AssetClass.reits);
    expect(guessAssetClass('TAEE11'), AssetClass.brStocks); // unit
    expect(guessAssetClass('QBTC11'), AssetClass.bitcoin);
  });

  test('valor da posição: cotação × quantidade, senão valor informado', () {
    const acao =
        Holding(ticker: 'PETR4', assetClass: AssetClass.brStocks, quantity: 10);
    expect(acao.value(45.3), closeTo(453, 1e-9));
    expect(acao.value(null), 0);
    const rf = Holding(
        ticker: '', assetClass: AssetClass.fixedIncome, manualValue: 2500);
    expect(rf.value(null), 2500);
    final back = Holding.fromMap(acao.toMap());
    expect((back.ticker, back.quantity, back.assetClass),
        ('PETR4', 10.0, AssetClass.brStocks));
  });

  testWidgets('foco agora mostra % do salário para reserva e bolsa',
      (tester) async {
    final plan = planNextSalary(
      settings: settings(),
      reserve: reserveStatus(settings(), essentialAverage: 2000),
      recentAverageExpenses: 4600,
      current: const {AssetClass.brStocks: 300},
      targetWeights: const {
        AssetClass.brStocks: 0.5,
        AssetClass.global: 0.5,
      },
    );
    var updated = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: FocusCard(
            plan: plan,
            priceOf: (t) => t == 'IVVB11' ? 50.0 : null,
            ownedByClass: const {
              AssetClass.brStocks: ['PETR4'],
            },
            onUpdateReserve: () => updated = true,
          ),
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
    expect(find.text('Foco agora: montar sua reserva de emergência'),
        findsOneWidget);
    expect(find.text('Gastos do mês'), findsOneWidget);
    expect(find.text('80%'), findsOneWidget); // gastos
    expect(find.text('16%'), findsOneWidget); // reserva
    expect(find.text('Exterior'), findsOneWidget);
    // Exterior está mais abaixo do alvo: recebe os R$ 200 (4% do salário).
    expect(find.text('4,0%'), findsOneWidget);
    expect(find.textContaining('IVVB11: 4 cotas'), findsOneWidget);
    expect(find.textContaining('menos que os'), findsOneWidget);
    await tester.tap(find.text('Já guardei: atualizar reserva'));
    expect(updated, isTrue);
  });

  testWidgets('adicionar investimento pelo diálogo', (tester) async {
    List<Holding>? saved;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: HoldingsCard(
            holdings: const [
              Holding(
                  ticker: 'PETR4',
                  assetClass: AssetClass.brStocks,
                  quantity: 10),
            ],
            priceOf: (t) => t == 'PETR4' ? 45.3 : null,
            targetWeights: const {AssetClass.brStocks: 1.0},
            onChanged: (h) async => saved = h,
          ),
        ),
      ),
    ));
    expect(find.textContaining(RegExp(r'10 × R\$\s45,30')), findsOneWidget);

    await tester.tap(find.text('Adicionar investimento'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('holding-ticker')), 'hglg11');
    await tester.enterText(find.byKey(const Key('holding-quantity')), '3');
    await tester.pumpAndSettle();
    expect(find.text('Fundos imobiliários'), findsOneWidget); // palpite
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(saved!.last.ticker, 'HGLG11');
    expect(saved!.last.assetClass, AssetClass.reits);
    expect(saved!.last.quantity, 3);

    // Mesmo ticker soma as cotas.
    await tester.tap(find.text('Adicionar investimento'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('holding-ticker')), 'PETR4');
    await tester.enterText(find.byKey(const Key('holding-quantity')), '5');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(saved!.single.quantity, 15);
  });
}
