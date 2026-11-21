import 'package:financas_app/main.dart';
import 'package:financas_app/pages/dev_review_page.dart';
import 'package:financas_app/services/notification_samples_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';

NotificationSample sample(String id, String title, String text,
        {String? review, String? deviceKind, int count = 1}) =>
    NotificationSample(
      id: id,
      package: 'com.nu.production',
      bank: 'Nubank',
      title: title,
      text: text,
      deviceKind: deviceKind,
      count: count,
      lastSeen: DateTime(2026, 11, 18, 12, 47),
      review: review,
    );

void main() {
  setUpAll(() => initializeDateFormatting('pt_BR'));

  testWidgets('mostra o texto, a leitura atual e grava a revisão',
      (tester) async {
    tester.view.physicalSize = const Size(412 * 3, 1600 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final reviews = <String, (String?, String?)>{};
    await tester.pumpWidget(FinancasApp(
      home: DevReviewPage(
        avatar: const CircleAvatar(radius: 17),
        samples: Stream.value([
          sample('a', 'Compra no crédito aprovada',
              'Compra de R\$ 99,99 APROVADA em CASASBAHIACOM para o cartão com final 0000.',
              count: 12, deviceKind: 'unknown'),
          sample('b', 'Aviso', 'Aconteceu algo com R\$ 99,99 na sua conta'),
          sample('c', 'Ok', 'Pix enviado: R\$ 99,99 para FULANO', review: 'ok'),
        ]),
        onReview: (id, review, {note}) async => reviews[id] = (review, note),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Para revisar (2)'), findsOneWidget);
    expect(find.text('12x'), findsOneWidget);
    expect(find.textContaining('Compra no crédito • R\$'), findsOneWidget);
    // O celular do usuário (versão antiga) não entendia: aparece a diferença.
    expect(find.textContaining('No celular do usuário'), findsOneWidget);
    // Na leitura atual do item b e na leitura antiga do item a.
    expect(find.textContaining('Não entendi'), findsNWidgets(2));
    // A já revisada como certa não aparece em "Para revisar".
    expect(find.textContaining('FULANO', findRichText: true), findsNothing);

    await tester.tap(find.text('Certo').first);
    await tester.pumpAndSettle();
    expect(reviews['a'], ('ok', null));

    await tester.tap(find.text('Errado').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'é propaganda');
    await tester.tap(find.text('Marcar como errado'));
    await tester.pumpAndSettle();
    expect(reviews['b'], ('wrong', 'é propaganda'));
  });

  test('regras liberam a leitura só para o UID do desenvolvedor', () {
    final rules = samplesRules('abc123');
    expect(rules, contains("request.auth.uid == 'abc123'"));
    expect(rules, contains('allow read, delete: if isDev();'));
    // Quem não é o dev só soma 1 na contagem.
    expect(rules,
        contains('request.resource.data.count == resource.data.count + 1'));
  });

  test('só a conta do desenvolvedor vê a área', () {
    expect(developerEmailHashes, hasLength(1));
    // O e-mail é comparado sem espaços e sem diferença de maiúsculas.
    expect(emailHash(' Dev@Exemplo.com '), emailHash('dev@exemplo.com'));
    expect(developerEmailHashes.contains(emailHash('outra@exemplo.com')),
        isFalse);
  });
}
