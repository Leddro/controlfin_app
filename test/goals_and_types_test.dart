import 'package:financas_app/models/tx.dart';
import 'package:financas_app/models/user_settings.dart';
import 'package:financas_app/widgets/expense_type_dialog.dart';
import 'package:financas_app/widgets/goals_card.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('metas e tipos de gasto sobrevivem ao mapa do Firestore', () {
    const original = UserSettings(
      monthlyIncome: 4000,
      budgets: [
        BudgetCategory(name: 'Essenciais', percent: 40, kind: BudgetKind.needs),
        BudgetCategory(name: 'Pets', percent: 10, kind: BudgetKind.custom),
        BudgetCategory(name: 'Desejos', percent: 30, kind: BudgetKind.wants),
        BudgetCategory(name: 'Guardar', percent: 20, kind: BudgetKind.save),
      ],
      expenseTypes: [
        ExpenseType(name: 'Pets', color: 0xFF7C3AED, goal: 'Essenciais'),
      ],
    );

    final restored = UserSettings.fromMap(original.toMap());

    expect(restored.monthlyIncome, 4000);
    expect(restored.effectiveBudgets.map((b) => b.name),
        ['Essenciais', 'Pets', 'Desejos', 'Guardar']);
    expect(restored.effectiveBudgets[1].percent, 10);
    expect(restored.expenseTypes.single.color, 0xFF7C3AED);
    expect(restored.expenseTypes.single.goal, 'Essenciais');
    expect(
      categoryOf(TxType.expense, 'Pets', extra: restored.expenseTypes).color,
      const Color(0xFF7C3AED),
    );
  });

  testWidgets('Ajustar adiciona uma categoria com porcentagem', (tester) async {
    UserSettings? saved;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              saved = await showGoalsDialog(
                context,
                const UserSettings(monthlyIncome: 3000),
                () async => null,
              );
            },
            child: const Text('abrir'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('goal-new-name')), 'Pets');
    await tester.enterText(find.byKey(const Key('goal-new-percent')), '8');
    await tester.ensureVisible(find.text('Adicionar categoria'));
    await tester.tap(find.text('Adicionar categoria'));
    await tester.pumpAndSettle();

    // Aparece na lista de categorias e como tipo de gasto ligado a ela.
    expect(find.byKey(const Key('type-goal-Pets')), findsOneWidget);
    expect(find.text('Total: 108%'), findsOneWidget);
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    final pets = saved!.effectiveBudgets.firstWhere((b) => b.name == 'Pets');
    expect(pets.percent, 8);
    expect(pets.kind, BudgetKind.custom);
    expect(saved!.monthlyIncome, 3000);

    // A categoria nova cria um tipo de gasto ligado a ela.
    final type = saved!.expenseTypes.single;
    expect(type.name, 'Pets');
    expect(type.goal, 'Pets');
    expect(saved!.budgetOf('Pets').name, 'Pets');
  });

  testWidgets('Ajustar troca a meta de um tipo de gasto existente',
      (tester) async {
    UserSettings? saved;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              saved = await showGoalsDialog(
                context,
                const UserSettings(
                  monthlyIncome: 3000,
                  expenseTypes: [
                    ExpenseType(name: 'Pets', color: 0xFF7C3AED),
                  ],
                ),
                () async => null,
              );
            },
            child: const Text('abrir'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    final dropdown = find.byKey(const Key('type-goal-Pets'));
    await tester.ensureVisible(dropdown);
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Essenciais').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(saved!.expenseTypes.single.goal, 'Essenciais');
    expect(saved!.budgetOf('Pets').kind, BudgetKind.needs);
  });

  testWidgets('remover a categoria nova remove o tipo criado junto',
      (tester) async {
    UserSettings? saved;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              saved = await showGoalsDialog(
                context,
                const UserSettings(monthlyIncome: 3000),
                () async => null,
              );
            },
            child: const Text('abrir'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('goal-new-name')), 'Pets');
    await tester.enterText(find.byKey(const Key('goal-new-percent')), '8');
    await tester.ensureVisible(find.text('Adicionar categoria'));
    await tester.tap(find.text('Adicionar categoria'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Remover'));
    await tester.tap(find.byTooltip('Remover'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(saved!.expenseTypes, isEmpty);
    expect(saved!.effectiveBudgets.map((b) => b.name),
        ['Essenciais', 'Desejos', 'Guardar']);
  });

  testWidgets('tocar numa meta de gasto avisa qual foi; Guardar não',
      (tester) async {
    final tapped = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: GoalsCard(
            settings: const UserSettings(monthlyIncome: 3000),
            txs: const [],
            onEdit: () {},
            onSelectGoal: tapped.add,
            selectedGoal: 'Desejos',
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Essenciais (50%)'));
    await tester.tap(find.text('Desejos (30%)'));
    await tester.tap(find.text('Guardar (20%)'));
    expect(tapped, ['Essenciais', 'Desejos']);
    // A explicação fica escondida no "i".
    expect(find.textContaining('Toque numa meta'), findsNothing);
    await tester.tap(find.byKey(const Key('info-goals')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Toque numa meta para ver os gastos dela.'),
        findsOneWidget);
    expect(find.textContaining('50/30/20'), findsOneWidget);
  });

  test('cada gasto conta na meta certa', () {
    const settings = UserSettings(
      budgets: [
        BudgetCategory(name: 'Essenciais', percent: 50, kind: BudgetKind.needs),
        BudgetCategory(name: 'Viagem', percent: 10, kind: BudgetKind.custom),
        BudgetCategory(name: 'Desejos', percent: 20, kind: BudgetKind.wants),
        BudgetCategory(name: 'Guardar', percent: 20, kind: BudgetKind.save),
      ],
      expenseTypes: [
        ExpenseType(name: 'Pets', color: 0xFF7C3AED, goal: 'Essenciais'),
        ExpenseType(name: 'Hobby', color: 0xFFDB2777),
        ExpenseType(name: 'Passagem', color: 0xFF0891B2, goal: 'Viagem'),
        ExpenseType(name: 'Antigo', color: 0xFF16A34A, goal: 'Removida'),
      ],
    );

    expect(settings.budgetOf('Pets').name, 'Essenciais');
    expect(settings.budgetOf('Hobby').name, 'Desejos');
    expect(settings.budgetOf('Passagem').name, 'Viagem');
    expect(settings.budgetOf('Viagem').name, 'Viagem');
    expect(settings.budgetOf('Antigo').name, 'Desejos');
    expect(settings.budgetOf('Moradia').name, 'Essenciais');
    expect(settings.budgetOf('Lazer').name, 'Desejos');
    expect(settings.budgetOf('Outros').name, 'Desejos');
  });

  testWidgets('novo tipo de gasto guarda nome e cor', (tester) async {
    ExpenseType? created;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              created = await showExpenseTypeDialog(context, ['Moradia']);
            },
            child: const Text('abrir'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('expense-type-name')), 'Pets');
    await tester
        .tap(find.byKey(Key('expense-type-color-${expenseTypePalette[2]}')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('expense-type-goal-Essenciais')));
    await tester.pump();
    await tester.tap(find.text('Criar'));
    await tester.pumpAndSettle();

    expect(created?.name, 'Pets');
    expect(created?.color, expenseTypePalette[2]);
    expect(created?.goal, 'Essenciais');
  });
}
