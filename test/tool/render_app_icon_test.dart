// Gera os PNGs do ícone do app a partir da logo desenhada em código.
// Rodar só quando a logo mudar:
//   flutter test test/tool/render_app_icon_test.dart --dart-define=RENDER_ICON=true
//   dart run flutter_launcher_icons
@TestOn('vm')
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:financas_app/widgets/app_logo.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

const _enabled = bool.fromEnvironment('RENDER_ICON');
const _size = 1024.0;

// A logo ocupa de ~8% a ~73% da largura; desloca para ficar centralizada.
const _centerShift = _size * 0.07;

Future<void> _write(String path, void Function(Canvas) draw) async {
  final recorder = ui.PictureRecorder();
  draw(Canvas(recorder));
  final image =
      await recorder.endRecording().toImage(_size.toInt(), _size.toInt());
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(png!.buffer.asUint8List());
}

void main() {
  test('gera assets/icon', () async {
    // Ícone comum: fundo escuro ocupando o quadrado todo.
    await _write('assets/icon/app_icon.png', (canvas) {
      canvas.drawRect(const Rect.fromLTWH(0, 0, _size, _size),
          Paint()..color = const Color(0xFF111111));
      canvas.translate(_centerShift, 0);
      const AppLogoPainter(background: false)
          .paint(canvas, const Size(_size, _size));
    });

    // Camada da frente do ícone adaptável: logo dentro da área segura
    // (66% central), porque o Android recorta as bordas em círculo ou gota.
    await _write('assets/icon/app_icon_foreground.png', (canvas) {
      const scale = 0.66;
      canvas.translate(_size * (1 - scale) / 2, _size * (1 - scale) / 2);
      canvas.scale(scale);
      canvas.translate(_centerShift, 0);
      const AppLogoPainter(background: false)
          .paint(canvas, const Size(_size, _size));
    });
  }, skip: !_enabled);
}
