import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/brand_logo.dart';

/// Shown while the stored session is restored; the router leaves it
/// automatically.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Scrolls instead of overflowing on very short windows.
      body: LayoutBuilder(
        builder: (context, constraints) {
          // ~62% of the width, never taller than ~60% of the window, and
          // between 140 and 300 logical pixels.
          final side = (constraints.maxWidth * 0.62)
              .clamp(0.0, constraints.maxHeight * 0.6)
              .clamp(140.0, 300.0);
          return Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  BrandLogo(size: side),
                  const SizedBox(height: AppSpacing.lg),
                  const SizedBox.square(
                    dimension: 28,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
