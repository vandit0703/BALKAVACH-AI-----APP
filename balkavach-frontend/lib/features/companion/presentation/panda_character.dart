import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/models/app_assets.dart';
import '../domain/panda_interaction.dart';

/// Which artwork Panda uses for each state, plus slots for the frames named in
/// `docs/panda-animation-art-brief.md`.
///
/// Today only [poses] are filled, with the existing Panda scenes. When the
/// artist delivers layered frames, fill [mouthOpen] and [blink]: the
/// renderer already swaps to them on real voice word boundaries and on blink
/// beats, with no other code change.
class PandaArtSet {
  const PandaArtSet({
    required this.poses,
    this.alignment = const {},
    this.mouthOpen = const {},
    this.blink = const {},
  });

  final Map<PandaPhase, String> poses;

  /// Where Panda sits in each wide scene, so a narrow crop keeps the face.
  final Map<String, Alignment> alignment;

  /// Same framing as the pose, mouth open. Shown while a word is spoken.
  final Map<PandaPhase, String> mouthOpen;

  /// Same framing as the pose, eyes closed. Shown for a blink.
  final Map<PandaPhase, String> blink;

  String poseFor(PandaPhase phase) => poses[phase] ?? AppImages.pandaHoodie;
}

/// The existing artwork, unchanged. No overlays are painted on Panda.
const kPandaArt = PandaArtSet(
  poses: {
    PandaPhase.idle: AppImages.pandaHoodie,
    PandaPhase.greeting: AppImages.pandaWelcome,
    PandaPhase.listening: AppImages.pandaMissions,
    PandaPhase.thinking: AppImages.pandaDrawing,
    PandaPhase.speaking: AppImages.pandaHoodie,
    PandaPhase.happy: AppImages.pandaCheering,
    PandaPhase.curious: AppImages.pandaMissions,
    PandaPhase.sleepy: AppImages.pandaHoodie,
    PandaPhase.error: AppImages.pandaHoodie,
  },
  alignment: {AppImages.pandaDrawing: Alignment(0.45, 0)},
);

/// Panda on a stage, reacting to the conversation.
///
/// Motion is tied to real events only: each word the voice engine starts
/// gives one talk beat (a mouth frame once art exists), a happy reply gives a
/// hop, idle Panda breathes slowly. With reduced motion nothing moves; the
/// state label beside Panda still says what is happening.
class PandaCharacter extends StatefulWidget {
  const PandaCharacter({
    required this.phase,
    required this.spokenWords,
    this.art = kPandaArt,
    this.onTap,
    super.key,
  });

  final PandaPhase phase;
  final int spokenWords;
  final PandaArtSet art;
  final VoidCallback? onTap;

  @override
  State<PandaCharacter> createState() => _PandaCharacterState();
}

class _PandaCharacterState extends State<PandaCharacter>
    with TickerProviderStateMixin {
  /// Slow breathing while Panda waits, for a limited number of breaths.
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  );

  /// One beat per spoken word.
  late final AnimationController _beat = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  );

  /// A hop for happy news.
  late final AnimationController _hop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  static const _maxBreaths = 8;
  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _sync(null);
  }

  @override
  void didUpdateWidget(PandaCharacter old) {
    super.didUpdateWidget(old);
    if (_reduceMotion) return;
    if (widget.spokenWords > old.spokenWords) _beat.forward(from: 0);
    if (widget.phase != old.phase) _sync(old.phase);
  }

  void _sync(PandaPhase? from) {
    if (_reduceMotion) {
      _breath.stop();
      _beat.stop();
      _hop.stop();
      _breath.value = _beat.value = _hop.value = 0;
      return;
    }
    final resting = const {
      PandaPhase.idle,
      PandaPhase.curious,
      PandaPhase.sleepy,
      PandaPhase.listening,
    }.contains(widget.phase);
    if (resting && !_breath.isAnimating) {
      _breath.repeat(reverse: true, count: _maxBreaths);
    } else if (!resting) {
      _breath.stop();
    }
    if (widget.phase == PandaPhase.happy && from != PandaPhase.happy) {
      _hop.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _breath.dispose();
    _beat.dispose();
    _hop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final phase = widget.phase;
    final art = widget.art;
    final listening = phase == PandaPhase.listening;

    return GestureDetector(
      key: const Key('panda.talk.character'),
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: _reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 250),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
            color: listening ? colors.primary : Colors.transparent,
            width: 3,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.lg - 3),
          child: AspectRatio(
            aspectRatio: 512 / 279,
            child: AnimatedBuilder(
              animation: Listenable.merge([_breath, _beat, _hop]),
              builder: (context, _) {
                final beat = Curves.easeOut.transform(
                  1 - (2 * _beat.value - 1).abs(),
                );
                final hop = Curves.easeOut.transform(
                  1 - (2 * _hop.value - 1).abs(),
                );
                final breath = Curves.easeInOut.transform(_breath.value);
                final talking = _beat.isAnimating && beat > 0.35;
                final asset = talking && art.mouthOpen[phase] != null
                    ? art.mouthOpen[phase]!
                    : art.poseFor(phase);
                final scale =
                    1 +
                    0.012 * breath +
                    (art.mouthOpen[phase] == null ? 0.02 * beat : 0) +
                    0.04 * hop;
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    Transform.translate(
                      offset: Offset(0, -10 * hop),
                      child: Transform.scale(
                        scale: scale,
                        alignment: Alignment.bottomCenter,
                        child: ColorFiltered(
                          colorFilter: ColorFilter.mode(
                            phase == PandaPhase.sleepy
                                ? Colors.black.withValues(alpha: 0.22)
                                : Colors.transparent,
                            BlendMode.srcATop,
                          ),
                          child: Image.asset(
                            asset,
                            key: ValueKey('panda.pose.$asset'),
                            fit: BoxFit.cover,
                            alignment: art.alignment[asset] ?? Alignment.center,
                            gaplessPlayback: true,
                            excludeFromSemantics: true,
                          ),
                        ),
                      ),
                    ),
                    if (phase == PandaPhase.sleepy)
                      Positioned(
                        right: AppSpacing.md,
                        top: AppSpacing.sm,
                        child: Text(
                          'z z z',
                          style: context.text.titleLarge?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
