import 'package:financas_app/models/tx.dart';
import 'package:financas_app/models/user_settings.dart';
import 'package:financas_app/widgets/expense_type_dialog.dart';
import 'package:financas_app/widgets/goals_card.dart';
import 'package:flutter/material.dart';
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
      expenseTypes: [ExpenseType(name: 'Pets', color: 0xFF7C3AED)],
    );

    final restored = UserSettings.fromMap(original.toMap());

    expect(restored.monthlyIncome, 4000);
    expect(restored.effectiveBudgets.map((b) => b.name),
        ['Essenciais', 'Pets', 'Desejos', 'Guardar']);
    expect(restored.effectiveBudgets[1].percent, 10);
    expect(restored.expenseTypes.single.color, 0xFF7C3AED);
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
    await tester.tap(find.text('Adicionar categoria'));
    await tester.pumpAndSettle();

    expect(find.text('Pets'), findsOneWidget);
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    final pets = saved!.effectiveBudgets.firstWhere((b) => b.name == 'Pets');
    expect(pets.percent, 8);
    expect(pets.kind, BudgetKind.custom);
    expect(saved!.monthlyIncome, 3000);
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
    await tester.tap(find.byType(InkWell).at(2));
    await tester.pump();
    await tester.tap(find.text('Criar'));
    await tester.pumpAndSettle();

    expect(created?.name, 'Pets');
    expect(created?.color, expenseTypePalette[2]);
  });
}
