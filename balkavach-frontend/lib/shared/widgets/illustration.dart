import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../models/app_assets.dart';

/// Rounded bundled illustration, decoded at the size it is shown.
class Illustration extends StatelessWidget {
  const Illustration({
    required this.asset,
    this.aspectRatio = 16 / 9,
    this.borderRadius = const BorderRadius.all(Radius.circular(24)),
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.semanticLabel,
    super.key,
  });

  final String asset;
  final double aspectRatio;
  final BorderRadius borderRadius;
  final BoxFit fit;
  final Alignment alignment;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: aspectRatio,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final dpr = MediaQuery.devicePixelRatioOf(context);
          final width = constraints.maxWidth.isFinite
              ? (constraints.maxWidth * dpr).round()
              : null;
          return ClipRRect(
            borderRadius: borderRadius,
            child: Image.asset(
              asset,
              fit: fit,
              alignment: alignment,
              cacheWidth: width,
              semanticLabel: semanticLabel,
              excludeFromSemantics: semanticLabel == null,
              errorBuilder: (context, error, stackTrace) =>
                  ColoredBox(color: context.colors.surfaceContainerHigh),
            ),
          );
        },
      ),
    );
  }
}

/// Circular avatar from the device-local avatar choice, falling back to the
/// child's initial.
class ChildAvatar extends StatelessWidget {
  const ChildAvatar({
    required this.name,
    this.option,
    this.size = 48,
    this.ring = true,
    super.key,
  });

  final String name;
  final ChildAvatarOption? option;
  final double size;
  final bool ring;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    final Widget face = option == null
        ? ColoredBox(
            color: colors.primaryFixed,
            child: Center(
              child: Text(
                initial,
                style: context.text.titleLarge?.copyWith(
                  color: colors.primary,
                  fontSize: size * 0.42,
                ),
              ),
            ),
          )
        : Image.asset(
            option!.asset,
            fit: BoxFit.cover,
            cacheWidth: (size * dpr).round(),
            excludeFromSemantics: true,
          );
    return Semantics(
      label: name,
      image: true,
      child: Container(
        width: size,
        height: size,
        padding: ring ? EdgeInsets.all(size * 0.05) : EdgeInsets.zero,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: ring ? colors.primary.withValues(alpha: 0.15) : null,
        ),
        child: ClipOval(child: SizedBox.expand(child: face)),
      ),
    );
  }
}
