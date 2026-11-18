import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:financas_app/main.dart';

void main() {
  testWidgets('FinancasApp monta com tema escuro e locale pt_BR',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const FinancasApp(home: Scaffold(body: Text('ControlFin'))),
    );

    expect(find.text('ControlFin'), findsOneWidget);

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.title, 'ControlFin');
    expect(app.locale, const Locale('pt', 'BR'));
    expect(app.theme?.brightness, Brightness.dark);
  });
}
