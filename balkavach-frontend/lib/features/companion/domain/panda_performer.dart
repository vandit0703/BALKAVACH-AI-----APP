import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'panda_interaction.dart';
import 'viseme.dart';

/// Everything about Panda's face and body that can change, as numbers the
/// painter reads. All fields ease smoothly from one [PandaPhase] to the next.
@immutable
class PandaPose {
  const PandaPose({
    this.eyeOpen = 1,
    this.squint = 0,
    this.browLeft = 0,
    this.browRight = 0,
    this.browWorry = 0,
    this.gazeX = 0,
    this.gazeY = 0,
    this.headTilt = 0,
    this.headDrop = 0,
    this.smile = 0.35,
    this.cheeks = 0,
    this.armWave = 0,
    this.armChin = 0,
    this.armsUp = 0,
    this.earPerk = 0,
    this.lean = 0,
    this.sleepy = 0,
  });

  /// 0 closed .. 1 normal .. 1.15 wide.
  final double eyeOpen;

  /// 0 round eyes .. 1 happy upturned arcs (^ ^).
  final double squint;

  /// -1 lowered .. 0 neutral .. 1 raised.
  final double browLeft;
  final double browRight;

  /// 0 .. 1: inner brow ends pulled up (worried).
  final double browWorry;

  /// Where the eyes look, -1 .. 1 (left/up negative).
  final double gazeX;
  final double gazeY;

  /// Head tilt in radians (positive = clockwise) and droop in face units.
  final double headTilt;
  final double headDrop;

  /// Resting mouth curve, -1 frown .. 1 grin (used when the mouth is closed).
  final double smile;
  final double cheeks;

  /// Right arm waving (0..1), paw at the chin (0..1), both arms raised (0..1).
  final double armWave;
  final double armChin;
  final double armsUp;

  /// Ears pricked up to listen (0..1) and a forward lean (0..1).
  final double earPerk;
  final double lean;

  /// 0..1, drives the drowsy "z z z".
  final double sleepy;

  static double _l(double a, double b, double t) => a + (b - a) * t;

  /// [t] of the way from [a] to [b].
  static PandaPose lerp(PandaPose a, PandaPose b, double t) => PandaPose(
    eyeOpen: _l(a.eyeOpen, b.eyeOpen, t),
    squint: _l(a.squint, b.squint, t),
    browLeft: _l(a.browLeft, b.browLeft, t),
    browRight: _l(a.browRight, b.browRight, t),
    browWorry: _l(a.browWorry, b.browWorry, t),
    gazeX: _l(a.gazeX, b.gazeX, t),
    gazeY: _l(a.gazeY, b.gazeY, t),
    headTilt: _l(a.headTilt, b.headTilt, t),
    headDrop: _l(a.headDrop, b.headDrop, t),
    smile: _l(a.smile, b.smile, t),
    cheeks: _l(a.cheeks, b.cheeks, t),
    armWave: _l(a.armWave, b.armWave, t),
    armChin: _l(a.armChin, b.armChin, t),
    armsUp: _l(a.armsUp, b.armsUp, t),
    earPerk: _l(a.earPerk, b.earPerk, t),
    lean: _l(a.lean, b.lean, t),
    sleepy: _l(a.sleepy, b.sleepy, t),
  );

  /// Largest difference between any two matching fields.
  double distanceTo(PandaPose o) => [
    (eyeOpen - o.eyeOpen).abs(),
    (squint - o.squint).abs(),
    (browLeft - o.browLeft).abs(),
    (browRight - o.browRight).abs(),
    (browWorry - o.browWorry).abs(),
    (gazeX - o.gazeX).abs(),
    (gazeY - o.gazeY).abs(),
    (headTilt - o.headTilt).abs() * 4,
    (headDrop - o.headDrop).abs() / 8,
    (smile - o.smile).abs(),
    (cheeks - o.cheeks).abs(),
    (armWave - o.armWave).abs(),
    (armChin - o.armChin).abs(),
    (armsUp - o.armsUp).abs(),
    (earPerk - o.earPerk).abs(),
    (lean - o.lean).abs(),
    (sleepy - o.sleepy).abs(),
  ].reduce(math.max);
}

/// The face and posture each phase calls for. They differ enough to tell
/// apart at a glance: wide-eyed head-tilt for listening, eyes-up with a paw at
/// the chin for thinking, arcs and raised arms for happy, drooping lids for
/// sleepy.
const pandaPoses = <PandaPhase, PandaPose>{
  PandaPhase.idle: PandaPose(),
  PandaPhase.requestingPermission: PandaPose(
    browLeft: 0.25,
    browRight: 0.25,
    headTilt: 0.05,
    earPerk: 0.5,
  ),
  PandaPhase.initializing: PandaPose(
    browLeft: 0.25,
    browRight: 0.25,
    headTilt: 0.08,
    earPerk: 0.8,
  ),
  PandaPhase.greeting: PandaPose(
    browLeft: 0.5,
    browRight: 0.5,
    smile: 0.85,
    cheeks: 0.5,
    armWave: 1,
    headTilt: 0.05,
  ),
  PandaPhase.listening: PandaPose(
    eyeOpen: 1.14,
    browLeft: 0.35,
    browRight: 0.35,
    gazeY: 0.05,
    headTilt: 0.13,
    smile: 0.2,
    earPerk: 1,
    lean: 1,
  ),
  PandaPhase.thinking: PandaPose(
    browLeft: 0.7,
    browRight: -0.25,
    gazeX: -0.7,
    gazeY: -0.75,
    headTilt: -0.07,
    smile: -0.05,
    armChin: 1,
  ),
  PandaPhase.speaking: PandaPose(
    browLeft: 0.12,
    browRight: 0.12,
    smile: 0.4,
    cheeks: 0.15,
  ),
  PandaPhase.happy: PandaPose(
    eyeOpen: 0.9,
    squint: 1,
    browLeft: 0.35,
    browRight: 0.35,
    smile: 1,
    cheeks: 1,
    armsUp: 1,
    headTilt: -0.04,
  ),
  PandaPhase.curious: PandaPose(
    browLeft: 0.1,
    browRight: 0.95,
    gazeX: 0.3,
    gazeY: -0.2,
    headTilt: 0.16,
    smile: 0.2,
  ),
  PandaPhase.sleepy: PandaPose(
    eyeOpen: 0.32,
    browLeft: -0.25,
    browRight: -0.25,
    headTilt: 0.1,
    headDrop: 8,
    smile: 0.1,
    sleepy: 1,
  ),
  PandaPhase.error: PandaPose(
    browLeft: 0.4,
    browRight: 0.4,
    browWorry: 1,
    smile: -0.3,
    armWave: 0.55,
    headTilt: 0.06,
  ),
};

/// Runs Panda's performance: eases between phases, blinks, glances around,
/// breathes, and moves the mouth toward the current [Viseme].
///
/// Pure Dart with an injectable [math.Random], so timing is testable.
/// [tick] advances everything by real elapsed time; the widget calls it from
/// one ticker.
class PandaPerformer {
  PandaPerformer({math.Random? random, this.reduceMotion = false})
    : _random = random ?? math.Random(),
      _pose = pandaPoses[PandaPhase.idle]!,
      _mouth = mouthShapes[Viseme.rest]! {
    _scheduleBlink();
    _scheduleGlance();
  }

  /// How long Panda keeps idling (blinking, breathing) with nobody talking,
  /// before the animation stops completely to save battery.
  static const idleTimeout = Duration(seconds: 20);

  final math.Random _random;

  /// With reduced motion Panda holds still, apart from the mouth: its shapes
  /// are what shows the voice, not decoration.
  bool reduceMotion;

  PandaPhase _phase = PandaPhase.idle;
  PandaPose _pose;
  MouthShape _mouth;
  Viseme _viseme = Viseme.rest;

  double _time = 0; // seconds since start
  double _sinceActivity = 0;
  double _blinkClock = 0; // seconds into the current blink, <0 = waiting
  double _nextBlink = 3;
  bool _doubleBlink = false;
  double _nextGlance = 2;
  double _glanceX = 0;
  double _glanceY = 0;
  double _glanceTargetX = 0;
  double _glanceTargetY = 0;
  double _happyAge = 99;

  PandaPhase get phase => _phase;

  /// The eased pose (without blink, glance, breathing: see the getters below).
  PandaPose get pose => _pose;

  /// The eased mouth.
  MouthShape get mouth => _mouth;
  Viseme get viseme => _viseme;

  /// 0 eyes open .. 1 fully shut by a blink.
  double get blink {
    if (reduceMotion || _blinkClock < 0) return 0;
    const close = 0.07, hold = 0.04, open = 0.1;
    if (_blinkClock < close) return _blinkClock / close;
    if (_blinkClock < close + hold) return 1;
    final t = (_blinkClock - close - hold) / open;
    return t >= 1 ? 0 : 1 - t;
  }

  /// Small extra eye movement on top of the phase's gaze.
  double get glanceX => reduceMotion ? 0 : _glanceX;
  double get glanceY => reduceMotion ? 0 : _glanceY;

  /// -1..1 slow breathing.
  double get breath => reduceMotion ? 0 : math.sin(_time * 2 * math.pi / 3.2);

  /// Head nod in face units while speaking, from how open the mouth is.
  double get headBob => reduceMotion ? 0 : _mouth.open * 2.2;

  /// Waving paw angle offset, radians.
  double get waveAngle => reduceMotion ? 0 : math.sin(_time * 9) * 0.3;

  /// Hop height in face units for happy news (first 1.4 s of [PandaPhase.happy]).
  double get hop {
    if (reduceMotion || _happyAge > 1.4) return 0;
    return (math.sin(_happyAge * 7.5).abs() * 9) * (1 - _happyAge / 1.4);
  }

  /// Seconds since the performer started (drives the painter's idle motion).
  double get time => _time;

  /// Whether another frame is needed: Panda is speaking or easing, or is
  /// still within the idle window. False lets the ticker stop.
  bool get needsFrames {
    if (_viseme != Viseme.rest || _mouth.open > 0.01) return true;
    if (!_settled) return true;
    return !reduceMotion && _sinceActivity < idleTimeout.inSeconds;
  }

  bool get _settled =>
      _pose.distanceTo(_target) < 0.01 &&
      (_mouth.open - mouthShapes[_viseme]!.open).abs() < 0.01 &&
      _blinkClock < 0 &&
      _hopping == false;

  bool get _hopping => !reduceMotion && _happyAge <= 1.4;

  PandaPose get _target => pandaPoses[_phase]!;

  /// Switches the face and posture to [phase]. Transitions ease.
  void setPhase(PandaPhase phase) {
    if (phase == _phase) return;
    if (phase == PandaPhase.happy) _happyAge = 0;
    _phase = phase;
    _sinceActivity = 0;
    if (reduceMotion) _pose = _target;
  }

  /// Advances by [dt] with the mouth heading to [viseme].
  void tick(Duration dt, Viseme viseme) {
    final seconds = dt.inMicroseconds / 1e6;
    if (seconds <= 0) return;
    _time += seconds;
    _happyAge += seconds;
    _sinceActivity += seconds;
    if (viseme != Viseme.rest) _sinceActivity = 0;
    _viseme = viseme;

    // Expression: ease toward the phase's pose (about a quarter second).
    if (reduceMotion) {
      _pose = _target;
    } else {
      _pose = PandaPose.lerp(_pose, _target, _ease(seconds, 0.11));
    }
    // Mouth: faster, so shapes read as separate sounds.
    final target = mouthShapes[viseme]!;
    final eased = MouthShape.lerp(_mouth, target, _ease(seconds, 0.032));
    // Numbers glide; teeth, tongue and pressed lips switch with the sound.
    _mouth = MouthShape(
      open: eased.open,
      width: eased.width,
      round: eased.round,
      teeth: target.teeth,
      tongue: target.tongue,
      pressed: target.pressed,
    );

    if (reduceMotion) {
      _blinkClock = -1;
      return;
    }
    _tickBlink(seconds);
    _tickGlance(seconds);
  }

  static double _ease(double seconds, double tau) =>
      1 - math.exp(-seconds / tau);

  bool get _canBlink =>
      _pose.eyeOpen > 0.6 && _pose.squint < 0.5 && _phase != PandaPhase.sleepy;

  void _scheduleBlink() {
    _nextBlink = 2.2 + _random.nextDouble() * 2.8;
    _doubleBlink = _random.nextDouble() < 0.15;
  }

  void _tickBlink(double seconds) {
    if (_blinkClock >= 0) {
      _blinkClock += seconds;
      if (_blinkClock > 0.21) {
        _blinkClock = -1;
        if (_doubleBlink) {
          _doubleBlink = false;
          _nextBlink = 0.12;
        } else {
          _scheduleBlink();
        }
      }
      return;
    }
    _nextBlink -= seconds;
    if (_nextBlink <= 0 && _canBlink) {
      _blinkClock = 0;
    } else if (_nextBlink <= 0) {
      _scheduleBlink();
    }
  }

  void _scheduleGlance() {
    _nextGlance = 1.3 + _random.nextDouble() * 2.4;
    // Thinking keeps its fixed upward look; other phases wander a little.
    final range = _phase == PandaPhase.thinking ? 0.05 : 0.22;
    _glanceTargetX = (_random.nextDouble() * 2 - 1) * range;
    _glanceTargetY = (_random.nextDouble() * 2 - 1) * range * 0.6;
  }

  void _tickGlance(double seconds) {
    _nextGlance -= seconds;
    if (_nextGlance <= 0) _scheduleGlance();
    final k = _ease(seconds, 0.09);
    _glanceX += (_glanceTargetX - _glanceX) * k;
    _glanceY += (_glanceTargetY - _glanceY) * k;
  }
}
