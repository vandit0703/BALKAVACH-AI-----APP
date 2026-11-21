import 'package:flutter/foundation.dart';

/// A mouth shape. Eight shapes cover the visible difference between speech
/// sounds in English, Hindi and Gujarati (the usual cartoon viseme set).
///
/// | Viseme | Sounds it stands for |
/// |---|---|
/// | [rest] | silence, lips softly closed |
/// | [mbp] | m, b, p (lips pressed together) |
/// | [fv] | f, v, Hindi/Gujarati व (upper teeth on lower lip) |
/// | [oo] | oo, u, w (small round lips) |
/// | [oh] | o, au (rounder, more open) |
/// | [ah] | a, aa (wide open) |
/// | [ee] | e, i, ee (wide, teeth, narrow opening) |
/// | [tl] | t, d, n, l, th, k, g, s... (slightly open, teeth/tongue) |
enum Viseme { rest, mbp, fv, oo, oh, ah, ee, tl }

/// Geometry of one [Viseme], in face units (the painter scales it).
@immutable
class MouthShape {
  const MouthShape({
    required this.open,
    required this.width,
    this.round = 0,
    this.teeth = false,
    this.tongue = false,
    this.pressed = false,
  });

  /// How far the jaw is open, 0 (closed) to 1 (widest).
  final double open;

  /// Mouth width relative to a neutral smile (1).
  final double width;

  /// 0 for a stretched mouth, 1 for fully round lips.
  final double round;

  /// Upper teeth visible.
  final bool teeth;

  /// Tongue visible.
  final bool tongue;

  /// Lips pressed flat together (a line, no smile curve).
  final bool pressed;

  static MouthShape lerp(MouthShape a, MouthShape b, double t) => MouthShape(
    open: a.open + (b.open - a.open) * t,
    width: a.width + (b.width - a.width) * t,
    round: a.round + (b.round - a.round) * t,
    teeth: t < 0.5 ? a.teeth : b.teeth,
    tongue: t < 0.5 ? a.tongue : b.tongue,
    pressed: t < 0.5 ? a.pressed : b.pressed,
  );
}

/// The shape each viseme draws.
const mouthShapes = <Viseme, MouthShape>{
  Viseme.rest: MouthShape(open: 0, width: 1),
  Viseme.mbp: MouthShape(open: 0, width: 0.8, pressed: true),
  Viseme.fv: MouthShape(open: 0.2, width: 1, teeth: true),
  Viseme.oo: MouthShape(open: 0.4, width: 0.5, round: 1),
  Viseme.oh: MouthShape(open: 0.65, width: 0.7, round: 0.75, tongue: true),
  Viseme.ah: MouthShape(open: 1, width: 0.95, tongue: true),
  Viseme.ee: MouthShape(open: 0.25, width: 1.25, teeth: true),
  Viseme.tl: MouthShape(open: 0.38, width: 0.95, teeth: true, tongue: true),
};
