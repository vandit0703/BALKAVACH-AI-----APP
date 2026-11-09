import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/buttons.dart';
import '../../../shared/widgets/state_views.dart';
import '../../learning/data/video_feed_repository.dart';

class ChildWatchHistoryScreen extends ConsumerWidget {
  const ChildWatchHistoryScreen({required this.childId, super.key});

  final String childId;

  Future<void> _authorizeReplay(
    BuildContext context,
    WidgetRef ref,
    String videoId,
  ) async {
    try {
      await ref
          .read(videoFeedRepositoryProvider)
          .authorizeReplay(childId, videoId);
      ref.invalidate(parentVideoHistoryProvider(childId));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).videoReplayEnabled),
          ),
        );
      }
    } on ApiException catch (error) {
      if (context.mounted) showErrorSnackBar(context, error);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final history = ref.watch(parentVideoHistoryProvider(childId));
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.parentWatchHistoryTitle),
        actions: [
          IconButton(
            tooltip: l10n.videoRetry,
            onPressed: () =>
                ref.invalidate(parentVideoHistoryProvider(childId)),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: switch (history) {
        AsyncData(value: final entries) when entries.isEmpty => EmptyView(
          message: l10n.parentWatchHistoryEmpty,
        ),
        AsyncData(value: final entries) => ListView.separated(
          padding: const EdgeInsets.all(AppSpacing.md),
          itemCount: entries.length,
          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
          itemBuilder: (context, index) {
            final entry = entries[index];
            final video = entry.video;
            final watchedAt = DateFormat.yMMMd(
              Localizations.localeOf(context).toString(),
            ).add_jm().format(entry.lastWatchedAt.toLocal());
            return AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: AppSpacing.sm,
                children: [
                  Text(video.title, style: context.text.titleMedium),
                  Text(watchedAt, style: context.text.bodySmall),
                  LinearProgressIndicator(
                    value: entry.completionPercentage / 100,
                    semanticsLabel: l10n.videoWatchProgress,
                  ),
                  Text('${entry.completionPercentage}%'),
                  if (entry.isCompleted)
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: SecondaryButton(
                        key: Key('watchHistory.replay.${video.id}'),
                        label: l10n.videoAllowReplay,
                        icon: Icons.replay_rounded,
                        dense: true,
                        onPressed: () =>
                            _authorizeReplay(context, ref, video.id),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
        AsyncError(:final error) => ErrorView(
          error: error,
          onRetry: () => ref.invalidate(parentVideoHistoryProvider(childId)),
        ),
        _ => const LoadingView(),
      },
    );
  }
}
