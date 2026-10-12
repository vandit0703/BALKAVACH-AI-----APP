import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Bal Kavach shield + panda mark, drawn from the Stitch SVG
/// (`bal_kavach_shield_logo/code.html`, 160×160 viewBox).
class ShieldLogo extends StatelessWidget {
  const ShieldLogo({this.size = 40, this.semanticLabel, super.key});

  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final logo = SizedBox.square(
      dimension: size,
      child: const CustomPaint(painter: _ShieldPainter()),
    );
    if (semanticLabel == null) return ExcludeSemantics(child: logo);
    return Semantics(label: semanticLabel, image: true, child: logo);
  }
}

class _ShieldPainter extends CustomPainter {
  const _ShieldPainter();

  static const _navy = AppPalette.navy;
  static const _teal = Color(0xFF22B8A7);

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 160;
    canvas.scale(scale);

    final outer = Path()
      ..moveTo(80, 18)
      ..cubicTo(108, 18, 134, 26, 134, 26)
      ..lineTo(134, 74)
      ..cubicTo(134, 108, 108, 136, 80, 144)
      ..cubicTo(52, 136, 26, 108, 26, 74)
      ..lineTo(26, 26)
      ..cubicTo(26, 26, 52, 18, 80, 18)
      ..close();

    canvas.drawPath(
      outer.shift(const Offset(0, 6)),
      Paint()
        ..color = AppPalette.shieldShadow.withValues(alpha: 0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawPath(
      outer,
      Paint()
        ..shader = const LinearGradient(
          colors: [AppPalette.brightBlue, AppPalette.primaryContainer],
        ).createShader(const Rect.fromLTWH(20, 20, 120, 120)),
    );

    final inner = Path()
      ..moveTo(80, 24)
      ..cubicTo(104, 24, 126, 31, 126, 31)
      ..lineTo(126, 72)
      ..cubicTo(126, 102, 104, 128, 80, 136)
      ..cubicTo(56, 128, 34, 102, 34, 72)
      ..lineTo(34, 31)
      ..cubicTo(34, 31, 56, 24, 80, 24)
      ..close();
    canvas.drawPath(
      inner,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: 0.35),
    );

    final navy = Paint()..color = _navy;
    final light = Paint()..color = const Color(0xFFF4F8FF);
    final white = Paint()..color = Colors.white;

    // Ears.
    canvas
      ..drawCircle(const Offset(56, 56), 13, navy)
      ..drawCircle(const Offset(104, 56), 13, navy)
      ..drawCircle(const Offset(56, 56), 7, light)
      ..drawCircle(const Offset(104, 56), 7, light);
    // Face, eye patches, eyes.
    canvas
      ..drawOval(
        Rect.fromCenter(center: const Offset(80, 82), width: 68, height: 60),
        white,
      )
      ..drawOval(
        Rect.fromCenter(center: const Offset(66, 78), width: 16, height: 22),
        navy,
      )
      ..drawOval(
        Rect.fromCenter(center: const Offset(94, 78), width: 16, height: 22),
        navy,
      )
      ..drawCircle(const Offset(68, 76), 3.5, white)
      ..drawCircle(const Offset(96, 76), 3.5, white)
      ..drawOval(
        Rect.fromCenter(center: const Offset(80, 88), width: 11, height: 8),
        Paint()..color = _teal,
      );
    // Smile.
    canvas.drawPath(
      Path()
        ..moveTo(74, 94)
        ..cubicTo(76, 97, 84, 97, 86, 94),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..color = _navy,
    );
    // Sparkle.
    final star = Path()
      ..moveTo(120, 24)
      ..lineTo(123, 32)
      ..lineTo(131, 35)
      ..lineTo(123, 38)
      ..lineTo(120, 46)
      ..lineTo(117, 38)
      ..lineTo(109, 35)
      ..lineTo(117, 32)
      ..close();
    canvas.drawPath(
      star,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFE066), AppPalette.star],
        ).createShader(const Rect.fromLTWH(109, 24, 22, 22)),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
