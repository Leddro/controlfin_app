import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:financas_app/services/avatar_service.dart';
import 'package:financas_app/widgets/user_avatar.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// PNG retangular: metade esquerda vermelha, metade direita azul.
Future<Uint8List> _png(int width, int height) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(Rect.fromLTWH(0, 0, width / 2, height.toDouble()),
      Paint()..color = const Color(0xFFFF0000));
  canvas.drawRect(Rect.fromLTWH(width / 2, 0, width / 2, height.toDouble()),
      Paint()..color = const Color(0xFF0000FF));
  final image = await recorder.endRecording().toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

void main() {
  testWidgets('foto vira JPEG quadrado de 256 recortado no centro',
      (tester) async {
    await tester.runAsync(() async {
      final jpg = await prepareAvatar(await _png(1200, 600));
      final decoded = img.decodeJpg(jpg)!;
      expect(decoded.width, 256);
      expect(decoded.height, 256);
      expect(jpg.length, lessThan(100 * 1024));

      // Recorte central: esquerda ainda vermelha, direita ainda azul.
      final left = decoded.getPixel(20, 128);
      final right = decoded.getPixel(236, 128);
      expect(left.r, greaterThan(200));
      expect(left.b, lessThan(60));
      expect(right.b, greaterThan(200));
      expect(right.r, lessThan(60));
    });
  });

  testWidgets('bytes que não são imagem geram erro', (tester) async {
    await tester.runAsync(() async {
      await expectLater(
        prepareAvatar(Uint8List.fromList([1, 2, 3, 4])),
        throwsA(anything),
      );
    });
  });

  testWidgets('sem foto mostra a inicial do nome', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: AvatarCircle(label: 'carlos', radius: 30)),
    ));
    expect(find.text('C'), findsOneWidget);
  });
}
