import 'package:flutter/material.dart';

/// Raw palette from the Stitch Tailwind config (`bal_kavach_safe/DESIGN.md`).
abstract final class AppPalette {
  static const primary = Color(0xFF0051B6);
  static const onPrimary = Color(0xFFFFFFFF);
  static const primaryContainer = Color(0xFF1769E0);
  static const onPrimaryContainer = Color(0xFFF0F2FF);
  static const primaryFixed = Color(0xFFD9E2FF);
  static const primaryFixedDim = Color(0xFFAFC6FF);
  static const inversePrimary = Color(0xFFAFC6FF);

  static const secondary = Color(0xFF006A60);
  static const onSecondary = Color(0xFFFFFFFF);
  static const secondaryContainer = Color(0xFF75F8E5);
  static const onSecondaryContainer = Color(0xFF007166);

  static const tertiary = Color(0xFF6E5200);
  static const onTertiary = Color(0xFFFFFFFF);
  static const tertiaryContainer = Color(0xFF8C6900);
  static const onTertiaryContainer = Color(0xFFFFF1D9);
  static const tertiaryFixed = Color(0xFFFFDF9C);
  static const tertiaryFixedDim = Color(0xFFF5BF34);
  static const onTertiaryFixed = Color(0xFF251A00);

  static const error = Color(0xFFBA1A1A);
  static const onError = Color(0xFFFFFFFF);
  static const errorContainer = Color(0xFFFFDAD6);
  static const onErrorContainer = Color(0xFF93000A);

  static const surface = Color(0xFFF9F9FF);
  static const surfaceDim = Color(0xFFCADAFF);
  static const surfaceContainerLowest = Color(0xFFFFFFFF);
  static const surfaceContainerLow = Color(0xFFF1F3FF);
  static const surfaceContainer = Color(0xFFE8EDFF);
  static const surfaceContainerHigh = Color(0xFFE0E8FF);
  static const surfaceContainerHighest = Color(0xFFD7E2FF);
  static const onSurface = Color(0xFF041B3C);
  static const onSurfaceVariant = Color(0xFF424754);
  static const inverseSurface = Color(0xFF1D3052);
  static const onInverseSurface = Color(0xFFEDF0FF);
  static const outline = Color(0xFF727785);
  static const outlineVariant = Color(0xFFC2C6D6);

  // Semantic accents from DESIGN.md prose.
  static const success = Color(0xFF20B26B);
  static const star = Color(0xFFFFC83D);
  static const navy = Color(0xFF172B4D);
  static const brightBlue = Color(0xFF2587F7);
  static const shieldShadow = Color(0xFF1769E0);
}

const appColorScheme = ColorScheme(
  brightness: Brightness.light,
  primary: AppPalette.primary,
  onPrimary: AppPalette.onPrimary,
  primaryContainer: AppPalette.primaryContainer,
  onPrimaryContainer: AppPalette.onPrimaryContainer,
  primaryFixed: AppPalette.primaryFixed,
  primaryFixedDim: AppPalette.primaryFixedDim,
  inversePrimary: AppPalette.inversePrimary,
  secondary: AppPalette.secondary,
  onSecondary: AppPalette.onSecondary,
  secondaryContainer: AppPalette.secondaryContainer,
  onSecondaryContainer: AppPalette.onSecondaryContainer,
  tertiary: AppPalette.tertiary,
  onTertiary: AppPalette.onTertiary,
  tertiaryContainer: AppPalette.tertiaryContainer,
  onTertiaryContainer: AppPalette.onTertiaryContainer,
  tertiaryFixed: AppPalette.tertiaryFixed,
  tertiaryFixedDim: AppPalette.tertiaryFixedDim,
  onTertiaryFixed: AppPalette.onTertiaryFixed,
  error: AppPalette.error,
  onError: AppPalette.onError,
  errorContainer: AppPalette.errorContainer,
  onErrorContainer: AppPalette.onErrorContainer,
  surface: AppPalette.surface,
  surfaceDim: AppPalette.surfaceDim,
  surfaceBright: AppPalette.surface,
  surfaceContainerLowest: AppPalette.surfaceContainerLowest,
  surfaceContainerLow: AppPalette.surfaceContainerLow,
  surfaceContainer: AppPalette.surfaceContainer,
  surfaceContainerHigh: AppPalette.surfaceContainerHigh,
  surfaceContainerHighest: AppPalette.surfaceContainerHighest,
  onSurface: AppPalette.onSurface,
  onSurfaceVariant: AppPalette.onSurfaceVariant,
  inverseSurface: AppPalette.inverseSurface,
  onInverseSurface: AppPalette.onInverseSurface,
  outline: AppPalette.outline,
  outlineVariant: AppPalette.outlineVariant,
  surfaceTint: Color(0xFF0059C7),
  shadow: AppPalette.shieldShadow,
);

/// Brand tokens Material's [ColorScheme] has no slot for.
@immutable
class BalKavachColors extends ThemeExtension<BalKavachColors> {
  const BalKavachColors({
    required this.success,
    required this.star,
    required this.brandGradient,
    required this.learnTint,
    required this.moveTint,
    required this.helpTint,
    required this.createTint,
  });

  static const light = BalKavachColors(
    success: AppPalette.success,
    star: AppPalette.star,
    brandGradient: LinearGradient(
      colors: [
        AppPalette.primary,
        AppPalette.primaryContainer,
        AppPalette.secondary,
      ],
      stops: [0, 0.55, 1],
    ),
    learnTint: AppPalette.surfaceContainerHigh,
    moveTint: AppPalette.secondaryContainer,
    helpTint: AppPalette.tertiaryFixed,
    createTint: AppPalette.surfaceContainer,
  );

  final Color success;
  final Color star;
  final Gradient brandGradient;
  final Color learnTint;
  final Color moveTint;
  final Color helpTint;
  final Color createTint;

  @override
  BalKavachColors copyWith({
    Color? success,
    Color? star,
    Gradient? brandGradient,
    Color? learnTint,
    Color? moveTint,
    Color? helpTint,
    Color? createTint,
  }) => BalKavachColors(
    success: success ?? this.success,
    star: star ?? this.star,
    brandGradient: brandGradient ?? this.brandGradient,
    learnTint: learnTint ?? this.learnTint,
    moveTint: moveTint ?? this.moveTint,
    helpTint: helpTint ?? this.helpTint,
    createTint: createTint ?? this.createTint,
  );

  @override
  BalKavachColors lerp(BalKavachColors? other, double t) {
    if (other == null) return this;
    return BalKavachColors(
      success: Color.lerp(success, other.success, t)!,
      star: Color.lerp(star, other.star, t)!,
      brandGradient: Gradient.lerp(brandGradient, other.brandGradient, t)!,
      learnTint: Color.lerp(learnTint, other.learnTint, t)!,
      moveTint: Color.lerp(moveTint, other.moveTint, t)!,
      helpTint: Color.lerp(helpTint, other.helpTint, t)!,
      createTint: Color.lerp(createTint, other.createTint, t)!,
    );
  }
}

extension BalKavachThemeX on BuildContext {
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get text => Theme.of(this).textTheme;
  BalKavachColors get brand =>
      Theme.of(this).extension<BalKavachColors>() ?? BalKavachColors.light;
}
