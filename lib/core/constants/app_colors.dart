import 'package:flutter/material.dart';

abstract class AppColors {
  // ── Primary – industrial blue ──────────────────────────────────────────────
  static const Color primary          = Color(0xFF1565C0);
  static const Color primaryLight     = Color(0xFF5E92F3);
  static const Color primaryDark      = Color(0xFF003C8F);
  static const Color primaryContainer = Color(0xFF1E3A6E);

  // ── Secondary – teal ──────────────────────────────────────────────────────
  static const Color secondary        = Color(0xFF00695C);
  static const Color secondaryLight   = Color(0xFF439889);

  // ── Accent – amber / warning ──────────────────────────────────────────────
  static const Color accent           = Color(0xFFFF6F00);
  static const Color accentLight      = Color(0xFFFFA040);

  // ── Dark theme surfaces ────────────────────────────────────────────────────
  static const Color backgroundDark   = Color(0xFF0D1117);
  static const Color surfaceDark      = Color(0xFF161B22);
  static const Color cardDark         = Color(0xFF21262D);
  static const Color borderDark       = Color(0xFF30363D);

  // ── Light theme surfaces ───────────────────────────────────────────────────
  static const Color backgroundLight  = Color(0xFFF0F4F8);
  static const Color surfaceLight     = Color(0xFFFFFFFF);
  static const Color cardLight        = Color(0xFFF8FAFC);
  static const Color borderLight      = Color(0xFFDDE3EA);

  // ── Cell type colors ───────────────────────────────────────────────────────
  static const Color cellValue        = Color(0xFF2D3748);  // plain hex value
  static const Color cellValueLight   = Color(0xFFEDF2F7);
  static const Color cellFunc         = Color(0xFF1A3A5C);  // @expression
  static const Color cellFuncLight    = Color(0xFFBEE3F8);
  static const Color cellTFunc        = Color(0xFF1A4A3A);  // $transfer-fn
  static const Color cellTFuncLight   = Color(0xFFC6F6D5);

  // ── Status ─────────────────────────────────────────────────────────────────
  static const Color success          = Color(0xFF2E7D32);
  static const Color successLight     = Color(0xFF66BB6A);
  static const Color error            = Color(0xFFC62828);
  static const Color errorLight       = Color(0xFFEF5350);
  static const Color warning          = Color(0xFFE65100);
  static const Color warningLight     = Color(0xFFFFA726);
  static const Color info             = Color(0xFF0277BD);
  static const Color infoLight        = Color(0xFF29B6F6);

  // ── Text ───────────────────────────────────────────────────────────────────
  static const Color textPrimary      = Color(0xFFE6EDF3);
  static const Color textSecondary    = Color(0xFF8B949E);
  static const Color textDisabled     = Color(0xFF484F58);
  static const Color textOnPrimary    = Colors.white;

  // ── Connection indicators ──────────────────────────────────────────────────
  static const Color connected        = Color(0xFF4CAF50);
  static const Color disconnected     = Color(0xFF9E9E9E);
  static const Color connecting       = Color(0xFFFFC107);
}
