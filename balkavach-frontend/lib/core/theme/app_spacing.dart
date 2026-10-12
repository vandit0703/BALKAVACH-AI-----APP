import 'package:flutter/material.dart';

/// 4/8 px rhythm from DESIGN.md.
abstract final class AppSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const xxl = 48.0;

  static const marginCompact = 16.0;
  static const marginWide = 24.0;
}

abstract final class AppRadius {
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const pill = 999.0;

  static const card = BorderRadius.all(Radius.circular(lg));
  static const input = BorderRadius.all(Radius.circular(md));
  static const hero = BorderRadius.all(Radius.circular(xl));
}

/// Blue-tinted ambient shadows (never grey drop shadows).
abstract final class AppShadows {
  static const tier1 = [
    BoxShadow(
      color: Color(0x141769E0), // rgba(23,105,224,.08)
      offset: Offset(0, 4),
      blurRadius: 16,
      spreadRadius: -2,
    ),
  ];

  static const tier2 = [
    BoxShadow(
      color: Color(0x291769E0), // rgba(23,105,224,.16)
      offset: Offset(0, 8),
      blurRadius: 24,
      spreadRadius: -4,
    ),
  ];
}

/// Minimum tap targets: parent mode 48, child mode 56 (DESIGN.md).
abstract final class AppTouch {
  static const parentMin = 48.0;
  static const childMin = 56.0;
}
