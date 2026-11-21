import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../domain/panda_performer.dart';
import '../domain/viseme.dart';

/// Design size of the stage. Everything is drawn in these units and scaled.
const kPandaStageSize = Size(512, 279);

/// Palette taken from the existing Panda artwork (`assets/images/panda_hoodie.jpg`).
abstract final class _Ink {
  static const fur = Color(0xFFFFFFFF);
  static const furShade = Color(0xFFE6EBF5);
  static const black = Color(0xFF1B1B26);
  static const earInner = Color(0xFF3B3B4A);
  static const hoodie = Color(0xFF2B5FD9);
  static const hoodieDark = Color(0xFF1F47AE);
  static const hoodieLight = Color(0xFF4A7BEA);
  static const logo = Color(0xFFFFD54F);
  static const blush = Color(0xFFFF8FA3);
  static const nose = Color(0xFF22222E);
  static const brow = Color(0xFF3A3F52);
  static const mouthLine = Color(0xFF3A1F2B);
  static const mouthInside = Color(0xFF5A1F2E);
  static const tongue = Color(0xFFFF7A90);
  static const skyTop = Color(0xFFB7C6F4);
  static const skyMid = Color(0xFFD9CCF3);
  static const skyLow = Color(0xFFF7DDEB);
}

/// Paints Panda from separate layers, the way a 2D rig would: each part is
/// its own function that reads the performer's current numbers.
///
/// Layers, back to front: backdrop, legs and belly, hoodie, arms, ears, head,
/// cheeks, eye patches, eyes, brows, nose, mouth (one shape per viseme), and a
/// paw raised to the chin when thinking.
class PandaRigPainter extends CustomPainter {
  PandaRigPainter({required this.performer, super.repaint});

  final PandaPerformer performer;

  @override
  void paint(Canvas canvas, Size size) {
    final p = performer;
    final scale = math.min(
      size.width / kPandaStageSize.width,
      size.height / kPandaStageSize.height,
    );
    canvas
      ..save()
      ..translate(
        (size.width - kPandaStageSize.width * scale) / 2,
        (size.height - kPandaStageSize.height * scale) / 2,
      )
      ..scale(scale);

    _backdrop(canvas, p);
    final hop = p.hop;
    canvas.save();
    canvas.translate(0, -hop);
    _legsAndBelly(canvas, p);
    _hoodie(canvas, p);
    final chin = p.pose.armChin;
    _arms(canvas, p, chinInFront: false);
    _head(canvas, p);
    if (chin > 0.02) _arms(canvas, p, chinInFront: true);
    canvas.restore();
    if (p.pose.sleepy > 0.4) _sleepZs(canvas, p);
    canvas.restore();
  }

  @override
  bool shouldRepaint(PandaRigPainter old) => old.performer != performer;

  // ---- backdrop ------------------------------------------------------------

  void _backdrop(Canvas canvas, PandaPerformer p) {
    final rect = Offset.zero & kPandaStageSize;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
          rect.topCenter,
          rect.bottomCenter,
          [_Ink.skyTop, _Ink.skyMid, _Ink.skyLow],
          [0, 0.55, 1],
        ),
    );
    final soft = Paint()..color = Colors.white.withValues(alpha: 0.35);
    canvas
      ..drawOval(
        Rect.fromCenter(center: const Offset(70, 215), width: 190, height: 70),
        soft,
      )
      ..drawOval(
        Rect.fromCenter(center: const Offset(440, 222), width: 210, height: 80),
        soft,
      )
      ..drawOval(
        Rect.fromCenter(center: const Offset(256, 268), width: 250, height: 36),
        Paint()..color = Colors.white.withValues(alpha: 0.6),
      );
    // A few stars that twinkle slowly (still when reduced motion holds time).
    const stars = [
      Offset(120, 40),
      Offset(190, 70),
      Offset(350, 52),
      Offset(410, 95),
      Offset(70, 110),
      Offset(455, 150),
      Offset(300, 30),
      Offset(150, 150),
    ];
    for (var i = 0; i < stars.length; i++) {
      final twinkle = p.reduceMotion
          ? 0.7
          : 0.55 + 0.45 * math.sin(p.time * 1.6 + i * 1.7);
      canvas.drawCircle(
        stars[i],
        1.4 + (i % 3) * 0.5,
        Paint()..color = Colors.white.withValues(alpha: twinkle),
      );
    }
  }

  // ---- body ----------------------------------------------------------------

  void _legsAndBelly(Canvas canvas, PandaPerformer p) {
    final black = Paint()..color = _Ink.black;
    canvas
      ..drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: const Offset(236, 238),
            width: 28,
            height: 40,
          ),
          const Radius.circular(13),
        ),
        black,
      )
      ..drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: const Offset(276, 238),
            width: 28,
            height: 40,
          ),
          const Radius.circular(13),
        ),
        black,
      )
      ..drawOval(
        Rect.fromCenter(center: const Offset(234, 258), width: 36, height: 18),
        black,
      )
      ..drawOval(
        Rect.fromCenter(center: const Offset(278, 258), width: 36, height: 18),
        black,
      )
      ..drawOval(
        Rect.fromCenter(center: const Offset(256, 222), width: 84, height: 34),
        Paint()..color = _Ink.fur,
      );
  }

  void _hoodie(Canvas canvas, PandaPerformer p) {
    final lean = p.pose.lean;
    canvas.save();
    canvas.translate(256, 232);
    canvas.rotate(0.02 * lean);
    final breath = 1 + 0.012 * p.breath;
    canvas.scale(breath, breath);
    canvas.translate(-256, -232);

    final body = RRect.fromRectAndCorners(
      const Rect.fromLTRB(205, 150, 307, 236),
      topLeft: const Radius.circular(34),
      topRight: const Radius.circular(34),
      bottomLeft: const Radius.circular(26),
      bottomRight: const Radius.circular(26),
    );
    canvas.drawRRect(
      body,
      Paint()
        ..shader = ui.Gradient.linear(
          const Offset(205, 150),
          const Offset(307, 236),
          [_Ink.hoodieLight, _Ink.hoodie, _Ink.hoodieDark],
          [0, 0.45, 1],
        ),
    );
    // Hood collar behind the neck.
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(256, 152), width: 86, height: 24),
      Paint()..color = _Ink.hoodieDark,
    );
    // Pocket.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: const Offset(256, 212), width: 60, height: 24),
        const Radius.circular(10),
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = _Ink.hoodieDark,
    );
    // Drawstrings.
    final string = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    canvas
      ..drawLine(const Offset(245, 162), const Offset(243, 192), string)
      ..drawLine(const Offset(267, 162), const Offset(269, 190), string)
      ..drawCircle(const Offset(243, 194), 2.2, Paint()..color = Colors.white)
      ..drawCircle(const Offset(269, 192), 2.2, Paint()..color = Colors.white);
    // The "K" of the existing hoodie.
    final k = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = _Ink.logo;
    canvas.drawPath(
      Path()
        ..moveTo(274, 176)
        ..lineTo(274, 190)
        ..moveTo(286, 176)
        ..lineTo(274, 183)
        ..lineTo(286, 191),
      k,
    );
    canvas.restore();
  }

  void _arms(Canvas canvas, PandaPerformer p, {required bool chinInFront}) {
    final pose = p.pose;
    const shoulderL = Offset(213, 166);
    const shoulderR = Offset(299, 166);
    const restL = Offset(192, 208);
    const restR = Offset(320, 208);
    const upL = Offset(160, 120);
    const upR = Offset(354, 124);
    const chinR = Offset(272, 140);

    final wobble = Offset(math.sin(p.time * 9) * 7, 0);
    final waving = p.reduceMotion ? Offset.zero : wobble * pose.armWave;

    Offset mix(Offset rest, Offset target, double w) =>
        Offset.lerp(rest, target, w.clamp(0, 1))!;

    var pawR = restR;
    pawR = mix(pawR, upR + waving, pose.armWave);
    pawR = mix(pawR, upR, pose.armsUp);
    pawR = mix(pawR, chinR, pose.armChin);
    final pawL = mix(restL, upL, pose.armsUp);

    if (chinInFront) {
      _arm(canvas, shoulderR, pawR, bend: 14);
    } else {
      _arm(canvas, shoulderL, pawL, bend: -10);
      if (pose.armChin <= 0.02) _arm(canvas, shoulderR, pawR, bend: 10);
    }
  }

  void _arm(
    Canvas canvas,
    Offset shoulder,
    Offset paw, {
    required double bend,
  }) {
    final mid = Offset.lerp(shoulder, paw, 0.5)!;
    final normal = (paw - shoulder);
    final len = normal.distance == 0 ? 1.0 : normal.distance;
    final ctrl = mid + Offset(-normal.dy / len, normal.dx / len) * bend;
    final path = Path()
      ..moveTo(shoulder.dx, shoulder.dy)
      ..quadraticBezierTo(ctrl.dx, ctrl.dy, paw.dx, paw.dy);
    canvas
      ..drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 21
          ..strokeCap = StrokeCap.round
          ..color = _Ink.hoodie,
      )
      ..drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round
          ..color = _Ink.hoodieLight.withValues(alpha: 0.5),
      )
      ..drawCircle(paw, 11.5, Paint()..color = _Ink.black)
      ..drawCircle(
        paw + const Offset(0, 2),
        4.2,
        Paint()..color = _Ink.earInner,
      );
  }

  // ---- head ----------------------------------------------------------------

  void _head(Canvas canvas, PandaPerformer p) {
    final pose = p.pose;
    canvas.save();
    // Pivot at the neck so tilts swing the head, not the whole stage.
    canvas.translate(256, 150 + pose.headDrop + p.headBob * 0.6);
    canvas.rotate(pose.headTilt + 0.03 * pose.lean * (p.breath));
    // The head is drawn larger than the body, as in the original artwork's
    // cartoon proportions, so the mouth shapes read at small sizes.
    const headScale = 1.3;
    canvas.translate(0, (-38 - 0.7 * p.breath - pose.lean * 3) * headScale);
    canvas.scale(headScale);

    _ears(canvas, pose);
    _skull(canvas, pose);
    _eyePatches(canvas);
    _eyes(canvas, p);
    _brows(canvas, p);
    _nose(canvas);
    _mouth(canvas, p);
    canvas.restore();
  }

  void _ears(Canvas canvas, PandaPose pose) {
    final lift = pose.earPerk * 5;
    for (final side in const [-1.0, 1.0]) {
      final c = Offset(side * 49, -42 - lift);
      canvas
        ..drawCircle(c, 18 + pose.earPerk, Paint()..color = _Ink.black)
        ..drawCircle(
          c + Offset(side * -1, 2),
          8.5,
          Paint()..color = _Ink.earInner,
        );
    }
  }

  void _skull(Canvas canvas, PandaPose pose) {
    final rect = Rect.fromCenter(center: Offset.zero, width: 130, height: 112);
    canvas.drawOval(
      rect,
      Paint()
        ..shader = ui.Gradient.radial(
          const Offset(0, -14),
          78,
          [_Ink.fur, _Ink.fur, _Ink.furShade],
          const [0, 0.6, 1],
        ),
    );
    final blush = 0.22 + 0.5 * pose.cheeks;
    for (final side in const [-1.0, 1.0]) {
      canvas.drawOval(
        Rect.fromCenter(center: Offset(side * 42, 18), width: 26, height: 16),
        Paint()..color = _Ink.blush.withValues(alpha: blush),
      );
    }
  }

  void _eyePatches(Canvas canvas) {
    for (final side in const [-1.0, 1.0]) {
      canvas.save();
      canvas.translate(side * 27, -2);
      canvas.rotate(-side * 0.42);
      canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: 38, height: 49),
        Paint()..color = _Ink.black,
      );
      canvas.restore();
    }
  }

  void _eyes(Canvas canvas, PandaPerformer p) {
    final pose = p.pose;
    final open = (pose.eyeOpen * (1 - p.blink)).clamp(0.0, 1.2);
    final gx = (pose.gazeX + p.glanceX).clamp(-1.0, 1.0);
    final gy = (pose.gazeY + p.glanceY).clamp(-1.0, 1.0);
    for (final side in const [-1.0, 1.0]) {
      final center = Offset(side * 26, -2);
      canvas.save();
      canvas.translate(center.dx, center.dy);
      final roundAlpha = (1 - pose.squint).clamp(0.0, 1.0);

      if (open > 0.12 && roundAlpha > 0.02) {
        final eye = Rect.fromCenter(
          center: Offset.zero,
          width: 18,
          height: 21 * open.clamp(0.0, 1.0) + (open > 1 ? (open - 1) * 20 : 0),
        );
        canvas.saveLayer(
          eye.inflate(2),
          Paint()..color = Colors.white.withValues(alpha: roundAlpha),
        );
        canvas
          ..clipPath(Path()..addOval(eye))
          ..drawOval(eye, Paint()..color = Colors.white)
          ..drawCircle(
            Offset(gx * 3.5, gy * 3.8),
            7.6,
            Paint()..color = const Color(0xFF2A1B24),
          )
          ..drawCircle(
            Offset(gx * 3.5 + 2.4, gy * 3.8 - 3),
            2.5,
            Paint()..color = Colors.white,
          )
          ..drawCircle(
            Offset(gx * 3.5 - 2, gy * 3.8 + 3),
            1.2,
            Paint()..color = Colors.white.withValues(alpha: 0.85),
          );
        canvas.restore();
      } else if (roundAlpha > 0.02) {
        // Shut by a blink or sleepiness: a soft light line on the dark patch.
        canvas.drawPath(
          Path()
            ..moveTo(-8, -1)
            ..quadraticBezierTo(0, 4, 8, -1),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.4
            ..strokeCap = StrokeCap.round
            ..color = Colors.white.withValues(alpha: roundAlpha),
        );
      }
      if (pose.squint > 0.02) {
        // Happy eyes: an upturned arc (^).
        canvas.drawPath(
          Path()
            ..moveTo(-8.5, 3)
            ..quadraticBezierTo(0, -8, 8.5, 3),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3.2
            ..strokeCap = StrokeCap.round
            ..color = Colors.white.withValues(
              alpha: pose.squint.clamp(0.0, 1.0),
            ),
        );
      }
      canvas.restore();
    }
  }

  void _brows(Canvas canvas, PandaPerformer p) {
    final pose = p.pose;
    // The mouth's own motion nudges the brows a little while speaking.
    final speech = p.mouth.open * 0.14;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.4
      ..strokeCap = StrokeCap.round
      ..color = _Ink.brow;
    for (final side in const [-1.0, 1.0]) {
      final raise = (side < 0 ? pose.browLeft : pose.browRight) + speech;
      // Inner end is toward the nose. Lowered brows slant down inward (frown);
      // worry pulls the inner end up.
      final frown = raise < 0 ? -raise * 3 : 0.0;
      final lift = -raise * 7;
      final inner = Offset(side * 12, -33 + lift + frown - pose.browWorry * 6);
      final outer = Offset(side * 40, -33 + lift + pose.browWorry * 2);
      canvas.drawPath(
        Path()
          ..moveTo(inner.dx, inner.dy)
          ..quadraticBezierTo(
            (inner.dx + outer.dx) / 2,
            math.min(inner.dy, outer.dy) - 3,
            outer.dx,
            outer.dy,
          ),
        paint,
      );
    }
  }

  void _nose(Canvas canvas) {
    canvas.drawPath(
      Path()
        ..moveTo(-8, 8)
        ..quadraticBezierTo(0, 5, 8, 8)
        ..quadraticBezierTo(8, 15, 0, 18)
        ..quadraticBezierTo(-8, 15, -8, 8)
        ..close(),
      Paint()..color = _Ink.nose,
    );
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(-2.5, 9), width: 5, height: 2.6),
      Paint()..color = Colors.white.withValues(alpha: 0.35),
    );
  }

  /// The mouth, drawn from the eased [MouthShape] of the current viseme.
  void _mouth(Canvas canvas, PandaPerformer p) {
    final m = p.mouth;
    final smile = p.pose.smile.clamp(-1.0, 1.0);
    const y0 = 27.0;
    final halfWidth = 15.0 * m.width;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = _Ink.mouthLine;

    // Philtrum from the nose.
    canvas.drawLine(
      const Offset(0, 18),
      const Offset(0, y0 - 1),
      line..strokeWidth = 1.6,
    );
    line.strokeWidth = 2.2;

    final depth = m.open * 15;
    if (depth < 0.8) {
      // Closed: a smile line (or a pressed, flatter one for m, b, p).
      final curve = m.pressed
          ? 0.8
          : 3 + 7 * (smile + 1) / 2 * (1 - m.round * 0.5);
      canvas.drawPath(
        Path()
          ..moveTo(-halfWidth, y0 - smile * 1.5)
          ..quadraticBezierTo(0, y0 + curve, halfWidth, y0 - smile * 1.5),
        line..strokeWidth = m.pressed ? 2.8 : 2.2,
      );
      return;
    }

    // Open: corners lift with the smile, jaw drops by [depth].
    final corner = y0 - smile * 2 * (1 - m.open);
    final squeeze = 1 - m.round * 0.28;
    final shape = Path()
      ..moveTo(-halfWidth, corner)
      ..quadraticBezierTo(0, corner + 2 - m.round * 1.5, halfWidth, corner)
      ..cubicTo(
        halfWidth * squeeze,
        corner + depth * 1.3,
        -halfWidth * squeeze,
        corner + depth * 1.3,
        -halfWidth,
        corner,
      )
      ..close();
    canvas.save();
    canvas.clipPath(shape);
    canvas.drawPath(shape, Paint()..color = _Ink.mouthInside);
    if (m.tongue) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(0, corner + depth * 0.78),
          width: halfWidth * 1.15,
          height: depth * 0.7,
        ),
        Paint()..color = _Ink.tongue,
      );
    }
    if (m.teeth) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            -halfWidth * 0.62,
            corner + 0.4,
            halfWidth * 1.24,
            math.min(5.5, depth * 0.55),
          ),
          const Radius.circular(2),
        ),
        Paint()..color = Colors.white,
      );
    }
    canvas.restore();
    canvas.drawPath(shape, line..strokeWidth = 2);
  }

  // ---- extras --------------------------------------------------------------

  void _sleepZs(Canvas canvas, PandaPerformer p) {
    final alpha = ((p.pose.sleepy - 0.4) / 0.6).clamp(0.0, 1.0);
    for (var i = 0; i < 3; i++) {
      final phase = p.reduceMotion ? i / 3 : ((p.time * 0.35 + i / 3) % 1);
      final x = 338 + i * 14 + phase * 10;
      final y = 78 - phase * 46;
      final fade = math.sin(phase * math.pi).clamp(0.0, 1.0) * alpha;
      final size = 7.0 + i * 3;
      canvas.drawPath(
        Path()
          ..moveTo(x, y)
          ..lineTo(x + size, y)
          ..lineTo(x, y + size)
          ..lineTo(x + size, y + size),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.6
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = Colors.white.withValues(alpha: fade),
      );
    }
  }
}
