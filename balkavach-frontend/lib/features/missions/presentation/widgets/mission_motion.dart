import 'package:flutter/material.dart';

/// Small, one-shot animations for the mission screens. Each one shows its
/// final state immediately when the system asks for reduced motion
/// (`MediaQuery.disableAnimations`), and none of them repeats, so they never
/// keep a screen busy or delay a tap.

bool reduceMotion(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// Fades and lifts [child] in once, after a short [index]-based stagger.
class EntranceFade extends StatelessWidget {
  const EntranceFade({required this.child, this.index = 0, super.key});

  final Widget child;

  /// Position in a list; later items start slightly later (capped).
  final int index;

  @override
  Widget build(BuildContext context) {
    if (reduceMotion(context)) return child;
    final delay = (index.clamp(0, 6)) * 0.08;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 360 + (delay * 1000).round()),
      curve: Interval(delay / (0.36 + delay), 1, curve: Curves.easeOutCubic),
      child: child,
      builder: (context, t, child) => Opacity(
        opacity: t,
        // Vertical only, so the final layout (and every hit area) is exact.
        child: Transform.translate(
          offset: Offset(0, (1 - t) * 14),
          child: child,
        ),
      ),
    );
  }
}

/// A rounded progress bar that fills from 0 to [value] once.
class AnimatedPillProgress extends StatelessWidget {
  const AnimatedPillProgress({
    required this.value,
    required this.color,
    required this.background,
    this.height = 12,
    this.semanticsLabel,
    super.key,
  });

  final double value;
  final Color color;
  final Color background;
  final double height;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final target = value.clamp(0.0, 1.0);
    Widget bar(double v) => ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: LinearProgressIndicator(
        value: v,
        minHeight: height,
        color: color,
        backgroundColor: background,
        semanticsLabel: semanticsLabel,
      ),
    );
    if (reduceMotion(context)) return bar(target);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: target),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => bar(v),
    );
  }
}

/// Pops [child] in with a small overshoot: the "well done" moment.
class CelebrationPop extends StatelessWidget {
  const CelebrationPop({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (reduceMotion(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.6, end: 1),
      duration: const Duration(milliseconds: 650),
      curve: Curves.elasticOut,
      child: child,
      builder: (context, scale, child) =>
          Transform.scale(scale: scale, child: child),
    );
  }
}
