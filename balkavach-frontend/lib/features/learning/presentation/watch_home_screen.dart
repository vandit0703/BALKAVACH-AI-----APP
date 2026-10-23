import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/responsive/breakpoints.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/async/refresh_quietly.dart';
import '../../../shared/models/app_assets.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/buttons.dart';
import '../../../shared/widgets/gamification.dart';
import '../../../shared/widgets/state_views.dart';
import '../data/learning_gate_repository.dart';
import '../data/learning_repository.dart';
import 'learning_screen.dart';

/// Home: the curated watch-and-learn experience.
///
/// What this screen may claim is limited by what the server can prove. While
/// `videoGateAvailable` is false there is no playback provider configured, so
/// no viewing time can be measured; the screen says so plainly and keeps
/// missions reachable instead of showing a progress bar that cannot move.
class WatchHomeScreen extends ConsumerWidget {
  const WatchHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gate = ref.watch(learningGateProvider);

    Future<void> refresh() async {
      ref
        ..invalidate(learningGateProvider)
        ..invalidate(learningItemsProvider);
      await refreshQuietly(ref.read(learningGateProvider.future));
    }

    return RefreshIndicator(
      onRefresh: refresh,
      child: switch (gate) {
        AsyncData(:final value) => _Body(gate: value),
        AsyncError(:final error) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            ErrorView(
              error: error,
              onRetry: () => ref.invalidate(learningGateProvider),
            ),
          ],
        ),
        _ => const LoadingView(),
      },
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.gate});

  final LearningGate gate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items =
        ref.watch(learningItemsProvider).value ?? const <LearningItem>[];
    final videos = [
      for (final item in items)
        if (item.contentType == 'video') item,
    ];

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        ResponsiveContent(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: AppSpacing.md,
            children: [
              _SessionCard(gate: gate),
              if (!gate.videoGateAvailable) _UnavailableCard(gate: gate),
              if (videos.isEmpty)
                EmptyView(
                  key: const Key('watch.empty'),
                  message: AppLocalizations.of(context).watchNoVideos,
                  image: AppImages.pandaDrawing,
                )
              else
                for (final video in videos)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: _VideoTile(item: video),
                  ),
              SecondaryButton(
                key: const Key('watch.openVideos'),
                label: AppLocalizations.of(context).videoFeedOpen,
                icon: Icons.video_library_rounded,
                onPressed: () => context.push(AppRoutes.childVideos),
              ),
              SecondaryButton(
                key: const Key('watch.openLearn'),
                label: AppLocalizations.of(context).learnOpenLearn,
                icon: Icons.menu_book_rounded,
                onPressed: () => context.go(AppRoutes.childLearn),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Today's session state: which session is in progress, how far along, and why
/// anything is still locked.
class _SessionCard extends StatelessWidget {
  const _SessionCard({required this.gate});

  final LearningGate gate;

  String _headline(AppLocalizations l10n) => switch (gate.phase) {
    LearningPhase.firstSession => l10n.watchGateMissionsLocked(
      (gate.firstSessionTargetSeconds / 60).ceil(),
    ),
    LearningPhase.missions => l10n.watchGateMissionsUnlocked,
    LearningPhase.awaitingApproval => l10n.watchGateAwaitingApproval,
    LearningPhase.secondSession => l10n.watchGateSecondUnlocked,
    LearningPhase.complete => l10n.watchGateComplete,
    LearningPhase.videoUnavailable =>
      gate.videoEnabled ? l10n.watchUnavailableTitle : l10n.watchDisabledTitle,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final progress = gate.sessionProgress;
    final watchedMinutes = (gate.watchedSecondsToday / 60).floor();
    final totalMinutes = (gate.dailyAllowanceSeconds / 60).round();

    return AppCard(
      key: const Key('watch.session'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.md,
        children: [
          SectionHeader(
            title: gate.firstSessionComplete
                ? l10n.watchSessionSecond
                : l10n.watchSessionFirst,
            trailing: gate.videoGateAvailable
                ? EyebrowPill(
                    label: l10n.watchTimeToday(watchedMinutes, totalMinutes),
                  )
                : null,
          ),
          Text(
            _headline(l10n),
            key: const Key('watch.headline'),
            style: context.text.titleMedium,
          ),
          // A progress bar only appears when the server is actually measuring
          // viewing time; otherwise there is nothing truthful to show.
          if (progress != null) ...[
            PillProgressBar(value: progress, semanticsLabel: _headline(l10n)),
            Text(
              l10n.watchMinutesLeft(
                (gate.secondsRemainingInSession / 60).ceil(),
              ),
              style: context.text.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
          if (gate.missionsUnlocked)
            PrimaryButton(
              key: const Key('watch.toMissions'),
              label: l10n.watchMissionsOpen,
              icon: Icons.rocket_launch_rounded,
              onPressed: () => context.go(AppRoutes.childMissions),
            ),
        ],
      ),
    );
  }
}

/// Says why the daily video gate is not running, without pretending otherwise.
class _UnavailableCard extends StatelessWidget {
  const _UnavailableCard({required this.gate});

  final LearningGate gate;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return InlineNotice(
      key: const Key('watch.unavailable'),
      icon: Icons.info_outline_rounded,
      message: gate.videoEnabled
          ? l10n.watchUnavailableBody
          : l10n.watchDisabledBody,
    );
  }
}

/// One curated video. Playback is not wired up: tapping opens the existing
/// Learn detail screen, which is the only place that can legitimately open an
/// admin-curated link today.
class _VideoTile extends StatelessWidget {
  const _VideoTile({required this.item});

  final LearningItem item;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;

    return AppCard(
      key: Key('watch.video.${item.id}'),
      padding: const EdgeInsets.all(AppSpacing.md),
      onTap: () => context.push(
        item.isPlayableInApp
            ? AppRoutes.childLearnPlay(item.id)
            : AppRoutes.childLearnItem(item.id),
        extra: item,
      ),
      child: Row(
        children: [
          _Thumbnail(item: item),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: AppSpacing.xs,
              children: [
                Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.titleMedium,
                ),
                EyebrowPill(label: learningTypeName(l10n, item.contentType)),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: colors.onSurfaceVariant),
        ],
      ),
    );
  }
}

/// Thumbnail with a play affordance, falling back to an icon when the curated
/// item has no image or the image cannot be loaded.
class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.item});

  final LearningItem item;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final url = item.thumbnailUrl;
    final placeholder = Icon(
      Icons.play_circle_rounded,
      size: 32,
      color: colors.primary,
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: ColoredBox(
        color: colors.primaryFixed,
        child: SizedBox(
          width: 96,
          height: 64,
          child: url == null || Uri.tryParse(url)?.scheme != 'https'
              ? Center(child: placeholder)
              : Image.network(
                  url,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Center(child: placeholder),
                ),
        ),
      ),
    );
  }
}
