import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme.dart';

/// СШ monogram drawn as a head: С arc over the top, Ш as the face, small camera as the neck.
/// [arc], [bars], [cam] (0..1) drive the splash animation.
class LogoPainter extends CustomPainter {
  final double arc, bars, cam;
  final Color shColor, camColor;
  final bool solidArc;
  final Color arcColor;
  LogoPainter({this.arc = 1, this.bars = 1, this.cam = 1, this.shColor = const Color(0xFF0D1433), this.camColor = C.yellow, this.solidArc = false, this.arcColor = Colors.white});

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 120;
    canvas.scale(k);
    // С arc (300°, open at the bottom)
    final rect = Rect.fromCircle(center: const Offset(60, 53.7), radius: 42);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 13
      ..strokeCap = StrokeCap.round;
    if (solidArc) {
      p.color = arcColor;
    } else {
      p.shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFE6337A), Color(0xFF7B4FD6), Color(0xFF11A6E0)], stops: [0, .55, 1]).createShader(const Rect.fromLTWH(0, 0, 120, 120));
    }
    if (arc > 0) canvas.drawArc(rect, 120 * math.pi / 180, 300 * math.pi / 180 * arc, false, p);
    // Ш bars rise from the bottom
    final f = Paint()..color = shColor;
    void bar(double x, double y, double w, double h) {
      final hh = h * bars;
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, y + h - hh, w, hh), const Radius.circular(4.5)), f);
    }

    if (bars > 0) {
      bar(42, 37, 9, 34);
      bar(55.5, 43, 9, 28);
      bar(69, 37, 9, 34);
      final bw = 36 * bars;
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(60 - bw / 2, 62, bw, 9), const Radius.circular(4.5)), f);
    }
    // small camera under the opening
    if (cam > 0) {
      canvas.save();
      canvas.translate(60, 106);
      canvas.scale(cam);
      canvas.translate(-60, -106);
      final cp = Paint()..color = camColor;
      canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(55.6, 97.6, 8.8, 4), const Radius.circular(1.6)), cp);
      canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(50.5, 100, 19, 13.4), const Radius.circular(4)), cp);
      canvas.drawCircle(const Offset(60, 106.7), 4.3, Paint()..color = Colors.white);
      canvas.drawCircle(const Offset(60, 106.7), 2.5, Paint()..color = const Color(0xFF0D1433));
      canvas.drawCircle(const Offset(59, 105.7), .8, Paint()..color = Colors.white);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(LogoPainter o) => o.arc != arc || o.bars != bars || o.cam != cam;
}

/// Glossy 3D blue play triangle with the shining ПАХШ label.
class KnobPainter extends CustomPainter {
  final double shine; // 0..1 sweep position
  final String label;
  KnobPainter({required this.shine, required this.label});

  Path _tri() => Path()
    ..moveTo(27, 15)
    ..quadraticBezierTo(14, 8, 14, 23)
    ..lineTo(14, 73)
    ..quadraticBezierTo(14, 88, 27, 81)
    ..lineTo(79.5, 54.5)
    ..quadraticBezierTo(92, 48, 79.5, 41.5)
    ..close();

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 96;
    canvas.scale(k);
    // squeeze slightly from the sides, as approved
    canvas.translate(48, 48);
    canvas.scale(.88, 1);
    canvas.translate(-48, -48);
    final tri = _tri();
    canvas.drawShadow(tri.shift(const Offset(3, 4)), const Color(0xFF14308F), 6, false);
    canvas.drawPath(tri, Paint()..shader = const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF7DB8FF), Color(0xFF2F6DF0), Color(0xFF1533A8)]).createShader(const Rect.fromLTWH(0, 0, 96, 96)));
    canvas.drawPath(tri, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..shader = const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFE4F0FF), Color(0x995C8EF5), Color(0xFF0D2378)]).createShader(const Rect.fromLTWH(0, 0, 96, 96)));
    // raised inner face
    canvas.save();
    canvas.translate(38.7, 48);
    canvas.scale(.76);
    canvas.translate(-38.7, -48);
    canvas.drawPath(tri, Paint()..shader = const RadialGradient(center: Alignment(-.36, -.32), radius: .75, colors: [Color(0xFFC9E2FF), Color(0xFF5E96FA), Color(0xFF2556DC), Color(0xFF1D45C4)], stops: [0, .35, .8, 1]).createShader(const Rect.fromLTWH(0, 0, 96, 96)));
    canvas.restore();
    // gloss
    final gloss = Path()
      ..moveTo(28, 19.5)
      ..quadraticBezierTo(19, 14.8, 19, 25)
      ..lineTo(19, 45)
      ..quadraticBezierTo(44, 39, 70, 42.5)
      ..close();
    canvas.drawPath(gloss, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.white.withValues(alpha: .8), Colors.white.withValues(alpha: 0)]).createShader(const Rect.fromLTWH(19, 15, 51, 30)));
    canvas.drawOval(const Rect.fromLTWH(23.3, 22.4, 6.4, 9.2), Paint()..color = Colors.white);
    // label with a light sweeping left → right
    final x0 = -55 + 110 * shine;
    final shader = LinearGradient(colors: const [Color(0xFFCFE2FF), Color(0xFFCFE2FF), Colors.white, Color(0xFFFFF4C2), Color(0xFFCFE2FF), Color(0xFFCFE2FF)], stops: const [0, .4, .5, .54, .62, 1]).createShader(Rect.fromLTWH(x0, 0, 80, 10));
    final tp = TextPainter(
      text: TextSpan(text: label, style: tx(14.2, FontWeight.w800).copyWith(foreground: Paint()..shader = shader, shadows: const [Shadow(color: Color(0x7312308F), blurRadius: 2)])),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(41.5 - tp.width / 2, 53.5 - tp.height * .78));
  }

  @override
  bool shouldRepaint(KnobPainter o) => o.shine != shine || o.label != label;
}

/// Red → green → blue camera used on the yellow selfie button and the shutter.
class RgbCameraPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 48;
    canvas.scale(k);
    const body = LinearGradient(colors: [C.red, C.green, C.blue]);
    final bodyPaint = Paint()..shader = body.createShader(const Rect.fromLTWH(4, 6, 40, 36));
    final top = Path()
      ..moveTo(17, 11.5)
      ..lineTo(19.6, 7.6)
      ..quadraticBezierTo(20.4, 6.5, 21.8, 6.5)
      ..lineTo(26.2, 6.5)
      ..quadraticBezierTo(27.6, 6.5, 28.4, 7.6)
      ..lineTo(31, 11.5)
      ..close();
    canvas.drawPath(top, bodyPaint);
    final r = RRect.fromRectAndRadius(const Rect.fromLTWH(4, 11, 40, 30), const Radius.circular(10));
    canvas.drawRRect(r, bodyPaint);
    canvas.drawRRect(r, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.white.withValues(alpha: .35), Colors.white.withValues(alpha: 0), Colors.black.withValues(alpha: .15)]).createShader(const Rect.fromLTWH(4, 11, 40, 30)));
    canvas.drawCircle(const Offset(24, 26.5), 11, Paint()..color = C.paper);
    canvas.drawCircle(const Offset(24, 26.5), 8.4, Paint()..shader = const RadialGradient(center: Alignment(-.24, -.3), colors: [Color(0xFF9AA7C7), Color(0xFF2E3654), Color(0xFF11152A)], stops: [0, .4, 1]).createShader(Rect.fromCircle(center: const Offset(24, 26.5), radius: 8.4)));
    canvas.drawCircle(const Offset(21, 23.4), 2.4, Paint()..color = Colors.white.withValues(alpha: .9));
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(33.5, 15, 6, 3.4), const Radius.circular(1.7)), Paint()..color = Colors.white.withValues(alpha: .9));
    canvas.drawCircle(const Offset(10, 16.6), 1.6, Paint()..color = Colors.white.withValues(alpha: .85));
  }

  @override
  bool shouldRepaint(covariant CustomPainter o) => false;
}

/// Tinted pane zones, inset groove and the RGB line that bulges around the knob.
class CurvePainter extends CustomPainter {
  final double s, ky;
  CurvePainter({required this.s, required this.ky});

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    canvas.clipRect(Offset.zero & size); // keep the curve inside the board
    final lx = 158 * s, bx = 112 * s;
    double y(double d) => ky + d * s;
    Path line() => Path()
      ..moveTo(lx, 0)
      ..lineTo(lx, y(-98))
      ..cubicTo(lx, y(-52), bx, y(-46), bx, ky)
      ..cubicTo(bx, y(46), lx, y(52), lx, y(98))
      ..lineTo(lx, h);
    final left = line()
      ..lineTo(0, h)
      ..lineTo(0, 0)
      ..close();
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, h), Paint()..color = C.zoneR);
    canvas.drawPath(left, Paint()..color = C.zoneL);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(line().shift(Offset(1.8 * s, 1.8 * s)), stroke..color = Colors.white..strokeWidth = 16 * s);
    canvas.drawPath(line().shift(Offset(-1.8 * s, -1.8 * s)), stroke..color = C.lo..strokeWidth = 16 * s);
    canvas.drawPath(line(), stroke..color = const Color(0xFFE2E7EF)..strokeWidth = 14 * s);
    canvas.drawPath(
        line(),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 6 * s
          ..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [C.red, C.green, C.blue]).createShader(Rect.fromLTWH(0, 0, size.width, h)));
  }

  @override
  bool shouldRepaint(CurvePainter o) => o.ky != ky || o.s != s;
}
