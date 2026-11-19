import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/state_views.dart';
import '../../approvals/presentation/approval_providers.dart';
import '../../authentication/presentation/session_controller.dart';
import '../../missions/data/missions_repository.dart';
import '../../missions/domain/mission_models.dart';
import '../../missions/presentation/mission_providers.dart';
import '../domain/notification_category.dart';

/// The notifications the signed-in role may read, from the existing
/// `GET /notifications` (the server already scopes them to the account).
AsyncValue<List<AppNotification>> _notificationsFor(
  WidgetRef ref,
  NotificationAudience audience,
) => audience == NotificationAudience.child
    ? ref.watch(childNotificationsProvider)
    : ref.watch(parentNotificationsProvider);

void _refresh(WidgetRef ref, NotificationAudience audience) =>
    audience == NotificationAudience.child
    ? ref.invalidate(childNotificationsProvider)
    : ref.invalidate(parentNotificationsProvider);

/// Bell with an unread count that opens the notification centre.
class NotificationBell extends ConsumerWidget {
  const NotificationBell({required this.audience, super.key});

  final NotificationAudience audience;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final unread =
        _notificationsFor(
          ref,
          audience,
        ).value?.where((n) => !n.isRead).length ??
        0;
    return IconButton(
      key: const Key('notifications.bell'),
      tooltip: l10n.notifTitle,
      onPressed: () => Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => NotificationCenterScreen(audience: audience),
        ),
      ),
      icon: Badge(
        isLabelVisible: unread > 0,
        label: Text(unread > 99 ? '99+' : '$unread'),
        child: const Icon(Icons.notifications_none_rounded),
      ),
    );
  }
}

class NotificationCenterScreen extends ConsumerStatefulWidget {
  const NotificationCenterScreen({required this.audience, super.key});

  final NotificationAudience audience;

  @override
  ConsumerState<NotificationCenterScreen> createState() =>
      _NotificationCenterScreenState();
}

class _NotificationCenterScreenState
    extends ConsumerState<NotificationCenterScreen> {
  NotificationCategory _filter = NotificationCategory.all;

  /// Ids read in this session, so the dot disappears at once and stays gone
  /// even before the list is reloaded.
  final _readHere = <String>{};

  bool _isRead(AppNotification n) => n.isRead || _readHere.contains(n.id);

  Future<void> _markRead(AppNotification n) async {
    if (_isRead(n)) return;
    setState(() => _readHere.add(n.id));
    try {
      await ref.read(missionsRepositoryProvider).markNotificationRead(n.id);
    } on ApiException {
      // Keep it unread so the child or parent can try again.
      if (mounted) setState(() => _readHere.remove(n.id));
    }
  }

  Future<void> _markAll(List<AppNotification> items) async {
    final unread = items.where((n) => !_isRead(n)).toList();
    await Future.wait(unread.map(_markRead));
    if (mounted) _refresh(ref, widget.audience);
  }

  void _open(AppNotification n) {
    unawaited(_markRead(n));
    context.go(
      locationFor(
        type: n.type,
        audience: widget.audience,
        relatedTaskId: n.relatedTaskId,
        childId: ref.read(sessionControllerProvider).value?.childId,
      ),
    );
  }

  String _label(AppLocalizations l10n, NotificationCategory c) => switch (c) {
    NotificationCategory.all => l10n.notifCatAll,
    NotificationCategory.missions => l10n.notifCatMissions,
    NotificationCategory.rewards => l10n.notifCatRewards,
    NotificationCategory.videos => l10n.notifCatVideos,
    NotificationCategory.streaks => l10n.notifCatStreaks,
    NotificationCategory.other => l10n.notifCatOther,
  };

  IconData _icon(NotificationCategory c) => switch (c) {
    NotificationCategory.missions => Icons.flag_rounded,
    NotificationCategory.rewards => Icons.card_giftcard_rounded,
    NotificationCategory.videos => Icons.play_circle_rounded,
    NotificationCategory.streaks => Icons.local_fire_department_rounded,
    _ => Icons.notifications_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final async = _notificationsFor(ref, widget.audience);
    final items = async.value ?? const <AppNotification>[];
    final present = {for (final n in items) categoryOf(n.type)};
    final shown = [
      for (final n in items)
        if (_filter == NotificationCategory.all ||
            categoryOf(n.type) == _filter)
          n,
    ];
    final anyUnread = items.any((n) => !_isRead(n));

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.notifTitle),
        actions: [
          if (anyUnread)
            IconButton(
              key: const Key('notifications.markAll'),
              tooltip: l10n.notifMarkAllRead,
              onPressed: () => _markAll(items),
              icon: const Icon(Icons.done_all_rounded),
            ),
        ],
      ),
      body: switch (async) {
        AsyncError(:final error) when items.isEmpty => ErrorView(
          error: error,
          onRetry: () => _refresh(ref, widget.audience),
        ),
        AsyncData() || AsyncError() => RefreshIndicator(
          onRefresh: () async => _refresh(ref, widget.audience),
          child: ListView(
            key: const Key('notifications.list'),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              if (present.length > 1)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: [
                      for (final c in [
                        NotificationCategory.all,
                        ...NotificationCategory.values.where(present.contains),
                      ])
                        ChoiceChip(
                          key: Key('notifications.filter.${c.name}'),
                          label: Text(_label(l10n, c)),
                          selected: _filter == c,
                          onSelected: (_) => setState(() => _filter = c),
                        ),
                    ],
                  ),
                ),
              if (items.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xl),
                  child: Text(
                    l10n.notifEmpty,
                    key: const Key('notifications.empty'),
                    textAlign: TextAlign.center,
                  ),
                )
              else if (shown.isEmpty)
                Text(
                  l10n.notifEmptyFiltered,
                  key: const Key('notifications.emptyFiltered'),
                  textAlign: TextAlign.center,
                )
              else
                for (final n in shown)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: _NotificationCard(
                      notification: n,
                      read: _isRead(n),
                      icon: _icon(categoryOf(n.type)),
                      onTap: () => _open(n),
                    ),
                  ),
            ],
          ),
        ),
        _ => const LoadingView(),
      },
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.notification,
    required this.read,
    required this.icon,
    required this.onTap,
  });

  final AppNotification notification;
  final bool read;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final when = DateFormat.MMMd(
      Localizations.localeOf(context).toString(),
    ).add_jm().format(notification.createdAt.toLocal());
    return Semantics(
      label: read ? null : l10n.notifUnread,
      child: AppCard(
        key: Key('notifications.item.${notification.id}'),
        onTap: onTap,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: colors.primary.withValues(alpha: 0.12),
              child: Icon(icon, color: colors.primary),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notification.title,
                    style: context.text.titleMedium?.copyWith(
                      fontWeight: read ? FontWeight.w500 : FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(notification.message, style: context.text.bodyMedium),
                  const SizedBox(height: AppSpacing.xs),
                  Text(when, style: context.text.bodySmall),
                ],
              ),
            ),
            if (!read)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Container(
                  key: Key('notifications.unreadDot.${notification.id}'),
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: colors.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
