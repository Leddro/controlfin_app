import 'package:financas_app/models/investor_profile.dart';
import 'package:financas_app/pages/invest_page.dart';
import 'package:financas_app/widgets/investor_quiz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

InvestorProfile profileWith(Map<String, int> changes) {
  // Base: pessoa jovem, prazo longo, renda estável, reserva grande,
  // experiente e que aceita risco em todas as perguntas.
  final answers = <String, int>{
    'goal': 3,
    'horizon': 4,
    'age': 1,
    'income': 0,
    'reserve': 3,
    'dependents': 0,
    'experience': 3,
    'gamble': 1,
    'gambleFollow': 1,
    'drop': 3,
    'range': 3,
    ...changes,
  };
  return InvestorProfile(answers: answers, createdAt: DateTime(2026, 11, 15));
}

void main() {
  group('aversão ao risco (Barsky et al. / Arrow-Pratt)', () {
    test('as quatro combinações das apostas', () {
      expect(profileWith({'gamble': 0, 'gambleFollow': 0}).riskAversion,
          RiskAversionClass.veryHigh);
      expect(profileWith({'gamble': 0, 'gambleFollow': 1}).riskAversion,
          RiskAversionClass.high);
      expect(profileWith({'gamble': 1, 'gambleFollow': 0}).riskAversion,
          RiskAversionClass.moderate);
      expect(profileWith({'gamble': 1, 'gambleFollow': 1}).riskAversion,
          RiskAversionClass.low);
    });
  });

  group('tipo de perfil', () {
    test('disposto e com capacidade: arrojado', () {
      final p = profileWith({});
      expect(p.willingness, closeTo(100, 0.01));
      expect(p.type, InvestorType.aggressive);
    });

    test('sem reserva de emergência fica conservador', () {
      final p = profileWith({'reserve': 0});
      expect(p.type, InvestorType.conservative);
      expect(p.limitingFactor, contains('reserva de emergência'));
    });

    test('objetivo de reserva ou prazo curto fica conservador', () {
      expect(profileWith({'goal': 0}).type, InvestorType.conservative);
      expect(profileWith({'horizon': 0}).type, InvestorType.conservative);
    });

    test('compra em até 3 anos limita a moderado', () {
      final p = profileWith({'goal': 1, 'horizon': 1});
      expect(p.score, greaterThanOrEqualTo(40));
      expect(p.type, InvestorType.moderate);
    });

    test('vale a menor entre disposição e capacidade', () {
      final cauteloso = profileWith({
        'gamble': 0,
        'gambleFollow': 0,
        'drop': 0,
        'range': 0,
      });
      expect(cauteloso.willingness, 0);
      expect(cauteloso.capacity, greaterThan(70));
      expect(cauteloso.type, InvestorType.conservative);
      expect(cauteloso.limitingFactor, contains('confortável'));

      final semFolga = profileWith({
        'horizon': 2,
        'age': 4,
        'income': 2,
        'reserve': 1,
        'dependents': 1,
        'experience': 0,
      });
      expect(semFolga.capacity, lessThan(semFolga.willingness));
      expect(semFolga.score, semFolga.capacity);
      expect(semFolga.limitingFactor, contains('mais cautela'));
    });
  });

  test('perfil sobrevive ao mapa do Firestore', () {
    final original = profileWith({'drop': 2});
    final restored = InvestorProfile.fromMap(original.toMap());
    expect(restored.answers, original.answers);
    expect(restored.createdAt, original.createdAt);
    expect(restored.type, original.type);
    expect(restored.isComplete, isTrue);
  });

  testWidgets('questionário passa pelas 11 perguntas e devolve o perfil',
      (tester) async {
    InvestorProfile? done;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: InvestorQuiz(onDone: (p) => done = p)),
    ));

    Future<void> answer(String id, int option) async {
      final finder = find.byKey(Key('quiz-$id-$option'));
      await tester.ensureVisible(finder);
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    await answer('goal', 2);
    await answer('horizon', 4);
    await answer('age', 2);
    await answer('income', 0);
    await answer('reserve', 2);
    await answer('dependents', 1);
    await answer('experience', 1);

    // Recusar a primeira aposta leva à aposta mais leve (-20%).
    await answer('gamble', 0);
    expect(find.textContaining('um quinto'), findsOneWidget);

    // Voltar e aceitar troca a segunda aposta para -50%.
    await tester.tap(find.byTooltip('Voltar'));
    await tester.pumpAndSettle();
    await answer('gamble', 1);
    expect(find.textContaining('metade da renda'), findsOneWidget);

    await answer('gambleFollow', 0);
    await answer('drop', 2);
    expect(find.text('Pergunta 11 de 11'), findsOneWidget);
    await answer('range', 1);

    expect(done, isNotNull);
    expect(done!.isComplete, isTrue);
    expect(done!.answers['gamble'], 1);
    expect(done!.riskAversion, RiskAversionClass.moderate);
    expect(done!.goal, 2);
  });

  testWidgets('tela do perfil mostra tipo, medidas e referências',
      (tester) async {
    var redo = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: InvestorProfileView(
          profile: profileWith({}),
          onRedo: () => redo = true,
        ),
      ),
    ));

    expect(find.text('Arrojado'), findsOneWidget);
    expect(find.text('Disposição para risco'), findsOneWidget);
    expect(find.text('Capacidade de correr risco'), findsOneWidget);
    expect(find.textContaining('γ < 1'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Base teórica'), 200);
    await tester.tap(find.text('Base teórica'));
    await tester.pumpAndSettle();
    expect(find.text('Daniel Bernoulli (1738)'), findsOneWidget);
    await tester.scrollUntilVisible(
        find.text('Franco Modigliani e Richard Brumberg (1954)'), 200);

    await tester.scrollUntilVisible(find.text('Refazer perfil'), 300);
    await tester.tap(find.text('Refazer perfil'));
    expect(redo, isTrue);
  });
}
