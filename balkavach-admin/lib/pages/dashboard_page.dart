import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/api.dart';
import '../core/session.dart';
import '../l10n/app_localizations.dart';
import '../ui/widgets.dart';

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  int _days = 30;
  late Future<_Data> _future = _load();

  Future<_Data> _load() async {
    final api = ref.read(adminApiProvider);
    final session = ref.read(sessionProvider);
    final counts = await api.getMap('/api/v1/admin/dashboard');
    Map<String, dynamic>? analytics;
    if (session?.can('reports:read') ?? false) {
      analytics = await api.getMap(
        '/api/v1/admin/analytics/overview',
        query: {'days': _days},
      );
    }
    return _Data(counts, analytics);
  }

  void _reload() => setState(() {
    _future = _load();
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListView(
      children: [
        PageHeader(
          title: l10n.dashboardTitle,
          subtitle: l10n.dashboardSubtitle,
          actions: [
            SegmentedButton<int>(
              key: const Key('dashboard.range'),
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: 7, label: Text(l10n.range7)),
                ButtonSegment(value: 30, label: Text(l10n.range30)),
                ButtonSegment(value: 90, label: Text(l10n.range90)),
              ],
              selected: {_days},
              onSelectionChanged: (value) {
                _days = value.first;
                _reload();
              },
            ),
          ],
        ),
        AsyncBody<_Data>(
          future: _future,
          onRetry: _reload,
          builder: (context, data) => _Body(data: data),
        ),
      ],
    );
  }
}

class _Data {
  const _Data(this.counts, this.analytics);

  final Map<String, dynamic> counts;
  final Map<String, dynamic>? analytics;
}

class _Body extends ConsumerWidget {
  const _Body({required this.data});

  final _Data data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final session = ref.watch(sessionProvider);
    final counts = data.counts;
    int count(String key) => counts[key] as int? ?? 0;
    // (key, label, value, icon, destination, permission to open it)
    final tiles = <(String, String, int, IconData, String, String)>[
      (
        'users',
        l10n.tileUsers,
        count('users'),
        Icons.people_outline_rounded,
        '/users',
        'users:read',
      ),
      (
        'families',
        l10n.tileFamilies,
        count('families'),
        Icons.family_restroom_rounded,
        '/families',
        'families:read',
      ),
      (
        'children',
        l10n.tileChildren,
        count('children'),
        Icons.child_care_rounded,
        '/families',
        'families:read',
      ),
      (
        'tasks',
        l10n.tileMissions,
        count('active_tasks'),
        Icons.task_alt_rounded,
        '/missions',
        'tasks:read',
      ),
      (
        'videos',
        l10n.tileVideos,
        count('published_videos'),
        Icons.play_circle_outline_rounded,
        '/content',
        'content:read',
      ),
      (
        'redemptions',
        l10n.tileRedemptions,
        count('pending_redemptions'),
        Icons.inbox_rounded,
        '/redemptions',
        'redemptions:read',
      ),
    ];
    final analytics = data.analytics;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, box) {
            final columns = box.maxWidth >= 900
                ? 3
                : box.maxWidth >= 520
                ? 2
                : 1;
            const gap = 12.0;
            final width = (box.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final (key, label, value, icon, path, permission) in tiles)
                  SizedBox(
                    width: width,
                    child: StatCard(
                      key: Key('tile.$key'),
                      icon: icon,
                      label: label,
                      value: '$value',
                      highlight: key == 'redemptions' && value > 0,
                      onTap: session?.can(permission) ?? false
                          ? () => context.go(path)
                          : null,
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        const _SystemStatus(),
        if (analytics != null) ...[
          const SizedBox(height: 16),
          _Activity(analytics: analytics),
        ],
      ],
    );
  }
}

/// Live API and database availability from the public health endpoints.
class _SystemStatus extends ConsumerStatefulWidget {
  const _SystemStatus();

  @override
  ConsumerState<_SystemStatus> createState() => _SystemStatusState();
}

class _SystemStatusState extends ConsumerState<_SystemStatus> {
  late Future<(bool, bool)> _future = _check();

  Future<(bool, bool)> _check() async {
    final api = ref.read(adminApiProvider);
    Future<bool> ok(String path) async {
      try {
        await api.anonymousGet(path);
        return true;
      } on ApiError {
        return false;
      }
    }

    final results = await Future.wait([ok('/health'), ok('/ready')]);
    return (results[0], results[1]);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SectionCard(
      title: l10n.systemTitle,
      trailing: IconButton(
        key: const Key('system.refresh'),
        tooltip: l10n.systemRefresh,
        icon: const Icon(Icons.refresh_rounded),
        onPressed: () => setState(() => _future = _check()),
      ),
      child: FutureBuilder<(bool, bool)>(
        future: _future,
        builder: (context, snapshot) {
          final data = snapshot.data;
          if (data == null) return Text(l10n.systemChecking);
          final (api, database) = data;
          return Wrap(
            key: const Key('system.status'),
            spacing: 24,
            runSpacing: 8,
            children: [
              _StatusLine(label: l10n.systemApi, up: api),
              _StatusLine(label: l10n.systemDatabase, up: database),
            ],
          );
        },
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.label, required this.up});

  final String label;
  final bool up;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(label),
        StatusPill(label: up ? l10n.systemUp : l10n.systemDown, good: up),
      ],
    );
  }
}

class _Activity extends StatelessWidget {
  const _Activity({required this.analytics});

  final Map<String, dynamic> analytics;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final totals = analytics['totals'] as Map<String, dynamic>;
    final daily = (analytics['daily'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    final statuses =
        (analytics['redemptions_by_status'] as Map<String, dynamic>);
    final top = (analytics['top_categories'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    final peak = daily.fold<int>(1, (m, d) {
      final value = (d['submissions'] as int? ?? 0);
      return value > m ? value : m;
    });
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final statusLabels = {
      'pending': l10n.redemptionPending,
      'approved': l10n.redemptionApproved,
      'rejected': l10n.redemptionDeclined,
      'fulfilled': l10n.redemptionGiven,
      'cancelled': l10n.redemptionCancelled,
    };
    final totalChips = [
      l10n.activityNewUsers('${totals['new_users']}'),
      l10n.activitySubmissions('${totals['submissions']}'),
      l10n.activityApprovals('${totals['approvals']}'),
      l10n.activityRejections('${totals['rejections']}'),
      l10n.activityRedemptions('${totals['redemptions']}'),
    ];
    return SectionCard(
      title: l10n.activityTitle('${analytics['period_days']}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            key: const Key('analytics.totals'),
            children: [
              for (final label in totalChips)
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    child: Text(label, style: text.labelMedium),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Text(l10n.activityChartTitle, style: text.titleSmall),
          Text(
            l10n.activityPeak('$peak'),
            style: text.bodySmall?.copyWith(color: scheme.outline),
          ),
          const SizedBox(height: 8),
          Semantics(
            label: l10n.activityChartTitle,
            child: SizedBox(
              height: 120,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final day in daily)
                    Expanded(
                      child: Tooltip(
                        message: l10n.activityDayTooltip(
                          '${day['date']}',
                          '${day['submissions']}',
                          '${day['approvals']}',
                        ),
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: FractionallySizedBox(
                            heightFactor:
                                ((day['submissions'] as int? ?? 0) / peak)
                                    .clamp(0.02, 1.0),
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 1),
                              decoration: BoxDecoration(
                                color: scheme.primaryContainer,
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(3),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (daily.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      '${daily.first['date']}',
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall?.copyWith(color: scheme.outline),
                    ),
                  ),
                  Flexible(
                    child: Text(
                      '${daily.last['date']}',
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall?.copyWith(color: scheme.outline),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 48,
            runSpacing: 16,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.activityByStatus, style: text.titleSmall),
                  const SizedBox(height: 4),
                  for (final entry in statuses.entries)
                    Text(
                      '${statusLabels[entry.key] ?? entry.key}: ${entry.value}',
                    ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.activityTopCategories, style: text.titleSmall),
                  const SizedBox(height: 4),
                  if (top.isEmpty) Text(l10n.activityNoApproved),
                  for (final row in top)
                    Text('${row['name']}: ${row['approved_tasks']}'),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
