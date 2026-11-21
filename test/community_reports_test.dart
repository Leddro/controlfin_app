import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:financas_app/main.dart';
import 'package:financas_app/pages/community_reports_page.dart';
import 'package:financas_app/pages/reports_admin_page.dart';
import 'package:financas_app/services/community_report_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';

CommunityReport report(
  String id, {
  ReportKind kind = ReportKind.bug,
  ReportStatus status = ReportStatus.received,
  String text = 'O gráfico não abre',
  String? reply,
  DateTime? at,
}) =>
    CommunityReport(
      id: id,
      uid: 'u1',
      name: 'Maria Souza',
      email: 'maria@exemplo.com',
      kind: kind,
      text: text,
      platform: 'android',
      version: '0.1.0',
      createdAt: at ?? DateTime(2026, 11, 19, 10),
      status: status,
      reply: reply,
    );

void phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(412 * 3, 1800 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void main() {
  setUpAll(() => initializeDateFormatting('pt_BR'));

  group('modelo', () {
    test('lê o documento e ordena com os recém-enviados no topo', () {
      final r = CommunityReport.fromMap('x', {
        'uid': 'u1',
        'kind': 'idea',
        'text': 'Modo claro',
        'status': 'review',
        'reply': '  ',
        'createdAt': Timestamp.fromDate(DateTime(2026, 11, 1)),
      });
      expect(r.kind, ReportKind.idea);
      expect(r.status, ReportStatus.inReview);
      expect(r.reply, isNull, reason: 'resposta em branco não conta');

      final sorted = sortReports([
        report('velho', at: DateTime(2026, 11, 1)),
        const CommunityReport(
            id: 'enviando',
            uid: 'u1',
            name: '',
            email: '',
            kind: ReportKind.bug,
            text: 'x'),
        report('novo', at: DateTime(2026, 11, 18)),
      ]);
      expect([for (final r in sorted) r.id], ['enviando', 'novo', 'velho']);
    });

    test('regras: só o próprio usuário cria e lê; só o dev muda', () {
      final rules = reportsRules('DEV');
      expect(rules, contains("request.auth.uid == 'DEV'"));
      expect(rules, contains('request.resource.data.uid == request.auth.uid'));
      // Ninguém manda report em nome de outro e-mail.
      expect(rules,
          contains('request.resource.data.email == request.auth.token.email'));
      expect(rules, contains('resource.data.uid == request.auth.uid'));
      expect(rules, contains('allow update, delete: if isDev();'));
      expect(rules, contains('<= $reportMaxLength'));
    });
  });

  testWidgets('usuário envia e acompanha status e resposta', (tester) async {
    phone(tester);
    final sent = <(ReportKind, String)>[];
    await tester.pumpWidget(FinancasApp(
      home: CommunityReportsPage(
        avatar: const CircleAvatar(radius: 17),
        mine: Stream.value([
          report('a',
              status: ReportStatus.done, reply: 'Corrigido na versão nova!'),
          report('b', kind: ReportKind.idea, text: 'Modo claro'),
        ]),
        onSend: (k, t) async => sent.add((k, t)),
      ),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Resolvido'), findsOneWidget);
    expect(find.text('Corrigido na versão nova!'), findsOneWidget);
    expect(find.text('Resposta do desenvolvedor'), findsOneWidget);
    expect(find.textContaining('Seu nome e e-mail vão junto'), findsOneWidget);

    // Texto curto demais não vai.
    await tester.enterText(find.byKey(const Key('report-text')), 'oi');
    await tester.tap(find.byKey(const Key('report-send')));
    await tester.pump();
    expect(sent, isEmpty);
    expect(find.textContaining('pelo menos 5 letras'), findsOneWidget);

    await tester.tap(find.text('Sugestão').first);
    await tester.pumpAndSettle();
    expect(find.text('Enviar sugestão'), findsOneWidget);
    await tester.enterText(
        find.byKey(const Key('report-text')), '  Exportar para Excel  ');
    await tester.tap(find.byKey(const Key('report-send')));
    await tester.pumpAndSettle();
    expect(sent, [(ReportKind.idea, 'Exportar para Excel')]);
    expect(find.textContaining('Obrigado pela ideia'), findsOneWidget);
    expect(
        tester
            .widget<TextField>(find.byKey(const Key('report-text')))
            .controller!
            .text,
        isEmpty);
  });

  testWidgets('desenvolvedor filtra, muda status, responde e apaga',
      (tester) async {
    phone(tester);
    final statuses = <String, ReportStatus>{};
    final replies = <String, String>{};
    final deleted = <String>[];
    await tester.pumpWidget(FinancasApp(
      home: ReportsAdminPage(
        avatar: const CircleAvatar(radius: 17),
        reports: Stream.value([
          report('a'),
          report('b', kind: ReportKind.idea, text: 'Modo claro'),
          report('c', status: ReportStatus.done, text: 'Já resolvido'),
        ]),
        onStatus: (id, s) async => statuses[id] = s,
        onReply: (id, t) async => replies[id] = t,
        onDelete: (id) async => deleted.add(id),
      ),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Novos (2)'), findsOneWidget);
    expect(find.text('Resolvidos (1)'), findsOneWidget);
    expect(find.text('Já resolvido'), findsNothing, reason: 'filtro Novos');
    expect(find.text('maria@exemplo.com'), findsNWidgets(2));

    // Só sugestões.
    await tester.tap(find.text('Sugestões'));
    await tester.pumpAndSettle();
    expect(find.text('Novos (1)'), findsOneWidget);
    expect(find.text('O gráfico não abre'), findsNothing);
    await tester.tap(find.text('Tudo'));
    await tester.pumpAndSettle();

    final cardA = find.byKey(const Key('admin-report-a'));
    await tester
        .tap(find.descendant(of: cardA, matching: find.text('Em análise')));
    await tester.pumpAndSettle();
    expect(statuses['a'], ReportStatus.inReview);

    await tester
        .tap(find.descendant(of: cardA, matching: find.text('Responder')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('reply-text')), 'Vou olhar, obrigado!');
    await tester.tap(find.text('Enviar resposta'));
    await tester.pumpAndSettle();
    expect(replies['a'], 'Vou olhar, obrigado!');

    await tester.tap(find.descendant(
        of: find.byKey(const Key('admin-report-b')),
        matching: find.byTooltip('Apagar')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Apagar'));
    await tester.pumpAndSettle();
    expect(deleted, ['b']);

    await tester.tap(find.text('Todos (3)'));
    await tester.pumpAndSettle();
    expect(find.text('Já resolvido'), findsOneWidget);
  });
}
