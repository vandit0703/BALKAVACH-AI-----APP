import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api.dart';
import '../core/session.dart';
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
    return ListView(
      children: [
        PageHeader(
          title: 'Dashboard',
          subtitle: 'A snapshot of how Bal Kavach is being used',
          actions: [
            SegmentedButton<int>(
              key: const Key('dashboard.range'),
              segments: const [
                ButtonSegment(value: 7, label: Text('7 days')),
                ButtonSegment(value: 30, label: Text('30 days')),
                ButtonSegment(value: 90, label: Text('90 days')),
              ],
              selected: {_days},
              onSelectionChanged: (value) {
                _days = value.first;
                _reload();
              },
            ),
          ],
        ),
        FutureBuilder<_Data>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return ErrorBox(error: snapshot.error!, onRetry: _reload);
            }
            final data = snapshot.data;
            if (data == null) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
              );
            }
            return _Body(data: data);
          },
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

class _Body extends StatelessWidget {
  const _Body({required this.data});

  final _Data data;

  @override
  Widget build(BuildContext context) {
    final counts = data.counts;
    final tiles = <(String, String, int)>[
      ('users', 'Users', counts['users'] as int? ?? 0),
      ('families', 'Families', counts['families'] as int? ?? 0),
      ('children', 'Active children', counts['children'] as int? ?? 0),
      ('tasks', 'Active missions', counts['active_tasks'] as int? ?? 0),
      ('videos', 'Published videos', counts['published_videos'] as int? ?? 0),
      (
        'redemptions',
        'Pending reward requests',
        counts['pending_redemptions'] as int? ?? 0,
      ),
    ];
    final analytics = data.analytics;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final (key, label, value) in tiles)
              SizedBox(
                width: 200,
                child: Card(
                  key: Key('tile.$key'),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$value',
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        Text(label),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
        if (analytics != null) ...[
          const SizedBox(height: 24),
          _Activity(analytics: analytics),
        ],
      ],
    );
  }
}

class _Activity extends StatelessWidget {
  const _Activity({required this.analytics});

  final Map<String, dynamic> analytics;

  @override
  Widget build(BuildContext context) {
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Last ${analytics['period_days']} days',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 24,
          runSpacing: 4,
          key: const Key('analytics.totals'),
          children: [
            Text('New users: ${totals['new_users']}'),
            Text('Submissions: ${totals['submissions']}'),
            Text('Approvals: ${totals['approvals']}'),
            Text('Rejections: ${totals['rejections']}'),
            Text('Reward requests: ${totals['redemptions']}'),
          ],
        ),
        const SizedBox(height: 16),
        Semantics(
          label: 'Daily submissions chart',
          child: SizedBox(
            height: 120,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final day in daily)
                  Expanded(
                    child: Tooltip(
                      message:
                          '${day['date']}: ${day['submissions']} submitted, ${day['approvals']} approved',
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: FractionallySizedBox(
                          heightFactor:
                              ((day['submissions'] as int? ?? 0) / peak).clamp(
                                0.02,
                                1.0,
                              ),
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 1),
                            color: scheme.primary,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 32,
          runSpacing: 12,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Reward requests by status',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                for (final entry in statuses.entries)
                  Text('${entry.key}: ${entry.value}'),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Top categories (approved missions)',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                if (top.isEmpty) const Text('No approved missions yet.'),
                for (final row in top)
                  Text('${row['name']}: ${row['approved_tasks']}'),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
