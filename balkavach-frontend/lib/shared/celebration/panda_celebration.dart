import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../l10n/app_localizations.dart';
import '../models/app_assets.dart';
import '../widgets/buttons.dart';
import 'activity_completion.dart';

/// How the child left the celebration.
enum CelebrationAction { continueOn, home }

/// Shows the celebration over the current screen and completes when it is
/// dismissed. Back counts as Continue. Showing it never changes any balance.
Future<CelebrationAction> showPandaCelebration(
  BuildContext context,
  ActivityCompletion completion,
) async {
  final action = await Navigator.of(context, rootNavigator: true)
      .push<CelebrationAction>(
        PageRouteBuilder<CelebrationAction>(
          opaque: false,
          barrierColor: Colors.black54,
          barrierDismissible: false,
          transitionDuration: const Duration(milliseconds: 220),
          pageBuilder: (_, _, _) => PandaCelebration(completion: completion),
          transitionsBuilder: (_, animation, _, child) =>
              FadeTransition(opacity: animation, child: child),
        ),
      );
  return action ?? CelebrationAction.continueOn;
}

String celebrationHeadline(AppLocalizations l10n, ActivityKind kind) =>
    switch (kind) {
      ActivityKind.mission => l10n.celebrationMission,
      ActivityKind.quiz => l10n.celebrationQuiz,
      ActivityKind.video => l10n.celebrationVideo,
      ActivityKind.story => l10n.celebrationStory,
      ActivityKind.garden => l10n.celebrationGarden,
    };

/// The official Panda cheering, a short burst of stars and confetti behind
/// it, the activity's name, any Stars and XP the server paid, and Continue.
/// With reduced motion the Panda and the text stay and nothing moves.
class PandaCelebration extends StatefulWidget {
  const PandaCelebration({required this.completion, super.key});

  final ActivityCompletion completion;

  @override
  State<PandaCelebration> createState() => _PandaCelebrationState();
}

class _PandaCelebrationState extends State<PandaCelebration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // The burst runs once; reduced motion skips it entirely.
    if (!MediaQuery.disableAnimationsOf(context)) _controller.forward();
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
    final completion = widget.completion;
    final rewards = [
      if (completion.stars > 0) l10n.quizRewardStars(completion.stars),
      if (completion.xp > 0) l10n.quizRewardXp(completion.xp),
    ];
    final reduce = MediaQuery.disableAnimationsOf(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Stack(
          children: [
            if (!reduce)
              Positioned.fill(
                child: IgnorePointer(
                  child: ExcludeSemantics(
                    child: AnimatedBuilder(
                      animation: _controller,
                      builder: (_, _) => CustomPaint(
                        painter: _ConfettiPainter(
                          progress: _controller.value,
                          colors: [
                            colors.primary,
                            colors.tertiary,
                            colors.secondary,
                            colors.error,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Material(
                    key: const Key('celebration.card'),
                    color: colors.surface,
                    borderRadius: AppRadius.hero,
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: AppSpacing.sm,
                        children: [
                          _Hop(
                            controller: _controller,
                            reduce: reduce,
                            child: ClipRRect(
                              borderRadius: AppRadius.card,
                              child: Image.asset(
                                AppImages.pandaCheering,
                                key: const Key('celebration.panda'),
                                height: 180,
                                fit: BoxFit.cover,
                                semanticLabel: celebrationHeadline(
                                  l10n,
                                  completion.kind,
                                ),
                              ),
                            ),
                          ),
                          Semantics(
                            liveRegion: true,
                            child: Text(
                              completion.headline ??
                                  celebrationHeadline(l10n, completion.kind),
                              key: const Key('celebration.headline'),
                              textAlign: TextAlign.center,
                              style: context.text.headlineMedium,
                            ),
                          ),
                          Text(
                            completion.title,
                            key: const Key('celebration.title'),
                            textAlign: TextAlign.center,
                            style: context.text.titleMedium?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                          if (completion.hasRewards)
                            Row(
                              key: const Key('celebration.rewards'),
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.stars_rounded,
                                  color: colors.primary,
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Flexible(
                                  child: Text(
                                    '+ ${rewards.join(' + ')}',
                                    style: context.text.titleLarge?.copyWith(
                                      color: colors.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          Text(
                            completion.note ?? l10n.celebrationCheer,
                            key: const Key('celebration.message'),
                            textAlign: TextAlign.center,
                            style: context.text.bodyLarge,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          PrimaryButton(
                            key: const Key('celebration.continue'),
                            label: l10n.celebrationContinue,
                            childSized: true,
                            onPressed: () => Navigator.of(
                              context,
                            ).pop(CelebrationAction.continueOn),
                          ),
                          if (completion.offerHome)
                            SecondaryButton(
                              key: const Key('celebration.home'),
                              label: l10n.celebrationHome,
                              icon: Icons.home_rounded,
                              onPressed: () => Navigator.of(
                                context,
                              ).pop(CelebrationAction.home),
                            ),
                        ],
                      ),
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

/// A small happy hop at the start; the Panda artwork itself is never painted on.
class _Hop extends StatelessWidget {
  const _Hop({
    required this.controller,
    required this.reduce,
    required this.child,
  });

  final AnimationController controller;
  final bool reduce;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (reduce) return child;
    return AnimatedBuilder(
      animation: controller,
      child: child,
      builder: (_, child) {
        final t = (controller.value * 2600 / 900).clamp(0.0, 1.0);
        final lift = -math.sin(t * math.pi * 2).abs() * 14 * (1 - t);
        return Transform.translate(offset: Offset(0, lift), child: child);
      },
    );
  }
}

/// Stars and confetti falling behind the card, deterministic so every
/// celebration looks the same and tests are stable.
class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter({required this.progress, required this.colors});

  final double progress;
  final List<Color> colors;

  static const _count = 28;

  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(7);
    for (var i = 0; i < _count; i++) {
      final x = random.nextDouble() * size.width;
      final delay = random.nextDouble() * 0.35;
      final speed = 0.65 + random.nextDouble() * 0.35;
      final t = ((progress - delay) / (1 - delay)).clamp(0.0, 1.0);
      if (t <= 0) continue;
      final y = -20 + t * speed * (size.height + 40);
      final paint = Paint()
        ..color = colors[i % colors.length].withValues(alpha: 1 - t * 0.6);
      canvas
        ..save()
        ..translate(x + math.sin(t * 6 + i) * 14, y)
        ..rotate(t * 6 + i);
      if (i.isEven) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(-4, -7, 8, 14),
            const Radius.circular(2),
          ),
          paint,
        );
      } else {
        canvas.drawPath(_star(9), paint);
      }
      canvas.restore();
    }
  }

  Path _star(double r) {
    final path = Path();
    for (var k = 0; k < 10; k++) {
      final radius = k.isEven ? r : r * 0.45;
      final angle = -math.pi / 2 + k * math.pi / 5;
      final p = Offset(math.cos(angle) * radius, math.sin(angle) * radius);
      k == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    return path..close();
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.progress != progress;
}
