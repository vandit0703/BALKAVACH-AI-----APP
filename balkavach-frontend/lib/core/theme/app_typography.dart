import 'package:flutter/material.dart';

import 'app_colors.dart';

abstract final class AppFonts {
  static const headline = 'Rubik';
  static const body = 'NunitoSans';
}

TextStyle _rubik(
  double size,
  double height,
  FontWeight weight, {
  double? tracking,
}) => TextStyle(
  fontFamily: AppFonts.headline,
  fontSize: size,
  height: height / size,
  fontWeight: weight,
  letterSpacing: tracking == null ? null : tracking * size,
  color: AppPalette.onSurface,
);

TextStyle _nunito(double size, double height, FontWeight weight) => TextStyle(
  fontFamily: AppFonts.body,
  fontSize: size,
  height: height / size,
  fontWeight: weight,
  color: AppPalette.onSurface,
);

/// Stitch type scale mapped onto Material roles (see docs/design-system.md).
final appTextTheme = TextTheme(
  displayLarge: _rubik(44, 52, FontWeight.w700, tracking: -0.02),
  displayMedium: _rubik(38, 46, FontWeight.w700, tracking: -0.015),
  displaySmall: _rubik(34, 42, FontWeight.w700, tracking: -0.01),
  headlineLarge: _rubik(32, 40, FontWeight.w600),
  headlineMedium: _rubik(26, 34, FontWeight.w600),
  headlineSmall: _rubik(22, 30, FontWeight.w600),
  titleLarge: _rubik(18, 26, FontWeight.w600),
  titleMedium: _rubik(16, 22, FontWeight.w600),
  titleSmall: _rubik(14, 20, FontWeight.w600),
  labelLarge: _rubik(15, 20, FontWeight.w500),
  labelMedium: _rubik(13, 18, FontWeight.w500),
  labelSmall: _rubik(11, 14, FontWeight.w600, tracking: 0.04),
  bodyLarge: _nunito(16, 24, FontWeight.w400),
  bodyMedium: _nunito(14, 20, FontWeight.w400),
  bodySmall: _nunito(12, 16, FontWeight.w400),
);
