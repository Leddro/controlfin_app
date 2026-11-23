import 'dart:async';

import 'package:financas_app/main.dart';
import 'package:financas_app/models/investor_profile.dart';
import 'package:financas_app/models/savings_goal.dart';
import 'package:financas_app/models/tx.dart' show parseMoney;
import 'package:financas_app/pages/goals_page.dart';
import 'package:financas_app/pages/investments_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';

import 'investor_profile_test.dart' show profileWith;

final now = DateTime(2026, 11, 23);

SavingsGoal goal(
  String id, {
  String name = 'Viagem',
  double target = 6000,
  DateTime? deadline,
  List<double> deposits = const [],
}) =>
    SavingsGoal(
      id: id,
      name: name,
      icon: 'travel',
      color: 0xFF38BDF8,
      target: target,
      deadline: deadline,
      deposits: [
        for (final d in deposits)
          GoalDeposit(amount: d, date: DateTime(2026, 11, 1)),
      ],
      createdAt: DateTime(2026, 11, 1),
    );

const avatar = CircleAvatar(radius: 17);

void phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(412 * 3, 1800 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void main() {
  setUpAll(() => initializeDateFormatting('pt_BR'));

  group('modelo', () {
    test('progresso e quanto guardar por mês até o prazo', () {
      // Nov/2026 a abr/2027 = 6 meses; faltam 4.800.
      final g = goal('a', deadline: DateTime(2027, 4), deposits: [1500, -300]);
      expect(g.saved, 1200);
      expect(g.remaining, 4800);
      expect(g.progress, closeTo(0.2, 1e-9));
      expect(g.monthsLeft(now), 6);
      expect(g.monthlyNeeded(now), closeTo(800, 1e-9));
      expect(goal('b').monthlyNeeded(now), isNull, reason: 'sem prazo');
      expect(goal('c', deadline: DateTime(2026, 9)).monthsLeft(now), 0);
      expect(goal('d', deposits: [7000]).done, isTrue);
      expect(goal('d', deposits: [7000]).remaining, 0);
    });

    test('ida e volta pelo Firestore', () {
      final g = goal('a', deadline: DateTime(2027, 4), deposits: [100]);
      final back = SavingsGoal.fromMap(g.toMap())!;
      expect(back.name, 'Viagem');
      expect(back.deadline, DateTime(2027, 4));
      expect(back.saved, 100);
      expect(SavingsGoal.fromMap({'name': 'x'}), isNull);
    });

    test('valores no formato brasileiro', () {
      expect(parseMoney('10.000'), 10000);
      expect(parseMoney('1.234.567'), 1234567);
      expect(parseMoney('10.000,50'), 10000.5);
      expect(parseMoney('10.5'), 10.5);
      expect(parseMoney(r'R$ 25,90'), 25.9);
    });

    test('ordem e sugestões que faltam', () {
      final sorted = sortGoals([
        goal('sem-prazo'),
        goal('batida', deposits: [6000]),
        goal('longe', deadline: DateTime(2028)),
        goal('perto', deadline: DateTime(2027)),
      ]);
      expect([for (final g in sorted) g.id],
          ['perto', 'longe', 'sem-prazo', 'batida']);
      final left = unusedSuggestions([goal('a', name: ' viagem ')]);
      expect(left.any((s) => s.name == 'Viagem'), isFalse);
      expect(left.any((s) => s.name == 'Reforma'), isTrue);
    });
  });

  testWidgets('cria meta pela sugestão, guarda e vê no detalhe',
      (tester) async {
    phone(tester);
    final store = StreamController<List<SavingsGoal>>();
    var saved = <SavingsGoal>[];
    Future<void> onSave(List<SavingsGoal> g) async {
      saved = g;
      store.add(g);
    }

    await tester.pumpWidget(FinancasApp(
      home: GoalsPage(
          goals: store.stream, onSave: onSave, now: () => now, avatar: avatar),
    ));
    store.add(const []);
    await tester.pumpAndSettle();
    expect(find.text('O que você quer conquistar?'), findsOneWidget);

    // Sugestão preenche o nome; o usuário pode trocar.
    await tester.tap(find.byKey(const Key('suggest-goal-Reforma')));
    await tester.pumpAndSettle();
    expect(find.text('Nova meta'), findsWidgets);
    await tester.enterText(
        find.byKey(const Key('goal-name')), 'Reforma da cozinha');
    await tester.enterText(find.byKey(const Key('goal-target')), '10.000');
    await tester.enterText(find.byKey(const Key('goal-already')), '1.000');
    await tester.tap(find.byKey(const Key('goal-save')));
    await tester.pumpAndSettle();

    expect(saved, hasLength(1));
    final g = saved.single;
    expect(g.name, 'Reforma da cozinha');
    expect(g.icon, 'renovation');
    expect(g.target, 10000);
    expect(g.saved, 1000);
    expect(find.text('Reforma da cozinha'), findsOneWidget);
    expect(find.textContaining('10%'), findsOneWidget);
    // A sugestão usada sai da lista; as outras continuam.
    expect(find.byKey(const Key('suggest-goal-Reforma')), findsNothing);
    expect(find.byKey(const Key('suggest-goal-Viagem')), findsOneWidget);

    // Guardar pelo botão do cartão.
    await tester.tap(find.byKey(Key('goal-deposit-${g.id}')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('deposit-amount')), '500');
    await tester.tap(find.byKey(const Key('deposit-save')));
    await tester.pumpAndSettle();
    expect(saved.single.saved, 1500);

    // Detalhe: histórico, retirada e edição.
    await tester.tap(find.text('Reforma da cozinha'));
    await tester.pumpAndSettle();
    expect(find.text('Histórico'), findsOneWidget);
    expect(find.textContaining('+ R\$'), findsNWidgets(2));

    await tester.tap(find.byKey(const Key('goal-detail-deposit')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retirar'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('deposit-amount')), '5.000');
    await tester.tap(find.byKey(const Key('deposit-save')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Só há'), findsOneWidget,
        reason: 'não retira mais do que tem');
    await tester.enterText(find.byKey(const Key('deposit-amount')), '200');
    await tester.tap(find.byKey(const Key('deposit-save')));
    await tester.pumpAndSettle();
    expect(saved.single.saved, 1300);

    await tester.tap(find.byKey(const Key('goal-edit')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('goal-target')), '12.000');
    await tester.tap(find.byKey(const Key('goal-save')));
    await tester.pumpAndSettle();
    expect(saved.single.target, 12000);
    expect(saved.single.saved, 1300, reason: 'editar não perde o histórico');

    await tester.tap(find.byKey(const Key('goal-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('goal-delete-confirm')));
    await tester.pumpAndSettle();
    expect(saved, isEmpty);
    expect(find.text('O que você quer conquistar?'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await store.close();
  });

  testWidgets('meta criada do zero exige nome e valor', (tester) async {
    phone(tester);
    var saved = <SavingsGoal>[];
    await tester.pumpWidget(FinancasApp(
      home: GoalsPage(
        goals: Stream.value(const []),
        onSave: (g) async => saved = g,
        now: () => now,
        avatar: avatar,
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('goal-new')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('goal-save')));
    await tester.pumpAndSettle();
    expect(find.text('Dê um nome para a meta.'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('goal-name')), 'Bicicleta');
    await tester.tap(find.byKey(const Key('goal-save')));
    await tester.pumpAndSettle();
    expect(find.text('Informe quanto a meta custa.'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('goal-target')), '2.500');
    await tester.tap(find.byKey(const Key('goal-icon-game')));
    await tester.tap(find.byKey(const Key('goal-save')));
    await tester.pumpAndSettle();
    expect(saved.single.name, 'Bicicleta');
    expect(saved.single.icon, 'game');
    expect(saved.single.deposits, isEmpty);
  });

  testWidgets('investimentos mostra a faixa do perfil e abre o perfil',
      (tester) async {
    phone(tester);
    final profile = profileWith({});
    await tester.pumpWidget(FinancasApp(
      home: InvestmentsPage(
        profile: Stream.value(profile),
        body: (_) => const Text('mercado'),
        avatar: avatar,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('profile-strip')), findsOneWidget);
    expect(find.text(profile.type.label), findsOneWidget);
    expect(find.text('mercado'), findsOneWidget);
  });
}
