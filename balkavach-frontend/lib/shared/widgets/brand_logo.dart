import 'package:flutter/material.dart';

/// The product name exactly as it appears in the logo artwork. Never
/// translated, never suffixed.
const brandLogoLabel = 'BALKAVACH';

/// Approved transparent BALKAVACH logo for light backgrounds.
const brandLogoAsset = 'assets/images/balkavach_logo_light.png';

/// The approved BALKAVACH logo (panda, children and wordmark), square.
class BrandLogo extends StatelessWidget {
  const BrandLogo({required this.size, super.key});

  final double size;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return Image.asset(
      brandLogoAsset,
      width: size,
      height: size,
      cacheWidth: (size * dpr).round(),
      fit: BoxFit.contain,
      semanticLabel: brandLogoLabel,
    );
  }
}
