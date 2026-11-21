import 'package:flutter/material.dart';

/// The product name exactly as it appears in the logo artwork. Never
/// translated, never suffixed.
const brandLogoLabel = 'BALKAVACH';

/// The BALKAVACH logo (panda, children and wordmark). It is a square image on
/// a white background, so it is shown as a rounded white card on any theme.
const brandLogoAsset = 'assets/images/logo.jpeg';

/// The BALKAVACH logo, square.
class BrandLogo extends StatelessWidget {
  const BrandLogo({required this.size, super.key});

  final double size;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.16),
      child: Image.asset(
        brandLogoAsset,
        width: size,
        height: size,
        cacheWidth: (size * dpr).round(),
        fit: BoxFit.cover,
        semanticLabel: brandLogoLabel,
      ),
    );
  }
}
