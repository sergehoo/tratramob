// core/theme.dart
//
// Façade de compatibilité : le thème de la marque vit désormais dans le Design System
// (lib/design). Les nouveaux écrans utilisent directement `TtColors`, `TratraTheme`
// et les widgets `Tratra*` ; ces constantes ne servent qu'aux anciens appels.
import 'package:flutter/material.dart';

import 'package:flutter_tratra/design/design.dart';

class AppTheme {
  static const Color primaryColor = TtColors.primary;
  static const Color primaryLight = TtColors.primarySoft;
  static const Color accentColor = TtColors.accent;
  static const Color backgroundColor = TtColors.canvas;
  static const Color textPrimary = TtColors.ink;
  static const Color textSecondary = TtColors.ash;
  static const Color white = TtColors.surface;
  static const Color borderColor = TtColors.line;

  static ThemeData get lightTheme => TratraTheme.light();
}
