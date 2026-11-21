import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../domain/lip_sync.dart';
import '../domain/panda_interaction.dart';
import '../domain/panda_performer.dart';
import '../domain/viseme.dart';
import 'panda_rig_painter.dart';

/// Panda on a stage: a layered 2D character whose face and body follow the
/// conversation.
///
/// * [phase] picks the face and posture (idle, greeting, listening, thinking,
///   speaking, happy, curious, sleepy, error); changes ease in.
/// * While Panda speaks, the mouth shape comes from [lipSync], which follows the
///   voice engine's own start and word callbacks, so the mouth moves with the
///   audio and stops with it. It is a word-boundary viseme approximation, not
///   phoneme recognition (see [LipSyncController]).
/// * Blinking, eye movement and breathing are scheduled here. With reduced
///   motion everything holds still except the mouth, whose shapes are what
///   shows the voice.
/// * One ticker runs only while something moves; it stops after a short idle
///   window, so a resting Panda costs no battery.
class PandaCharacter extends StatefulWidget {
  const PandaCharacter({
    required this.phase,
    this.lipSync,
    this.onTap,
    super.key,
  });

  final PandaPhase phase;

  /// The mouth source. Null: the mouth stays closed.
  final LipSyncController? lipSync;
  final VoidCallback? onTap;

  @override
  State<PandaCharacter> createState() => PandaCharacterState();
}

class PandaCharacterState extends State<PandaCharacter>
    with SingleTickerProviderStateMixin {
  final _performer = PandaPerformer();
  final _frame = ValueNotifier<int>(0);
  late final Ticker _ticker = createTicker(_tick);
  late final PandaRigPainter _painter = PandaRigPainter(
    performer: _performer,
    repaint: _frame,
  );
  Duration _last = Duration.zero;

  /// The animation state, for tests.
  @visibleForTesting
  PandaPerformer get performer => _performer;

  @visibleForTesting
  bool get isTicking => _ticker.isActive;

  @override
  void initState() {
    super.initState();
    _performer.setPhase(widget.phase);
    widget.lipSync?.viseme.addListener(_wake);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _performer.reduceMotion = MediaQuery.disableAnimationsOf(context);
    _wake();
  }

  @override
  void didUpdateWidget(PandaCharacter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lipSync != widget.lipSync) {
      oldWidget.lipSync?.viseme.removeListener(_wake);
      widget.lipSync?.viseme.addListener(_wake);
    }
    if (oldWidget.phase != widget.phase) _performer.setPhase(widget.phase);
    _wake();
  }

  /// Starts the ticker if something needs animating. The mouth source and the
  /// phase both call this, so a stopped ticker restarts on the first event.
  void _wake() {
    if (!mounted || _ticker.isActive) return;
    _last = Duration.zero;
    _ticker.start();
    _frame.value++; // draws the first frame without waiting for a tick
  }

  void _tick(Duration elapsed) {
    final dt = elapsed - _last;
    _last = elapsed;
    final sync = widget.lipSync;
    sync?.update();
    _performer.tick(dt, sync?.viseme.value ?? Viseme.rest);
    _frame.value++;
    if (!_performer.needsFrames && !(sync?.isSpeaking ?? false)) {
      _ticker.stop();
    }
  }

  @override
  void dispose() {
    widget.lipSync?.viseme.removeListener(_wake);
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final phase = widget.phase;
    final listening = phase == PandaPhase.listening;
    final sync = widget.lipSync;

    return GestureDetector(
      key: const Key('panda.talk.character'),
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: _performer.reduceMotion
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
            aspectRatio: kPandaStageSize.width / kPandaStageSize.height,
            child: ExcludeSemantics(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  RepaintBoundary(
                    child: CustomPaint(
                      key: const Key('panda.rig'),
                      painter: _painter,
                      isComplex: true,
                      willChange: true,
                    ),
                  ),
                  // Zero-size markers so tests (and tooling) can read which
                  // phase and mouth shape are showing.
                  SizedBox.shrink(
                    key: ValueKey('panda.rig.phase.${phase.name}'),
                  ),
                  if (sync != null)
                    ValueListenableBuilder<Viseme>(
                      valueListenable: sync.viseme,
                      builder: (context, viseme, _) => SizedBox.shrink(
                        key: ValueKey('panda.rig.viseme.${viseme.name}'),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
