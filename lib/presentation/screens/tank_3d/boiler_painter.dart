import 'dart:math';
import 'package:flutter/material.dart';
import 'boiler_state.dart';

/// Full aquatubular boiler painter – SCADA / Digital Twin style.
///
/// Hierarchy rendered (matching the naming convention):
///   StructuralFrame, Furnace (Burner + Flame), WaterWallTubes,
///   MudDrum, SteamDrum (WaterLevel + LevelGauge + Sensors),
///   Economizer, FuelSystem, AirSystem (FD Fan + AirDamper),
///   DraftSystem (ID Fan + FlueGasDamper), GasDucts, FlowIndicators.
class BoilerPainter extends CustomPainter {
  final BoilerState state;

  BoilerPainter(this.state);

  // ── colour palette ──
  static const _bg = Color(0xFF0d1117);
  static const _metalLight = Color(0xFFcdd3da);
  static const _metalMid = Color(0xFF8a929c);
  static const _metalDark = Color(0xFF3a3f4a);
  static const _metalEdge = Color(0xFF252830);
  static const _waterBlue = Color(0xFF29b6f6);
  static const _steamWhite = Color(0xFFe0f7fa);
  static const _gasRed = Color(0xFFef5350);
  static const _airCyan = Color(0xFF4dd0e1);
  static const _flamOrange = Color(0xFFff9800);
  static const _flamBlue = Color(0xFF42a5f5);

  @override
  void paint(Canvas canvas, Size size) {
    _drawGrid(canvas, size);

    // Layout zones ---------------------------------------------------------
    // The boiler occupies the centre ≈80 % of the canvas.
    final margin = size.width * 0.08;
    final bL = margin;
    final bR = size.width - margin;
    final bT = size.height * 0.06;
    final bB = size.height * 0.88;
    final bW = bR - bL;
    final bH = bB - bT;

    // Sub-regions
    final furnaceL = bL + bW * 0.05;
    final furnaceR = bL + bW * 0.55;
    final furnaceT = bT + bH * 0.30;
    final furnaceB = bB - bH * 0.08;

    final drumW = bW * 0.40;
    final drumH = bH * 0.10;
    final steamDrumCx = bL + bW * 0.55;
    final steamDrumCy = bT + bH * 0.12;
    final mudDrumCx = bL + bW * 0.55;
    final mudDrumCy = bB - bH * 0.06;

    // ── draw order (back → front) ─────────────────────────────────────────
    _drawStructuralFrame(canvas, bL, bT, bR, bB);
    _drawGasDucts(canvas, furnaceR, furnaceT, bR, bT, bB, bW, bH);
    _drawEconomizer(
        canvas, bL + bW * 0.65, bT + bH * 0.50, bW * 0.25, bH * 0.20);
    _drawFurnace(canvas, furnaceL, furnaceT, furnaceR, furnaceB);
    _drawBurnerAndFlame(canvas, furnaceL, furnaceT, furnaceR, furnaceB);
    _drawWaterWallTubes(canvas, furnaceL, furnaceT, furnaceR, furnaceB,
        steamDrumCx, steamDrumCy, mudDrumCx, mudDrumCy, drumW, drumH);
    _drawMudDrum(canvas, mudDrumCx, mudDrumCy, drumW, drumH);
    _drawSteamDrum(canvas, steamDrumCx, steamDrumCy, drumW, drumH);
    _drawFuelSystem(canvas, furnaceL, furnaceB, bL, bB, bH);
    _drawAirSystem(canvas, furnaceL, furnaceT, furnaceB, bL, bW, bH, bT);
    _drawDraftSystem(canvas, bR, bT, bB, bW, bH, bL);
    _drawFlowIndicators(canvas, furnaceL, furnaceR, furnaceT, furnaceB,
        steamDrumCx, steamDrumCy, mudDrumCx, mudDrumCy, bR, bT, bB, bW, bH, bL);
    _drawLabels(canvas, furnaceL, furnaceR, furnaceT, furnaceB, steamDrumCx,
        steamDrumCy, mudDrumCx, mudDrumCy, bL, bR, bT, bB, bW, bH);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  BACKGROUND GRID
  // ═══════════════════════════════════════════════════════════════════════════
  void _drawGrid(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.white.withOpacity(0.015)
      ..strokeWidth = 0.5;
    const sp = 30.0;
    for (double x = 0; x < size.width; x += sp) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (double y = 0; y < size.height; y += sp) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  STRUCTURAL FRAME
  // ═══════════════════════════════════════════════════════════════════════════
  void _drawStructuralFrame(
      Canvas canvas, double l, double t, double r, double b) {
    final p = Paint()
      ..color = _metalDark.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTRB(l, t, r, b), const Radius.circular(6)),
        p);
    // Ground shadow
    canvas.drawLine(
        Offset(l, b + 4),
        Offset(r, b + 4),
        Paint()
          ..color = Colors.black.withOpacity(0.3)
          ..strokeWidth = 6
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  FURNACE
  // ═══════════════════════════════════════════════════════════════════════════
  void _drawFurnace(Canvas canvas, double l, double t, double r, double b) {
    final rect = Rect.fromLTRB(l, t, r, b);
    // Firewall bricks effect
    canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(4)),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: const [
              Color(0xFF2a1a0e),
              Color(0xFF3d2214),
              Color(0xFF1a1008),
            ],
          ).createShader(rect));
    // Inner glow from flame
    if (state.flameOn) {
      final glow = Rect.fromLTRB(l + 10, t + 10, r - 10, b - 10);
      canvas.drawRRect(
          RRect.fromRectAndRadius(glow, const Radius.circular(2)),
          Paint()
            ..color = _flamOrange.withOpacity(0.06 * state.flameIntensity)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 30));
    }
    // Border
    canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(4)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = _metalDark.withOpacity(0.5));
    // Brick lines
    final bP = Paint()
      ..color = const Color(0xFF1a0f08).withOpacity(0.35)
      ..strokeWidth = 0.6;
    final rows = ((b - t) / 12).floor();
    for (int i = 1; i < rows; i++) {
      final y = t + i * 12;
      canvas.drawLine(Offset(l + 2, y), Offset(r - 2, y), bP);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  BURNER + FLAME
  // ═══════════════════════════════════════════════════════════════════════════
  void _drawBurnerAndFlame(
      Canvas canvas, double fL, double fT, double fR, double fB) {
    final cx = fL + (fR - fL) * 0.18;
    final cy = fB - (fB - fT) * 0.22;
    final bW = (fR - fL) * 0.10;

    // Burner nozzle
    _drawCylinder(canvas, cx - bW / 2, cy - bW * 0.6, bW, bW * 1.2, _metalMid,
        _metalDark);

    // Flame
    if (state.flameOn) {
      final flameW = (fR - fL) * 0.55 * state.flameIntensity;
      final flameH = (fB - fT) * 0.18 * state.flameIntensity;
      final coreColor =
          Color.lerp(_flamOrange, _flamBlue, state.flameIntensity)!;
      final outerColor = Color.lerp(const Color(0xFFff5722),
          const Color(0xFF1e88e5), state.flameIntensity)!;

      // Outer flame
      final outerPath = Path();
      outerPath.moveTo(cx + bW * 0.3, cy);
      outerPath.quadraticBezierTo(
          cx + flameW * 0.5,
          cy - flameH * (0.8 + 0.2 * sin(state.wavePhase * 3)),
          cx + flameW,
          cy - flameH * 0.1 * sin(state.wavePhase * 5));
      outerPath.quadraticBezierTo(
          cx + flameW * 0.5,
          cy + flameH * (0.8 + 0.2 * sin(state.wavePhase * 3 + 1)),
          cx + bW * 0.3,
          cy);
      canvas.drawPath(
          outerPath,
          Paint()
            ..color = outerColor.withOpacity(0.25)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12));

      // Core flame
      final corePath = Path();
      corePath.moveTo(cx + bW * 0.3, cy);
      corePath.quadraticBezierTo(
          cx + flameW * 0.35,
          cy - flameH * 0.5 * (0.9 + 0.1 * sin(state.wavePhase * 4)),
          cx + flameW * 0.7,
          cy - flameH * 0.05 * sin(state.wavePhase * 6));
      corePath.quadraticBezierTo(
          cx + flameW * 0.35,
          cy + flameH * 0.5 * (0.9 + 0.1 * sin(state.wavePhase * 4 + 1)),
          cx + bW * 0.3,
          cy);
      canvas.drawPath(
          corePath,
          Paint()
            ..shader = LinearGradient(colors: [
              coreColor.withOpacity(0.7),
              coreColor.withOpacity(0.0),
            ]).createShader(
                Rect.fromLTRB(cx, cy - flameH, cx + flameW, cy + flameH)));

      // Hot-spot glow
      canvas.drawCircle(
          Offset(cx + bW * 0.4, cy),
          flameH * 0.5,
          Paint()
            ..color = Colors.white.withOpacity(0.08 * state.flameIntensity)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18));
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  WATER WALL TUBES
  // ═══════════════════════════════════════════════════════════════════════════
  void _drawWaterWallTubes(
      Canvas canvas,
      double fL,
      double fT,
      double fR,
      double fB,
      double sdCx,
      double sdCy,
      double mdCx,
      double mdCy,
      double drumW,
      double drumH) {
    final tubeP = Paint()
      ..color = _metalMid.withOpacity(0.6)
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;
    final tubeFill = Paint()..color = _metalDark.withOpacity(0.3);
    final cnt = 8;
    for (int i = 0; i < cnt; i++) {
      final t = i / (cnt - 1);
      final x = fL + 6 + (fR - fL - 12) * t;
      // Riser tubes (front wall)
      canvas.drawLine(Offset(x, fT + 4), Offset(x, fB - 4), tubeP);
      // Subtle fill
      canvas.drawRect(
          Rect.fromLTRB(x - 1.5, fT + 4, x + 1.5, fB - 4), tubeFill);
    }
    // Connection headers (top & bottom)
    _drawHorizontalPipe(canvas, fL, fT - 3, fR - fL, 6, _metalMid);
    _drawHorizontalPipe(canvas, fL, fB - 3, fR - fL, 6, _metalMid);

    // Downcomers (outside furnace) from steam drum to mud drum
    final dcL = fR + 8;
    final dcR = fR + 18;
    final dcPaint = Paint()
      ..shader = LinearGradient(colors: [_metalDark, _metalLight, _metalDark])
          .createShader(Rect.fromLTRB(dcL, sdCy, dcR, mdCy))
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(dcL + 5, sdCy + drumH / 2),
        Offset(dcL + 5, mdCy - drumH / 2), dcPaint);
    canvas.drawLine(Offset(dcR + 5, sdCy + drumH / 2),
        Offset(dcR + 5, mdCy - drumH / 2), dcPaint);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  STEAM DRUM (with water level, gauge, sensors)
  // ═══════════════════════════════════════════════════════════════════════════
  void _drawSteamDrum(Canvas canvas, double cx, double cy, double w, double h) {
    final rect = Rect.fromCenter(center: Offset(cx, cy), width: w, height: h);
    // Body
    _drawDrumBody(canvas, rect, 'SteamDrum');
    // Water level inside (cutaway)
    _drawDrumWaterLevel(canvas, rect);
    // Level Gauge (external tube on right side)
    _drawLevelGauge(canvas, rect);
    // Sensors
    _drawLevelSensor(canvas, rect.right + 24, rect.top + h * 0.2, 'H');
    _drawLevelSensor(canvas, rect.right + 24, rect.bottom - h * 0.2, 'L');
  }

  void _drawDrumBody(Canvas canvas, Rect rect, String name) {
    final rrect =
        RRect.fromRectAndRadius(rect, Radius.circular(rect.height / 2));
    // Shadow
    canvas.drawRRect(
        rrect.shift(const Offset(3, 3)),
        Paint()
          ..color = Colors.black.withOpacity(0.25)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
    // Metal body
    canvas.drawRRect(
        rrect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: const [
              Color(0xFFd8dee4),
              Color(0xFFa0a8b2),
              Color(0xFF6e7680),
              Color(0xFF50565e),
            ],
          ).createShader(rect));
    // Specular highlight
    final specRect = Rect.fromLTRB(rect.left + 10, rect.top + 2,
        rect.right - 10, rect.top + rect.height * 0.35);
    canvas.drawRRect(
        RRect.fromRectAndRadius(specRect, Radius.circular(specRect.height)),
        Paint()..color = Colors.white.withOpacity(0.08));
    // Rim
    canvas.drawRRect(
        rrect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = _metalEdge);
    // Brushed texture
    final bP = Paint()
      ..color = Colors.white.withOpacity(0.012)
      ..strokeWidth = 0.4;
    for (double y = rect.top; y < rect.bottom; y += 1.6) {
      canvas.drawLine(Offset(rect.left + rect.height / 2, y),
          Offset(rect.right - rect.height / 2, y), bP);
    }

    // Highlight check
    if (state.highlightedComponent == name) {
      canvas.drawRRect(
          rrect.inflate(2),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = _waterBlue.withOpacity(0.8));
    }
  }

  void _drawDrumWaterLevel(Canvas canvas, Rect drum) {
    final fl = state.waterLevel.clamp(0.0, 1.0);
    final innerRect = drum.deflate(3);
    final waterTop = innerRect.bottom - innerRect.height * fl;
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(
        innerRect, Radius.circular(innerRect.height / 2)));
    // Cutaway dark interior
    canvas.drawRect(innerRect, Paint()..color = const Color(0xFF121620));
    // Water fill
    if (fl > 0.01) {
      final wRect = Rect.fromLTRB(
          innerRect.left, waterTop, innerRect.right, innerRect.bottom);
      canvas.drawRect(
          wRect,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                _waterBlue.withOpacity(0.6),
                const Color(0xFF0288d1).withOpacity(0.8),
                const Color(0xFF01579b),
              ],
            ).createShader(wRect));
      // Wave
      final wave = Path()..moveTo(innerRect.left, waterTop);
      for (double x = innerRect.left; x <= innerRect.right; x += 2) {
        final p = (x - innerRect.left) / innerRect.width;
        final y = waterTop +
            sin(state.wavePhase * 2 + p * pi * 6) * 1.5 +
            sin(state.wavePhase * 1.3 + p * pi * 10) * 0.8;
        wave.lineTo(x, y);
      }
      wave.lineTo(innerRect.right, waterTop + 6);
      wave.lineTo(innerRect.left, waterTop + 6);
      wave.close();
      canvas.drawPath(wave, Paint()..color = _steamWhite.withOpacity(0.2));
    }
    canvas.restore();
  }

  void _drawLevelGauge(Canvas canvas, Rect drum) {
    final gx = drum.right + 8;
    final gW = 6.0;
    final gT = drum.top + 2;
    final gB = drum.bottom - 2;
    final gRect = Rect.fromLTRB(gx, gT, gx + gW, gB);
    // Glass tube
    canvas.drawRRect(RRect.fromRectAndRadius(gRect, const Radius.circular(3)),
        Paint()..color = Colors.white.withOpacity(0.06));
    canvas.drawRRect(
        RRect.fromRectAndRadius(gRect, const Radius.circular(3)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = _metalMid.withOpacity(0.5));
    // Water in gauge
    final fl = state.waterLevel.clamp(0.0, 1.0);
    final wT = gB - (gB - gT) * fl;
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(gRect, const Radius.circular(3)));
    canvas.drawRect(Rect.fromLTRB(gx, wT, gx + gW, gB),
        Paint()..color = _waterBlue.withOpacity(0.5));
    canvas.restore();
  }

  void _drawLevelSensor(Canvas canvas, double x, double y, String tag) {
    final r = 5.0;
    canvas.drawCircle(
        Offset(x, y),
        r,
        Paint()
          ..color = tag == 'H'
              ? _gasRed.withOpacity(0.7)
              : _waterBlue.withOpacity(0.7));
    canvas.drawCircle(
        Offset(x, y),
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = _metalLight.withOpacity(0.5));
    final tp = TextPainter(
      text: TextSpan(
          text: tag,
          style: const TextStyle(
              color: Colors.white, fontSize: 7, fontWeight: FontWeight.bold)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(x - tp.width / 2, y - tp.height / 2));
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  MUD DRUM
  // ═══════════════════════════════════════════════════════════════════════════
  void _drawMudDrum(Canvas canvas, double cx, double cy, double w, double h) {
    final rect = Rect.fromCenter(center: Offset(cx, cy), width: w, height: h);
    _drawDrumBody(canvas, rect, 'MudDrum');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  ECONOMIZER
  // ═══════════════════════════════════════════════════════════════════════════
  void _drawEconomizer(Canvas canvas, double x, double y, double w, double h) {
    final rect = Rect.fromLTRB(x, y, x + w, y + h);
    canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(4)),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_metalDark, const Color(0xFF505868), _metalDark],
          ).createShader(rect));
    canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(4)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = _metalMid.withOpacity(0.4));
    // Serpentine tubes inside
    final tP = Paint()
      ..color = _metalLight.withOpacity(0.25)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final rows = 5;
    for (int i = 0; i < rows; i++) {
      final ty = y + 8 + (h - 16) * i / (rows - 1);
      canvas.drawLine(Offset(x + 8, ty), Offset(x + w - 8, ty), tP);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  GAS DUCTS
  // ═══════════════════════════════════════════════════════════════════════════
  void _drawGasDucts(Canvas canvas, double furnaceR, double furnaceT, double bR,
      double bT, double bB, double bW, double bH) {
    final p = Paint()
      ..color = _metalDark.withOpacity(0.2)
      ..strokeWidth = 14
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    // From furnace top → up → right to economizer/stack
    final path = Path()
      ..moveTo(furnaceR, furnaceT + 20)
      ..lineTo(furnaceR + bW * 0.12, furnaceT + 20)
      ..lineTo(furnaceR + bW * 0.12, bT + bH * 0.08)
      ..lineTo(bR - bW * 0.04, bT + bH * 0.08);
    canvas.drawPath(path, p);
    // Inner
    canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xFF1a1d28).withOpacity(0.8)
          ..strokeWidth = 10
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  FUEL SYSTEM
  // ═══════════════════════════════════════════════════════════════════════════
  void _drawFuelSystem(
      Canvas canvas, double fL, double fB, double bL, double bB, double bH) {
    final pipeY = fB - 10;
    final valveX = bL + 20;
    // Pipe
    _drawHorizontalPipe(canvas, bL - 5, pipeY - 3, fL - bL + 10, 6, _metalMid);
    // Valve
    _drawValve(canvas, valveX, pipeY, state.fuelValveOpen, _flamOrange);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  AIR SYSTEM (FD Fan + Air Damper)
  // ═══════════════════════════════════════════════════════════════════════════
  void _drawAirSystem(Canvas canvas, double fL, double fT, double fB, double bL,
      double bW, double bH, double bT) {
    final fanX = bL + bW * 0.01;
    final fanY = fT + (fB - fT) * 0.35;
    final fanR = min(bW * 0.04, 24.0);
    _drawFan(
        canvas, fanX, fanY, fanR, state.forcedDraftFanSpeed, state.fanPhase);
    // Air duct from fan to furnace
    _drawHorizontalPipe(canvas, fanX + fanR, fanY - 3, fL - fanX - fanR, 6,
        _airCyan.withOpacity(0.3));
    // Air Damper
    _drawDamper(canvas, fanX + fanR + 10, fanY, state.airDamperOpen, _airCyan);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  DRAFT SYSTEM (ID Fan + Flue Gas Damper)
  // ═══════════════════════════════════════════════════════════════════════════
  void _drawDraftSystem(Canvas canvas, double bR, double bT, double bB,
      double bW, double bH, double bL) {
    final fanX = bR - bW * 0.02;
    final fanY = bT + bH * 0.08;
    final fanR = min(bW * 0.04, 24.0);
    _drawFan(canvas, fanX, fanY, fanR, state.inducedDraftFanSpeed,
        state.fanPhase + pi);
    // Flue Gas Damper
    _drawDamper(
        canvas, fanX - fanR - 18, fanY, state.flueGasDamperOpen, _gasRed);
    // Stack
    final stackX = bR - 12;
    final stackB = bT + bH * 0.08 - fanR;
    final stackT = bT - bH * 0.02;
    canvas.drawRect(
        Rect.fromLTRB(stackX - 8, stackT, stackX + 8, stackB),
        Paint()
          ..shader =
              LinearGradient(colors: [_metalDark, _metalLight, _metalDark])
                  .createShader(
                      Rect.fromLTRB(stackX - 8, stackT, stackX + 8, stackB)));
    canvas.drawRect(
        Rect.fromLTRB(stackX - 8, stackT, stackX + 8, stackB),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = _metalEdge);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  FLOW INDICATORS (animated arrows)
  // ═══════════════════════════════════════════════════════════════════════════
  void _drawFlowIndicators(
      Canvas canvas,
      double fL,
      double fR,
      double fT,
      double fB,
      double sdCx,
      double sdCy,
      double mdCx,
      double mdCy,
      double bR,
      double bT,
      double bB,
      double bW,
      double bH,
      double bL) {
    final phase = state.wavePhase;
    // Water flow (blue) – up through water walls
    _drawFlowArrow(canvas, Offset(fL + 30, fB - 8), Offset(fL + 30, fT + 8),
        _waterBlue, phase);
    // Steam flow (white) – out of steam drum up
    _drawFlowArrow(canvas, Offset(sdCx, sdCy - 20), Offset(sdCx, sdCy - 50),
        _steamWhite, phase * 0.8);
    // Flue gas (red) – furnace top → right → up to stack
    _drawFlowArrow(canvas, Offset(fR + 5, fT + 20),
        Offset(fR + bW * 0.12, fT + 20), _gasRed, phase * 1.2);
    // Air (cyan) – into furnace
    _drawFlowArrow(canvas, Offset(bL + bW * 0.04, fT + (fB - fT) * 0.35),
        Offset(fL - 2, fT + (fB - fT) * 0.35), _airCyan, phase * 0.9);
    // Fuel (orange) – into burner
    _drawFlowArrow(canvas, Offset(bL + 8, fB - 10), Offset(fL - 2, fB - 10),
        _flamOrange, phase * 1.1);
  }

  void _drawFlowArrow(
      Canvas canvas, Offset from, Offset to, Color color, double phase) {
    final dx = to.dx - from.dx;
    final dy = to.dy - from.dy;
    final len = sqrt(dx * dx + dy * dy);
    if (len < 10) return;
    final nx = dx / len;
    final ny = dy / len;

    final arrowLen = 8.0;
    final gap = 20.0;
    final count = (len / gap).floor();
    final offset = (phase * 10) % gap;

    final paint = Paint()
      ..color = color.withOpacity(0.5)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < count; i++) {
      final d = offset + i * gap;
      if (d > len - arrowLen) continue;
      final px = from.dx + nx * d;
      final py = from.dy + ny * d;
      final tx = px + nx * arrowLen;
      final ty = py + ny * arrowLen;
      // Arrow shaft
      canvas.drawLine(Offset(px, py), Offset(tx, ty), paint);
      // Arrowhead
      final hx = -ny * 3;
      final hy = nx * 3;
      final path = Path()
        ..moveTo(tx, ty)
        ..lineTo(tx - nx * 4 + hx, ty - ny * 4 + hy)
        ..lineTo(tx - nx * 4 - hx, ty - ny * 4 - hy)
        ..close();
      canvas.drawPath(path, Paint()..color = color.withOpacity(0.4));
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  LABELS
  // ═══════════════════════════════════════════════════════════════════════════
  void _drawLabels(
      Canvas canvas,
      double fL,
      double fR,
      double fT,
      double fB,
      double sdCx,
      double sdCy,
      double mdCx,
      double mdCy,
      double bL,
      double bR,
      double bT,
      double bB,
      double bW,
      double bH) {
    final style = TextStyle(
      color: Colors.white.withOpacity(0.35),
      fontSize: min(bW * 0.018, 11),
      fontWeight: FontWeight.w500,
      letterSpacing: 0.8,
    );
    _drawLabel(canvas, 'STEAM DRUM', sdCx, sdCy - bH * 0.10 - 12, style);
    _drawLabel(canvas, 'MUD DRUM', mdCx, mdCy + bH * 0.06, style);
    _drawLabel(canvas, 'FORNALHA', (fL + fR) / 2, fT - 14, style);
    _drawLabel(canvas, 'ECONOMIZER', bL + bW * 0.775, bT + bH * 0.48, style);

    // Water level value
    final lvlStyle = TextStyle(
      color: _waterBlue,
      fontSize: min(bW * 0.022, 13),
      fontWeight: FontWeight.w600,
    );
    _drawLabel(canvas, '${(state.waterLevel * 100).toStringAsFixed(0)}%',
        sdCx + bW * 0.27 + 36, sdCy, lvlStyle);
  }

  void _drawLabel(
      Canvas canvas, String text, double x, double y, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(x - tp.width / 2, y - tp.height / 2));
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  REUSABLE COMPONENTS
  // ═══════════════════════════════════════════════════════════════════════════

  void _drawCylinder(Canvas canvas, double x, double y, double w, double h,
      Color light, Color dark) {
    final rect = Rect.fromLTWH(x, y, w, h);
    canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(w / 2)),
        Paint()
          ..shader =
              LinearGradient(colors: [dark, light, dark]).createShader(rect));
    canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(w / 2)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..color = _metalEdge);
  }

  void _drawHorizontalPipe(
      Canvas canvas, double x, double y, double w, double h, Color color) {
    final rect = Rect.fromLTWH(x, y, w, h);
    canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(h / 2)),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              _metalDark,
              color,
              _metalDark,
            ],
          ).createShader(rect));
  }

  void _drawFan(Canvas canvas, double cx, double cy, double r, double speed,
      double phase) {
    // Housing
    canvas.drawCircle(
        Offset(cx, cy), r, Paint()..color = _metalDark.withOpacity(0.6));
    canvas.drawCircle(
        Offset(cx, cy),
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = _metalMid.withOpacity(0.4));
    // Blades
    if (speed > 0) {
      final bP = Paint()..color = _metalLight.withOpacity(0.3);
      final blades = 4;
      for (int i = 0; i < blades; i++) {
        final angle = phase * speed * 3 + (2 * pi / blades) * i;
        final bx = cx + cos(angle) * r * 0.85;
        final by = cy + sin(angle) * r * 0.85;
        canvas.drawLine(
            Offset(cx, cy),
            Offset(bx, by),
            Paint()
              ..color = _metalLight.withOpacity(0.3)
              ..strokeWidth = max(r * 0.2, 2));
      }
    }
    // Centre hub
    canvas.drawCircle(Offset(cx, cy), r * 0.2, Paint()..color = _metalMid);
  }

  void _drawValve(
      Canvas canvas, double x, double y, double openFraction, Color color) {
    final s = 10.0;
    // Body
    canvas.drawRect(
        Rect.fromCenter(center: Offset(x, y), width: s, height: s * 1.2),
        Paint()..color = _metalDark);
    canvas.drawRect(
        Rect.fromCenter(center: Offset(x, y), width: s, height: s * 1.2),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = _metalMid.withOpacity(0.5));
    // Indicator
    final iH = s * openFraction;
    canvas.drawRect(
        Rect.fromLTRB(x - s * 0.3, y + s * 0.6 - iH, x + s * 0.3, y + s * 0.6),
        Paint()..color = color.withOpacity(0.5));
    // Handwheel
    canvas.drawCircle(
        Offset(x, y - s * 0.8),
        4,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = color.withOpacity(0.6));
  }

  void _drawDamper(
      Canvas canvas, double x, double y, double openFraction, Color color) {
    final angle = (1.0 - openFraction) * pi / 2;
    canvas.save();
    canvas.translate(x, y);
    canvas.rotate(angle);
    canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: 16, height: 3),
        Paint()..color = color.withOpacity(0.5));
    canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: 16, height: 3),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..color = _metalMid.withOpacity(0.5));
    canvas.restore();
    // Pivot
    canvas.drawCircle(
        Offset(x, y), 2.5, Paint()..color = _metalMid.withOpacity(0.5));
  }

  @override
  bool shouldRepaint(BoilerPainter old) => true;
}
