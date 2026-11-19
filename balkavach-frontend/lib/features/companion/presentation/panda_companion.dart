import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/models/app_assets.dart';
import '../domain/companion_director.dart';

/// Panda, animated, saying one authored line for [event].
///
/// * The line is picked once by the shared [CompanionDirector] (no repeats, no
///   nagging) and stays put on rebuilds. Tapping Panda shows the other line.
/// * [name], [missionTitle], [stars] and [minutes] personalise the line. They
///   are only ever shown on this device; nothing is sent anywhere.
/// * The animation fits the mood (chatting, cheering, drowsy), plays a few
///   times and then rests, so it never drains the battery or keeps tests from
///   settling. It does not move at all when the system asks for reduced motion.
class PandaCompanion extends ConsumerStatefulWidget {
  const PandaCompanion({
    required this.event,
    this.name = '',
    this.missionTitle = '',
    this.stars = 1,
    this.minutes = 15,
    this.avatarSize = 72,
    super.key,
  });

  final CompanionEvent event;
  final String name;
  final String missionTitle;
  final int stars;
  final int minutes;
  final double avatarSize;

  @override
  ConsumerState<PandaCompanion> createState() => _PandaCompanionState();
}

class _PandaCompanionState extends ConsumerState<PandaCompanion>
    with SingleTickerProviderStateMixin {
  /// How many times one animation loops before Panda settles.
  static const _loops = 3;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  late int _variant;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    final director = ref.read(companionDirectorProvider);
    final fresh = director.next(widget.event);
    _variant = fresh ?? director.current(widget.event);
    _spoke = fresh != null;
  }

  bool _spoke = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion) {
      _controller.stop();
    } else if (_spoke && _controller.status == AnimationStatus.dismissed) {
      _spoke = false;
      _play();
    }
  }

  void _play() {
    if (_reduceMotion) return;
    final mood = pandaMoodFor(widget.event);
    // Drowsy Panda breathes slowly, cheering Panda is quicker.
    _controller.duration = switch (mood) {
      PandaMood.sleepy => const Duration(milliseconds: 2400),
      PandaMood.celebrating => const Duration(milliseconds: 900),
      PandaMood.talking => const Duration(milliseconds: 1400),
    };
    _controller.repeat(count: _loops);
  }

  void _another() {
    setState(() => _variant = (_variant + 1) % kCompanionVariants);
    _controller
      ..stop()
      ..value = 0;
    _play();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final mood = pandaMoodFor(widget.event);
    final line = pandaLine(
      l10n,
      widget.event,
      _variant,
      minutes: widget.minutes,
      name: widget.name,
      missionTitle: widget.missionTitle,
      stars: widget.stars,
    );
    final size = widget.avatarSize;

    return Semantics(
      container: true,
      label: '${l10n.pandaName}: $line',
      child: ExcludeSemantics(
        child: Row(
          key: const Key('panda.companion'),
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            GestureDetector(
              key: const Key('panda.avatar'),
              behavior: HitTestBehavior.opaque,
              onTap: _another,
              child: SizedBox(
                width: size + 16,
                height: size + 16,
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) => _PandaAvatar(
                    size: size,
                    mood: mood,
                    t: _controller.value,
                    animating: _controller.isAnimating,
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Flexible(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.surfaceContainerLowest,
                  // A speech bubble: the corner nearest Panda stays square.
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(4),
                    topRight: Radius.circular(AppRadius.md),
                    bottomLeft: Radius.circular(AppRadius.md),
                    bottomRight: Radius.circular(AppRadius.md),
                  ),
                  border: Border.all(color: colors.primaryContainer, width: 2),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm + 4),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Text(
                      line,
                      key: Key('panda.line.$_variant'),
                      style: context.text.bodyLarge,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PandaAvatar extends StatelessWidget {
  const _PandaAvatar({
    required this.size,
    required this.mood,
    required this.t,
    required this.animating,
  });

  final double size;
  final PandaMood mood;

  /// Animation position, 0..1 within one loop.
  final double t;
  final bool animating;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final wave = math.sin(t * 2 * math.pi);
    final hop = (math.sin(t * math.pi)).abs();

    final (dy, angle, scale) = !animating
        ? (0.0, 0.0, 1.0)
        : switch (mood) {
            PandaMood.talking => (-3 * wave, 0.0, 1.0 + 0.02 * wave),
            PandaMood.celebrating => (-10 * hop, 0.08 * wave, 1.0 + 0.05 * hop),
            PandaMood.sleepy => (0.0, 0.0, 1.0 + 0.03 * wave),
          };

    final asset = mood == PandaMood.celebrating
        ? AppImages.pandaCheering
        : AppImages.pandaHoodie;

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        Transform.translate(
          offset: Offset(0, dy),
          child: Transform.rotate(
            angle: angle,
            child: Transform.scale(
              scale: scale,
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.surfaceContainerLowest,
                  border: Border.all(color: colors.primaryContainer, width: 3),
                ),
                child: ClipOval(
                  child: ColorFiltered(
                    // Drowsy Panda is a little dimmer.
                    colorFilter: ColorFilter.mode(
                      mood == PandaMood.sleepy
                          ? Colors.black.withValues(alpha: 0.12)
                          : Colors.transparent,
                      BlendMode.srcATop,
                    ),
                    child: Image.asset(
                      asset,
                      fit: BoxFit.cover,
                      cacheWidth: (size * dpr).round(),
                      excludeFromSemantics: true,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (mood == PandaMood.celebrating && animating) ...[
          _Sparkle(size: size, t: t, phase: 0, left: true),
          _Sparkle(size: size, t: t, phase: 0.5, left: false),
        ],
        if (mood == PandaMood.sleepy)
          Positioned(
            right: 0,
            top: 0,
            child: Opacity(
              opacity: animating ? 0.4 + 0.6 * (0.5 + 0.5 * wave) : 0.8,
              child: Text(
                'z z',
                style: context.text.labelLarge?.copyWith(
                  color: colors.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// A little star that floats up beside a cheering Panda.
class _Sparkle extends StatelessWidget {
  const _Sparkle({
    required this.size,
    required this.t,
    required this.phase,
    required this.left,
  });

  final double size;
  final double t;
  final double phase;
  final bool left;

  @override
  Widget build(BuildContext context) {
    final p = (t + phase) % 1;
    final rise = p * 18;
    final opacity = (1 - p).clamp(0.0, 1.0);
    return Positioned(
      top: 4 - rise,
      left: left ? 0 : null,
      right: left ? null : 0,
      child: Opacity(
        opacity: opacity,
        child: Icon(
          Icons.star_rounded,
          size: 16,
          color: context.colors.tertiaryFixedDim,
        ),
      ),
    );
  }
}
