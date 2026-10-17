import 'package:flutter/material.dart';

/// Design tokens mirrored from the Bal Kavach app
/// (`balkavach-frontend/lib/core/theme/app_colors.dart`), so the panel reads as
/// the same product. Keep the two in step when the palette changes.
abstract final class Palette {
  static const primary = Color(0xFF0051B6);
  static const primaryContainer = Color(0xFF1769E0);
  static const primaryFixed = Color(0xFFD9E2FF);
  static const secondary = Color(0xFF006A60);
  static const secondaryContainer = Color(0xFF75F8E5);
  static const onSecondaryContainer = Color(0xFF007166);
  static const tertiary = Color(0xFF6E5200);
  static const tertiaryFixed = Color(0xFFFFDF9C);
  static const onTertiaryFixed = Color(0xFF251A00);
  static const error = Color(0xFFBA1A1A);
  static const errorContainer = Color(0xFFFFDAD6);
  static const onErrorContainer = Color(0xFF93000A);
  static const surface = Color(0xFFF9F9FF);
  static const surfaceContainerLowest = Color(0xFFFFFFFF);
  static const surfaceContainerLow = Color(0xFFF1F3FF);
  static const surfaceContainer = Color(0xFFE8EDFF);
  static const surfaceContainerHigh = Color(0xFFE0E8FF);
  static const surfaceContainerHighest = Color(0xFFD7E2FF);
  static const onSurface = Color(0xFF041B3C);
  static const onSurfaceVariant = Color(0xFF424754);
  static const outline = Color(0xFF727785);
  static const outlineVariant = Color(0xFFC2C6D6);
  static const success = Color(0xFF20B26B);
}

abstract final class Fonts {
  static const headline = 'Rubik';
  static const body = 'NunitoSans';
}

const adminColorScheme = ColorScheme(
  brightness: Brightness.light,
  primary: Palette.primary,
  onPrimary: Colors.white,
  primaryContainer: Palette.primaryContainer,
  onPrimaryContainer: Color(0xFFF0F2FF),
  primaryFixed: Palette.primaryFixed,
  primaryFixedDim: Color(0xFFAFC6FF),
  inversePrimary: Color(0xFFAFC6FF),
  secondary: Palette.secondary,
  onSecondary: Colors.white,
  secondaryContainer: Palette.secondaryContainer,
  onSecondaryContainer: Palette.onSecondaryContainer,
  tertiary: Palette.tertiary,
  onTertiary: Colors.white,
  tertiaryContainer: Color(0xFF8C6900),
  onTertiaryContainer: Color(0xFFFFF1D9),
  tertiaryFixed: Palette.tertiaryFixed,
  tertiaryFixedDim: Color(0xFFF5BF34),
  onTertiaryFixed: Palette.onTertiaryFixed,
  error: Palette.error,
  onError: Colors.white,
  errorContainer: Palette.errorContainer,
  onErrorContainer: Palette.onErrorContainer,
  surface: Palette.surface,
  surfaceDim: Color(0xFFCADAFF),
  surfaceBright: Palette.surface,
  surfaceContainerLowest: Palette.surfaceContainerLowest,
  surfaceContainerLow: Palette.surfaceContainerLow,
  surfaceContainer: Palette.surfaceContainer,
  surfaceContainerHigh: Palette.surfaceContainerHigh,
  surfaceContainerHighest: Palette.surfaceContainerHighest,
  onSurface: Palette.onSurface,
  onSurfaceVariant: Palette.onSurfaceVariant,
  inverseSurface: Color(0xFF1D3052),
  onInverseSurface: Color(0xFFEDF0FF),
  outline: Palette.outline,
  outlineVariant: Palette.outlineVariant,
  surfaceTint: Color(0xFF0059C7),
);

TextStyle _rubik(double size, double height, FontWeight weight) => TextStyle(
  fontFamily: Fonts.headline,
  fontSize: size,
  height: height / size,
  fontWeight: weight,
  color: Palette.onSurface,
);

TextStyle _nunito(double size, double height, FontWeight weight) => TextStyle(
  fontFamily: Fonts.body,
  fontSize: size,
  height: height / size,
  fontWeight: weight,
  color: Palette.onSurface,
);

/// Same scale as the app, one step denser where a console needs it.
final adminTextTheme = TextTheme(
  headlineLarge: _rubik(30, 38, FontWeight.w600),
  headlineMedium: _rubik(24, 32, FontWeight.w600),
  headlineSmall: _rubik(22, 30, FontWeight.w600),
  titleLarge: _rubik(18, 26, FontWeight.w600),
  titleMedium: _rubik(16, 22, FontWeight.w600),
  titleSmall: _rubik(14, 20, FontWeight.w600),
  labelLarge: _rubik(14, 20, FontWeight.w500),
  labelMedium: _rubik(13, 18, FontWeight.w500),
  labelSmall: _rubik(11, 14, FontWeight.w600),
  bodyLarge: _nunito(16, 24, FontWeight.w400),
  bodyMedium: _nunito(14, 20, FontWeight.w400),
  bodySmall: _nunito(12, 16, FontWeight.w400),
);

const kCardRadius = BorderRadius.all(Radius.circular(16));
const kInputRadius = BorderRadius.all(Radius.circular(12));

ThemeData buildAdminTheme() {
  const scheme = adminColorScheme;
  final text = adminTextTheme;
  const buttonShape = WidgetStatePropertyAll<OutlinedBorder>(StadiumBorder());
  final buttonText = WidgetStatePropertyAll(
    text.labelLarge!.copyWith(fontWeight: FontWeight.w600),
  );
  const buttonSize = WidgetStatePropertyAll(Size(64, 44));

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    fontFamily: Fonts.body,
    textTheme: text,
    visualDensity: VisualDensity.standard,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surfaceContainerLowest,
      surfaceTintColor: Colors.transparent,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: text.titleLarge,
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainerLowest,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: kCardRadius,
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        shape: buttonShape,
        textStyle: buttonText,
        minimumSize: buttonSize,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        shape: buttonShape,
        textStyle: buttonText,
        minimumSize: buttonSize,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        shape: buttonShape,
        textStyle: buttonText,
        minimumSize: const WidgetStatePropertyAll(Size(48, 40)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerLow,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: const OutlineInputBorder(
        borderRadius: kInputRadius,
        borderSide: BorderSide.none,
      ),
      enabledBorder: const OutlineInputBorder(
        borderRadius: kInputRadius,
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: kInputRadius,
        borderSide: BorderSide(color: scheme.primaryContainer, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: kInputRadius,
        borderSide: BorderSide(color: scheme.error, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: kInputRadius,
        borderSide: BorderSide(color: scheme.error, width: 2),
      ),
      labelStyle: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
      floatingLabelStyle: text.labelLarge?.copyWith(color: scheme.primary),
      errorStyle: text.bodySmall?.copyWith(color: scheme.error),
      errorMaxLines: 3,
      helperMaxLines: 3,
    ),
    dataTableTheme: DataTableThemeData(
      headingTextStyle: text.labelMedium?.copyWith(
        color: scheme.onSurfaceVariant,
        fontWeight: FontWeight.w600,
      ),
      headingRowColor: WidgetStatePropertyAll(scheme.surfaceContainerLow),
      dataTextStyle: text.bodyMedium,
      dividerThickness: 0.6,
      columnSpacing: 24,
      horizontalMargin: 16,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerLowest,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: kCardRadius),
      titleTextStyle: text.headlineSmall,
      contentTextStyle: text.bodyLarge,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: text.bodyMedium?.copyWith(
        color: scheme.onInverseSurface,
      ),
      shape: const RoundedRectangleBorder(borderRadius: kInputRadius),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        textStyle: buttonText,
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Palette.primaryFixed
              : null,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? Palette.primary : null,
        ),
      ),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary),
  );
}
