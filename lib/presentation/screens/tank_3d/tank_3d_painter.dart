import 'dart:math';
import 'package:flutter/material.dart';

class Tank3dPainter extends CustomPainter {
  final double fluidLevel;
  final double wavePhase;

  Tank3dPainter({required this.fluidLevel, required this.wavePhase});

  // Brushed stainless steel gradient (simulates cylindrical curvature + light)
  static const _metal = [
    Color(0xFF383d48),
    Color(0xFF525a66),
    Color(0xFF6e7680),
    Color(0xFF8e969f),
    Color(0xFFa8b0b8),
    Color(0xFFc2c9d0),
    Color(0xFFd8dee4),
    Color(0xFFe4e9ed),
    Color(0xFFd8dee4),
    Color(0xFFc0c7ce),
    Color(0xFFa0a8b2),
    Color(0xFF7e868f),
    Color(0xFF585f6a),
    Color(0xFF383d48),
  ];
  static const _metalS = [
    0.0,
    0.07,
    0.15,
    0.24,
    0.33,
    0.41,
    0.47,
    0.50,
    0.53,
    0.60,
    0.70,
    0.82,
    0.93,
    1.0,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final cX = size.width / 2;
    final cY = size.height / 2;
    final w = min(size.width * 0.44, 300.0);
    final h = min(size.height * 0.62, 440.0);
    final l = cX - w / 2;
    final r = cX + w / 2;
    final t = cY - h / 2;
    final b = cY + h / 2;
    final eH = w * 0.16;
    final bT = t + eH / 2;
    final bB = b - eH / 2;
    final bH = bB - bT;
    final cut = cX + w * 0.03;
    final wt = max(w * 0.022, 3.0);
    final fl = fluidLevel.clamp(0.0, 1.0);
    final flY = bB - bH * fl;

    _drawGrid(canvas, size);
    _drawShadow(canvas, cX, b, w, eH);
    _drawLegs(canvas, l, r, b, eH, w);
    _drawBottomEllipse(canvas, cX, bB, w, eH);
    _drawBackInterior(canvas, l, r, bT, bB, cut, wt);
    if (fl > 0.005) {
      _drawFluid(canvas, l, r, bT, bB, flY, cut, wt, cX, w, eH);
    }
    _drawFrontWall(canvas, l, r, bT, bB, cut);
    _drawCutEdge(canvas, cut, bT, bB, wt, flY, fl);
    _drawTopEllipse(canvas, cX, bT, w, eH, cut, wt, fl);
    _drawSpecular(canvas, l, bT, bB, w, cut);
    _drawBrushedTexture(canvas, l, bT, bB, cut);
    _drawScale(canvas, l, bT, bB, bH, flY, fl);
  }

  void _drawGrid(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.012)
      ..strokeWidth = 0.5;
    const sp = 35.0;
    for (double x = 0; x < size.width; x += sp) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += sp) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  void _drawShadow(Canvas canvas, double cX, double b, double w, double eH) {
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(cX, b + 10), width: w * 1.2, height: eH * 1.5),
      Paint()
        ..color = Colors.black.withOpacity(0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20),
    );
  }

  void _drawLegs(
      Canvas canvas, double l, double r, double b, double eH, double w) {
    final paint = Paint()..color = const Color(0xFF4a5060);
    final lw = w * 0.06;
    final lh = eH * 0.8;
    for (final x in [l + w * 0.18, r - w * 0.18]) {
      final path = Path()
        ..moveTo(x, b - eH * 0.3)
        ..lineTo(x - lw, b + lh)
        ..lineTo(x + lw, b + lh)
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  void _drawBottomEllipse(
      Canvas canvas, double cX, double bB, double w, double eH) {
    final oval = Rect.fromCenter(center: Offset(cX, bB), width: w, height: eH);
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(cX - w / 2 - 2, bB, cX + w / 2 + 2, bB + eH));
    canvas.drawOval(
        oval,
        Paint()
          ..shader = LinearGradient(
            colors: const [
              Color(0xFF2a2d35),
              Color(0xFF4a5060),
              Color(0xFF2a2d35)
            ],
          ).createShader(oval));
    canvas.drawOval(
        oval,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = const Color(0xFF5a6270));
    canvas.restore();
  }

  void _drawBackInterior(Canvas canvas, double l, double r, double bT,
      double bB, double cut, double wt) {
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(cut + wt, bT, r, bB));
    canvas.drawRect(
        Rect.fromLTRB(l, bT, r, bB),
        Paint()
          ..shader = LinearGradient(
            colors: const [
              Color(0xFF14171e),
              Color(0xFF1e2230),
              Color(0xFF252a38),
              Color(0xFF1e2230),
              Color(0xFF14171e)
            ],
            stops: const [0.0, 0.2, 0.5, 0.8, 1.0],
          ).createShader(Rect.fromLTRB(l, bT, r, bB)));
    canvas.restore();
  }

  void _drawFluid(Canvas canvas, double l, double r, double bT, double bB,
      double flY, double cut, double wt, double cX, double w, double eH) {
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(cut + wt, bT, r, bB));

    final fRect = Rect.fromLTRB(cut + wt, flY, r, bB);

    // Vertical gradient
    canvas.drawRect(
        fRect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: const [
              Color(0xFF4fc3f7),
              Color(0xFF29b6f6),
              Color(0xFF0288d1),
              Color(0xFF01579b)
            ],
            stops: const [0.0, 0.08, 0.5, 1.0],
          ).createShader(fRect));

    // Horizontal depth
    canvas.drawRect(
        fRect,
        Paint()
          ..shader = LinearGradient(
            colors: [
              Colors.black.withOpacity(0.12),
              Colors.transparent,
              Colors.black.withOpacity(0.08)
            ],
          ).createShader(fRect));

    // Wave surface
    final wave = Path()..moveTo(cut + wt, flY);
    for (double x = cut + wt; x <= r; x += 1.5) {
      final p = (x - cut) / (r - cut);
      final y = flY +
          sin(wavePhase + p * pi * 4) * 2.5 +
          sin(wavePhase * 0.7 + p * pi * 7) * 1.2;
      wave.lineTo(x, y);
    }
    wave.lineTo(r, flY + 10);
    wave.lineTo(cut + wt, flY + 10);
    wave.close();
    canvas.drawPath(
        wave,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFF81d4fa).withOpacity(0.7),
              const Color(0xFF4fc3f7).withOpacity(0.15)
            ],
          ).createShader(Rect.fromLTRB(cut, flY - 5, r, flY + 12)));

    // Surface glow
    canvas.drawRect(
        Rect.fromLTRB(cut + wt, flY - 3, r, flY + 6),
        Paint()
          ..color = const Color(0xFF81d4fa).withOpacity(0.15)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));

    // Fluid surface ellipse (3D perspective)
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(cut + wt, flY - eH * 0.5, r, flY + eH * 0.5));
    final sOval = Rect.fromCenter(
        center: Offset(cX, flY), width: w * 0.88, height: eH * 0.82);
    canvas.drawOval(
        sOval,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.2, -0.3),
            colors: [
              const Color(0xFF81d4fa).withOpacity(0.5),
              const Color(0xFF29b6f6).withOpacity(0.2),
              const Color(0xFF0288d1).withOpacity(0.08)
            ],
            stops: const [0.0, 0.5, 1.0],
          ).createShader(sOval));
    canvas.restore();

    canvas.restore();
  }

  void _drawFrontWall(
      Canvas canvas, double l, double r, double bT, double bB, double cut) {
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(l, bT, cut, bB));
    canvas.drawRect(
        Rect.fromLTRB(l, bT, r, bB),
        Paint()
          ..shader = LinearGradient(colors: _metal, stops: _metalS)
              .createShader(Rect.fromLTRB(l, bT, r, bB)));
    // Ambient occlusion top
    canvas.drawRect(
        Rect.fromLTRB(l, bT, cut, bT + 25),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black.withOpacity(0.3), Colors.transparent],
          ).createShader(Rect.fromLTRB(l, bT, cut, bT + 25)));
    // Ambient occlusion bottom
    canvas.drawRect(
        Rect.fromLTRB(l, bB - 18, cut, bB),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.black.withOpacity(0.25)],
          ).createShader(Rect.fromLTRB(l, bB - 18, cut, bB)));
    canvas.restore();
  }

  void _drawCutEdge(Canvas canvas, double cut, double bT, double bB, double wt,
      double flY, double fl) {
    canvas.drawRect(
        Rect.fromLTRB(cut, bT, cut + wt, bB),
        Paint()
          ..shader = LinearGradient(
            colors: const [
              Color(0xFFdfe4e9),
              Color(0xFFb8c0c8),
              Color(0xFF8a929c)
            ],
          ).createShader(Rect.fromLTRB(cut, bT, cut + wt, bB)));
    canvas.drawLine(
        Offset(cut, bT),
        Offset(cut, bB),
        Paint()
          ..color = Colors.white.withOpacity(0.45)
          ..strokeWidth = 0.8);
    if (fl > 0.005) {
      canvas.drawRect(Rect.fromLTRB(cut, flY, cut + wt, bB),
          Paint()..color = const Color(0xFF0288d1).withOpacity(0.25));
    }
  }

  void _drawTopEllipse(Canvas canvas, double cX, double bT, double w, double eH,
      double cut, double wt, double fl) {
    final oval = Rect.fromCenter(center: Offset(cX, bT), width: w, height: eH);
    // Surface
    canvas.drawOval(
        oval,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.1, -0.4),
            colors: const [
              Color(0xFFe8ecf0),
              Color(0xFFcdd3da),
              Color(0xFF9aa2ac),
              Color(0xFF6a737e)
            ],
            stops: const [0.0, 0.3, 0.65, 1.0],
          ).createShader(oval));
    // Rim
    canvas.drawOval(
        oval,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0
          ..shader = LinearGradient(
            colors: const [
              Color(0xFF5a6270),
              Color(0xFFb0b8c2),
              Color(0xFFe0e5ea),
              Color(0xFFb0b8c2),
              Color(0xFF5a6270)
            ],
          ).createShader(oval));
    // Interior through cutaway hole
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(cut + wt, bT - eH, cX + w / 2 + 5, bT + eH));
    final inner = oval.deflate(wt * 1.5);
    if (fl >= 0.97) {
      canvas.drawOval(
          inner,
          Paint()
            ..shader = RadialGradient(
              colors: const [
                Color(0xFF4fc3f7),
                Color(0xFF29b6f6),
                Color(0xFF0288d1)
              ],
            ).createShader(inner));
    } else {
      canvas.drawOval(inner, Paint()..color = const Color(0xFF14171e));
    }
    canvas.restore();
  }

  void _drawSpecular(
      Canvas canvas, double l, double bT, double bB, double w, double cut) {
    final x = l + w * 0.30;
    final sw = w * 0.06;
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(l, bT, cut, bB));
    canvas.drawRect(
        Rect.fromLTRB(x, bT + 5, x + sw, bB - 5),
        Paint()
          ..shader = LinearGradient(
            colors: [
              Colors.transparent,
              Colors.white.withOpacity(0.08),
              Colors.white.withOpacity(0.15),
              Colors.white.withOpacity(0.08),
              Colors.transparent,
            ],
            stops: const [0.0, 0.2, 0.5, 0.8, 1.0],
          ).createShader(Rect.fromLTRB(x, bT, x + sw, bB)));
    canvas.restore();
  }

  void _drawBrushedTexture(
      Canvas canvas, double l, double bT, double bB, double cut) {
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(l, bT, cut, bB));
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.012)
      ..strokeWidth = 0.5;
    for (double y = bT; y < bB; y += 1.8) {
      canvas.drawLine(Offset(l, y), Offset(cut, y), paint);
    }
    canvas.restore();
  }

  void _drawScale(Canvas canvas, double l, double bT, double bB, double bH,
      double flY, double fl) {
    final mP = Paint()
      ..color = Colors.white24
      ..strokeWidth = 1.0;
    for (int i = 0; i <= 10; i++) {
      final y = bB - bH * (i / 10);
      final len = i % 5 == 0 ? 14.0 : 7.0;
      canvas.drawLine(Offset(l - len - 6, y), Offset(l - 6, y), mP);
      if (i % 5 == 0 && i > 0 && i < 10) {
        final tp = TextPainter(
          text: TextSpan(
              text: '${i * 10}',
              style: const TextStyle(color: Colors.white24, fontSize: 10)),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(l - len - tp.width - 10, y - tp.height / 2));
      }
    }
    if (fl > 0.01 && fl < 0.99) {
      final dP = Paint()
        ..color = const Color(0xFF4fc3f7).withOpacity(0.35)
        ..strokeWidth = 1.0;
      for (double x = l - 20; x < l - 6; x += 5) {
        canvas.drawLine(Offset(x, flY), Offset(x + 3, flY), dP);
      }
    }
    final pct = '${(fl * 100).toStringAsFixed(0)}%';
    final pS = TextStyle(
      color: const Color(0xFF81d4fa),
      fontSize: min(bH * 0.045, 20),
      fontWeight: FontWeight.w600,
      shadows: const [Shadow(color: Color(0xFF0288d1), blurRadius: 10)],
    );
    final pP = TextPainter(
        text: TextSpan(text: pct, style: pS), textDirection: TextDirection.ltr)
      ..layout();
    pP.paint(canvas, Offset(l - pP.width - 25, flY - pP.height / 2));
    final nP = TextPainter(
      text: const TextSpan(
          text: 'NÍVEL',
          style:
              TextStyle(color: Colors.white38, fontSize: 9, letterSpacing: 2)),
      textDirection: TextDirection.ltr,
    )..layout();
    nP.paint(canvas, Offset(l - nP.width - 25, flY - pP.height / 2 - 14));
  }

  @override
  bool shouldRepaint(Tank3dPainter old) =>
      old.fluidLevel != fluidLevel || old.wavePhase != wavePhase;
}
