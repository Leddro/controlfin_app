import 'package:flutter/material.dart';

/// Logo do ControlFin em SVG inline, renderizada via Canvas.
/// Exibe o "C" dourado com gráfico de barras e seta de tendência.
class AppLogo extends StatelessWidget {
  final double size;

  const AppLogo({super.key, this.size = 36});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: const CustomPaint(painter: AppLogoPainter()),
    );
  }
}

/// Widget clicável que exibe a logo e navega para a rota raiz ao ser tocado.
class AppLogoButton extends StatelessWidget {
  final double size;

  const AppLogoButton({super.key, this.size = 36});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        // Volta para o início (remove todas as rotas até a primeira)
        Navigator.of(context).popUntil((route) => route.isFirst);
      },
      child: Tooltip(
        message: 'Início',
        child: AppLogo(size: size),
      ),
    );
  }
}

/// Desenho da logo. Também usado para gerar o ícone do app
/// (test/tool/render_app_icon_test.dart).
class AppLogoPainter extends CustomPainter {
  /// Fundo escuro arredondado. Desligado na camada da frente do ícone
  /// adaptável do Android, que recebe a cor de fundo à parte.
  final bool background;

  const AppLogoPainter({this.background = true});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Fundo preto com bordas arredondadas
    if (background) {
      final bgPaint = Paint()..color = const Color(0xFF111111);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(0, 0, w, h), Radius.circular(w * 0.19)),
        bgPaint,
      );
    }

    // Gradient dourado
    final goldShader = const LinearGradient(
      begin: Alignment.bottomLeft,
      end: Alignment.topRight,
      colors: [Color(0xFFB8860B), Color(0xFFF5A623), Color(0xFFFFD700)],
    ).createShader(Rect.fromLTWH(0, 0, w, h));
    final goldPaint = Paint()
      ..shader = goldShader
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.086
      ..strokeCap = StrokeCap.round;

    // "C" arc (abertura à direita, entre ~40° e ~320°)
    const startAngle = 0.70; // ~40°, ponta de baixo
    const sweepAngle = 4.89; // ~280°, passando pela esquerda até ~320°
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(w * 0.44, h * 0.50),
        width: w * 0.64,
        height: h * 0.64,
      ),
      startAngle,
      sweepAngle,
      false,
      goldPaint,
    );

    // Barras do gráfico
    final barPaint = Paint()
      ..shader = goldShader
      ..style = PaintingStyle.fill;

    final bx = [w * 0.340, w * 0.437, w * 0.534];
    final bh = [h * 0.164, h * 0.242, h * 0.320];
    final bw = w * 0.074;
    final bottom = h * 0.750;
    final radius = Radius.circular(bw * 0.3);

    for (var i = 0; i < 3; i++) {
      final opacity = 0.70 + 0.15 * i;
      barPaint.color = const Color(0xFFF5A623).withValues(alpha: opacity);
      barPaint.shader = null;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(bx[i], bottom - bh[i], bw, bh[i]),
          radius,
        ),
        barPaint,
      );
    }

    // Linha da seta
    final linePaint = Paint()
      ..color = const Color(0xFFFFD700)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.055
      ..strokeCap = StrokeCap.round;

    final p1 = Offset(w * 0.340, h * 0.638);
    final p2 = Offset(w * 0.620, h * 0.316);
    canvas.drawLine(p1, p2, linePaint);

    // Ponta da seta
    final arrowPaint = Paint()
      ..color = const Color(0xFFFFD700)
      ..style = PaintingStyle.fill;
    final arrowPath = Path()
      ..moveTo(p2.dx, p2.dy)
      ..lineTo(p2.dx - w * 0.080, p2.dy + h * 0.088)
      ..lineTo(p2.dx - w * 0.012, p2.dy + h * 0.096)
      ..close();
    canvas.drawPath(arrowPath, arrowPaint);
  }

  @override
  bool shouldRepaint(AppLogoPainter old) => old.background != background;
}
