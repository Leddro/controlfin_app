import 'package:financas_app/main.dart';
import 'package:financas_app/widgets/app_header.dart';
import 'package:financas_app/widgets/app_logo.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const fakeAvatar = CircleAvatar(radius: 17, child: Text('L'));

void main() {
  testWidgets('topo mostra logo, título e foto; foto abre a aba Conta',
      (tester) async {
    int? opened;
    await tester.pumpWidget(FinancasApp(
      home: ShellNavigation(
        go: (i) => opened = i,
        child: const Scaffold(
          appBar: AppHeader(title: 'Investimentos', avatar: fakeAvatar),
        ),
      ),
    ));
    expect(find.byType(AppLogo), findsOneWidget);
    expect(find.text('Investimentos'), findsOneWidget);
    await tester.tap(find.text('L'));
    expect(opened, ShellNavigation.account);
  });

  testWidgets('tela aberta por cima: voltar, logo e foto sem navegação',
      (tester) async {
    await tester.pumpWidget(FinancasApp(
      home: Builder(
        builder: (context) => FilledButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => const Scaffold(
              appBar: AppHeader(title: 'Meus cartões', avatar: fakeAvatar),
            ),
          )),
          child: const Text('abrir'),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    expect(find.byType(BackButton), findsOneWidget);
    expect(find.byType(AppLogo), findsOneWidget);
    expect(find.text('L'), findsOneWidget);
    // Sem o MainShell por baixo, tocar na foto não faz nada (nem quebra).
    await tester.tap(find.text('L'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('título longo encolhe em vez de estourar a tela estreita',
      (tester) async {
    tester.view.physicalSize = const Size(320 * 3, 640 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(FinancasApp(
      home: Scaffold(
        appBar: AppHeader(
          title: 'Perfil de investidor',
          avatar: fakeAvatar,
          actions: [
            IconButton(onPressed: () {}, icon: const Icon(Icons.edit)),
          ],
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
    expect(find.byType(AppLogo), findsOneWidget);
  });
}
