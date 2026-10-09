// GÉNÉRÉ par frontend/design-system/build.mjs depuis tokens.json (dépôt tratra).
// Ne pas éditer à la main : modifier tokens.json puis relancer `npm run ds:build`.
// ignore_for_file: constant_identifier_names
import 'package:flutter/material.dart';

/// Couleurs de marque, neutres et sémantiques (miroir de la landing web).
abstract final class TtColors {
  static const Color primary = Color(0xff2E8B57);
  static const Color primaryDark = Color(0xff1F6A41);
  static const Color primaryDeep = Color(0xff185736);
  static const Color primarySoft = Color(0xffE8F6EE);
  static const Color accent = Color(0xffF6C90E);
  static const Color accentBright = Color(0xffFFD42E);
  static const Color accentDark = Color(0xffD4AA00);
  static const Color accentSoft = Color(0xffFFF8D6);
  static const Color night = Color(0xff0B1210);
  static const Color nightSoft = Color(0xff15201B);
  static const Color ink = Color(0xff0F172A);
  static const Color inkSoft = Color(0xff475569);
  static const Color ash = Color(0xff6B7280);
  static const Color fog = Color(0xff94A3B8);
  static const Color line = Color(0xffE2E8F0);
  static const Color lineSoft = Color(0xffF1F5F9);
  static const Color canvas = Color(0xffF8FAFC);
  static const Color surface = Color(0xffFFFFFF);
  static const Color success = Color(0xff059669);
  static const Color successSoft = Color(0xffECFDF5);
  static const Color successInk = Color(0xff047857);
  static const Color warning = Color(0xffD97706);
  static const Color warningSoft = Color(0xffFFFBEB);
  static const Color warningInk = Color(0xff92400E);
  static const Color danger = Color(0xffDC2626);
  static const Color dangerSoft = Color(0xffFEF2F2);
  static const Color dangerInk = Color(0xffB91C1C);
  static const Color info = Color(0xff0284C7);
  static const Color infoSoft = Color(0xffF0F9FF);
  static const Color infoInk = Color(0xff075985);
}

/// Dégradés de marque.
abstract final class TtGradients {
  static const LinearGradient brand = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xff2E8B57), Color(0xff1F6A41)],
  );
  static const LinearGradient night = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xff0B1210), Color(0xff15201B)],
  );
  static const LinearGradient accent = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xffF6C90E), Color(0xffFFD42E)],
  );
  static const LinearGradient wash = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xffE8F6EE), Color(0xffFFFFFF)],
  );
}

/// Échelle d'espacement (base 4 dp).
abstract final class TtSpace {
  static const double s1 = 4;
  static const double s2 = 8;
  static const double s3 = 12;
  static const double s4 = 16;
  static const double s5 = 20;
  static const double s6 = 24;
  static const double s8 = 32;
  static const double s10 = 40;
  static const double s12 = 48;
  static const double s16 = 64;
  static const double s20 = 80;
  static const double s28 = 112;
}

/// Rayons : control (champs/boutons carrés), panel, card, sheet, pill.
abstract final class TtRadius {
  static const double sm = 8;
  static const double control = 12;
  static const double panel = 16;
  static const double card = 24;
  static const double sheet = 28;
  static const double pill = 9999;
  static BorderRadius get smAll => BorderRadius.circular(sm);
  static BorderRadius get controlAll => BorderRadius.circular(control);
  static BorderRadius get panelAll => BorderRadius.circular(panel);
  static BorderRadius get cardAll => BorderRadius.circular(card);
  static BorderRadius get sheetAll => BorderRadius.circular(sheet);
  static BorderRadius get pillAll => BorderRadius.circular(pill);
}

/// Ombres (équivalents des shadow-* Tailwind).
abstract final class TtShadows {
  static const List<BoxShadow> hair = [
    BoxShadow(color: Color(0x0f0F172A), offset: Offset(0, 1), blurRadius: 2, spreadRadius: 0),
  ];
  static const List<BoxShadow> soft = [
    BoxShadow(color: Color(0x140F172A), offset: Offset(0, 8), blurRadius: 24, spreadRadius: 0),
  ];
  static const List<BoxShadow> strong = [
    BoxShadow(color: Color(0x1f0F172A), offset: Offset(0, 16), blurRadius: 48, spreadRadius: 0),
  ];
  static const List<BoxShadow> glow = [
    BoxShadow(color: Color(0x592E8B57), offset: Offset(0, 12), blurRadius: 40, spreadRadius: 0),
  ];
  static const List<BoxShadow> glowAccent = [
    BoxShadow(color: Color(0x8cF6C90E), offset: Offset(0, 12), blurRadius: 32, spreadRadius: -8),
  ];
}

/// Durées et courbes d'animation.
abstract final class TtMotion {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration base = Duration(milliseconds: 220);
  static const Duration slow = Duration(milliseconds: 420);
  static const Duration hero = Duration(milliseconds: 900);
  static const Curve emphasized = Cubic(0.22, 1, 0.36, 1);
  static const Curve standard = Cubic(0.4, 0, 0.2, 1);
}

/// Mesures de mise en page.
abstract final class TtLayout {
  static const double containerMax = 1280;
  static const double gutterMobile = 16;
  static const double gutterDesktop = 24;
  static const double touchTarget = 44;
  static const double controlHeight = 48;
  static const double sidebarWidth = 256;
  static const double topbarHeight = 64;
  static const double bottomNavHeight = 64;
  /// Classes de fenêtre Material 3 : compact < 600, medium < 840, sinon expanded.
  static const double compactMax = 600;
  static const double mediumMax = 840;
}

/// Familles typographiques de la marque.
abstract final class TtFont {
  static const String display = 'Montserrat';
  static const String body = 'Poppins';
}

/// Spécification d'un style de texte (taille desktop/mobile, interligne, graisse, crénage en em).
class TtTextSpec {
  const TtTextSpec({
    required this.display,
    required this.size,
    required this.sizeMobile,
    required this.line,
    required this.weight,
    required this.tracking,
  });
  final bool display;
  final double size;
  final double sizeMobile;
  final double line;
  final FontWeight weight;
  final double tracking;
}

/// Échelle typographique (même nomenclature que tokens.json).
abstract final class TtType {
  static const TtTextSpec displayXl = TtTextSpec(display: true, size: 64, sizeMobile: 36, line: 1.05, weight: FontWeight.w800, tracking: -0.02);
  static const TtTextSpec displayLg = TtTextSpec(display: true, size: 44, sizeMobile: 30, line: 1.1, weight: FontWeight.w800, tracking: -0.015);
  static const TtTextSpec h1 = TtTextSpec(display: true, size: 32, sizeMobile: 26, line: 1.15, weight: FontWeight.w800, tracking: -0.01);
  static const TtTextSpec h2 = TtTextSpec(display: true, size: 24, sizeMobile: 21, line: 1.2, weight: FontWeight.w700, tracking: -0.005);
  static const TtTextSpec h3 = TtTextSpec(display: true, size: 19, sizeMobile: 18, line: 1.25, weight: FontWeight.w700, tracking: 0);
  static const TtTextSpec title = TtTextSpec(display: false, size: 16, sizeMobile: 16, line: 1.4, weight: FontWeight.w600, tracking: 0);
  static const TtTextSpec bodyLg = TtTextSpec(display: false, size: 18, sizeMobile: 16, line: 1.6, weight: FontWeight.w400, tracking: 0);
  static const TtTextSpec body = TtTextSpec(display: false, size: 15, sizeMobile: 15, line: 1.6, weight: FontWeight.w400, tracking: 0);
  static const TtTextSpec bodySm = TtTextSpec(display: false, size: 13, sizeMobile: 13, line: 1.5, weight: FontWeight.w400, tracking: 0);
  static const TtTextSpec caption = TtTextSpec(display: false, size: 12, sizeMobile: 12, line: 1.4, weight: FontWeight.w500, tracking: 0);
  static const TtTextSpec eyebrow = TtTextSpec(display: false, size: 11, sizeMobile: 11, line: 1.2, weight: FontWeight.w700, tracking: 0.16);
  static const TtTextSpec button = TtTextSpec(display: false, size: 15, sizeMobile: 15, line: 1.2, weight: FontWeight.w600, tracking: 0);
}
