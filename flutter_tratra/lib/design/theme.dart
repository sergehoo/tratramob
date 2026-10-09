// Thème Material 3 adapté à la marque Tratra (miroir de la landing web).
// Les valeurs viennent exclusivement de tokens.dart (généré depuis tokens.json).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tokens.dart';

abstract final class TratraTheme {
  /// Style de texte construit depuis une spécification de jeton (mobile = tailles compactes).
  /// Polices EMBARQUÉES (assets/fonts, licence SIL OFL) : aucun téléchargement à l'exécution,
  /// rendu identique hors ligne. Montserrat est une police variable : l'axe `wght` porte la graisse.
  static TextStyle style(TtTextSpec s, {Color color = TtColors.ink}) {
    return TextStyle(
      fontFamily: s.display ? TtFont.display : TtFont.body,
      fontVariations: s.display ? [FontVariation('wght', s.weight.value.toDouble())] : null,
      fontSize: s.sizeMobile,
      height: s.line,
      fontWeight: s.weight,
      letterSpacing: s.tracking * s.sizeMobile,
      color: color,
    );
  }

  static TextTheme textTheme() {
    return TextTheme(
      displayLarge: style(TtType.displayXl),
      displayMedium: style(TtType.displayLg),
      displaySmall: style(TtType.h1),
      headlineLarge: style(TtType.h1),
      headlineMedium: style(TtType.h2),
      headlineSmall: style(TtType.h3),
      titleLarge: style(TtType.h2),
      titleMedium: style(TtType.title),
      titleSmall: style(TtType.title).copyWith(fontSize: 14),
      bodyLarge: style(TtType.bodyLg),
      bodyMedium: style(TtType.body),
      bodySmall: style(TtType.bodySm, color: TtColors.ash),
      labelLarge: style(TtType.button),
      labelMedium: style(TtType.caption, color: TtColors.inkSoft),
      labelSmall: style(TtType.eyebrow, color: TtColors.ash),
    );
  }

  /// Texte blanc posé uniquement sur primaryDark / night (contraste AA) ; le vert
  /// `primary` reste décoratif — comme sur le web.
  static ColorScheme colorScheme() => const ColorScheme(
        brightness: Brightness.light,
        primary: TtColors.primaryDark,
        onPrimary: Colors.white,
        primaryContainer: TtColors.primarySoft,
        onPrimaryContainer: TtColors.primaryDeep,
        secondary: TtColors.accent,
        onSecondary: TtColors.ink,
        secondaryContainer: TtColors.accentSoft,
        onSecondaryContainer: TtColors.ink,
        tertiary: TtColors.night,
        onTertiary: Colors.white,
        tertiaryContainer: TtColors.nightSoft,
        onTertiaryContainer: Colors.white,
        error: TtColors.danger,
        onError: Colors.white,
        errorContainer: TtColors.dangerSoft,
        onErrorContainer: TtColors.dangerInk,
        surface: TtColors.surface,
        onSurface: TtColors.ink,
        onSurfaceVariant: TtColors.ash,
        surfaceTint: Colors.transparent,
        surfaceContainerLowest: TtColors.surface,
        surfaceContainerLow: TtColors.canvas,
        surfaceContainer: TtColors.canvas,
        surfaceContainerHigh: TtColors.lineSoft,
        surfaceContainerHighest: TtColors.line,
        outline: TtColors.fog,
        outlineVariant: TtColors.line,
        shadow: TtColors.ink,
        scrim: TtColors.night,
        inverseSurface: TtColors.night,
        onInverseSurface: Colors.white,
        inversePrimary: TtColors.accent,
      );

  static OutlineInputBorder _border(Color color, {double width = 1}) => OutlineInputBorder(
        borderRadius: TtRadius.controlAll,
        borderSide: BorderSide(color: color, width: width),
      );

  static ThemeData light() {
    final scheme = colorScheme();
    final text = textTheme();
    const stadium = StadiumBorder();
    final buttonText = style(TtType.button, color: Colors.white);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      textTheme: text,
      primaryTextTheme: text,
      scaffoldBackgroundColor: TtColors.canvas,
      canvasColor: TtColors.surface,
      splashFactory: InkSparkle.splashFactory,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      dividerColor: TtColors.lineSoft,
      dividerTheme: const DividerThemeData(color: TtColors.lineSoft, thickness: 1, space: 1),
      appBarTheme: AppBarTheme(
        backgroundColor: TtColors.surface,
        foregroundColor: TtColors.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        toolbarHeight: TtLayout.topbarHeight,
        iconTheme: const IconThemeData(color: TtColors.ink),
        titleTextStyle: style(TtType.h3),
        systemOverlayStyle: SystemUiOverlayStyle.dark,
      ),
      cardTheme: CardThemeData(
        color: TtColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: TtRadius.cardAll,
          side: const BorderSide(color: TtColors.lineSoft),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: TtColors.primaryDark,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          shape: stadium,
          textStyle: buttonText,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: TtColors.primaryDark,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          shape: stadium,
          textStyle: buttonText,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: TtColors.ink,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          side: const BorderSide(color: TtColors.line),
          shape: stadium,
          textStyle: buttonText.copyWith(color: TtColors.ink),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: TtColors.primaryDark,
          minimumSize: const Size(0, 44),
          shape: stadium,
          textStyle: buttonText.copyWith(color: TtColors.primaryDark),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: TtColors.accent,
        foregroundColor: TtColors.ink,
        elevation: 0,
        highlightElevation: 0,
        shape: const StadiumBorder(),
        extendedTextStyle: style(TtType.button, color: TtColors.ink),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: TtColors.ink,
          minimumSize: const Size(TtLayout.touchTarget, TtLayout.touchTarget),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: TtColors.surface,
        isDense: false,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: style(TtType.body, color: TtColors.fog),
        labelStyle: style(TtType.body, color: TtColors.ash),
        floatingLabelStyle: style(TtType.bodySm, color: TtColors.primaryDark),
        errorStyle: style(TtType.caption, color: TtColors.dangerInk),
        helperStyle: style(TtType.caption, color: TtColors.ash),
        prefixIconColor: TtColors.fog,
        suffixIconColor: TtColors.ash,
        border: _border(TtColors.line),
        enabledBorder: _border(TtColors.line),
        focusedBorder: _border(TtColors.primary, width: 1.6),
        errorBorder: _border(TtColors.danger),
        focusedErrorBorder: _border(TtColors.danger, width: 1.6),
        disabledBorder: _border(TtColors.lineSoft),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: TtColors.surface,
        selectedColor: TtColors.primarySoft,
        disabledColor: TtColors.lineSoft,
        side: const BorderSide(color: TtColors.line),
        shape: const StadiumBorder(),
        labelStyle: style(TtType.bodySm, color: TtColors.inkSoft).copyWith(fontWeight: FontWeight.w600),
        secondaryLabelStyle: style(TtType.bodySm, color: TtColors.primaryDark).copyWith(fontWeight: FontWeight.w600),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        showCheckmark: false,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: TtColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: TtRadius.cardAll),
        titleTextStyle: style(TtType.h3),
        contentTextStyle: style(TtType.body, color: TtColors.inkSoft),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: TtColors.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: TtColors.line,
        modalBackgroundColor: TtColors.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(TtRadius.sheet)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: TtColors.night,
        contentTextStyle: style(TtType.bodySm, color: Colors.white),
        actionTextColor: TtColors.accent,
        shape: RoundedRectangleBorder(borderRadius: TtRadius.panelAll),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: TtColors.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: TtColors.primarySoft,
        elevation: 0,
        height: TtLayout.bottomNavHeight,
        labelTextStyle: WidgetStateProperty.resolveWith((states) => style(TtType.caption).copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: states.contains(WidgetState.selected) ? TtColors.primaryDark : TtColors.ash,
            )),
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
              size: 22,
              color: states.contains(WidgetState.selected) ? TtColors.primaryDark : TtColors.ash,
            )),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: TtColors.primaryDark,
        unselectedLabelColor: TtColors.ash,
        indicatorColor: TtColors.accent,
        dividerColor: TtColors.lineSoft,
        labelStyle: style(TtType.title).copyWith(fontSize: 14),
        unselectedLabelStyle: style(TtType.title).copyWith(fontSize: 14, fontWeight: FontWeight.w500),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: TtColors.primary,
        linearTrackColor: TtColors.lineSoft,
        circularTrackColor: TtColors.lineSoft,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? Colors.white : TtColors.fog),
        trackColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? TtColors.primaryDark : TtColors.lineSoft),
        trackOutlineColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? TtColors.primaryDark : TtColors.line),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        side: const BorderSide(color: TtColors.fog, width: 1.5),
        fillColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? TtColors.primaryDark : Colors.transparent),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? TtColors.primaryDark : TtColors.fog),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: TtColors.inkSoft,
        titleTextStyle: style(TtType.title),
        subtitleTextStyle: style(TtType.bodySm, color: TtColors.ash),
        shape: RoundedRectangleBorder(borderRadius: TtRadius.panelAll),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: TtColors.primaryDark,
        selectionColor: TtColors.accent.withValues(alpha: 0.45),
        selectionHandleColor: TtColors.primaryDark,
      ),
    );
  }
}
