import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api.dart';
import '../core/session.dart';
import '../ui/widgets.dart';

class RewardsPage extends ConsumerWidget {
  const RewardsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canWrite = ref.watch(sessionProvider)?.can('rewards:write') ?? false;
    return ListView(
      children: [
        const PageHeader(
          title: 'Rewards',
          subtitle:
              'Rewards created by families. Parents manage their own; hide one here if needed.',
        ),
        PagedTable(
          emptyMessage: 'No rewards yet.',
          fetch: (offset, limit) => ref
              .read(adminApiProvider)
              .getList(
                '/api/v1/admin/rewards',
                query: {'limit': limit, 'offset': offset},
              ),
          columns: const [
            'Reward',
            'Family',
            'Type',
            'Star cost',
            'Status',
            '',
          ],
          cells: (context, row, reload) {
            final active = row['is_active'] == true;
            return [
              Text('${row['name']}'),
              Text('${row['family_name']}'),
              Text('${row['reward_type']}'),
              Text('${row['star_cost']}'),
              StatusPill(label: active ? 'Active' : 'Hidden', good: active),
              if (canWrite)
                TextButton(
                  key: Key('reward.toggle.${row['id']}'),
                  onPressed: () async {
                    final ok = await confirm(
                      context,
                      title: active ? 'Hide reward?' : 'Show reward?',
                      body: '"${row['name']}" from ${row['family_name']}.',
                      confirmLabel: active ? 'Hide' : 'Show',
                    );
                    if (!ok || !context.mounted) return;
                    final done = await runAction(
                      context,
                      () => ref.read(adminApiProvider).patch(
                        '/api/v1/admin/rewards/${row['id']}/active',
                        {'is_active': !active},
                      ),
                      success: active ? 'Reward hidden' : 'Reward shown',
                    );
                    if (done) reload();
                  },
                  child: Text(active ? 'Hide' : 'Show'),
                )
              else
                const SizedBox.shrink(),
            ];
          },
        ),
      ],
    );
  }
}

/// Read-only: a family decides its own reward requests.
class RedemptionsPage extends ConsumerStatefulWidget {
  const RedemptionsPage({super.key});

  @override
  ConsumerState<RedemptionsPage> createState() => _RedemptionsPageState();
}

class _RedemptionsPageState extends ConsumerState<RedemptionsPage> {
  String _status = '';

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const PageHeader(
          title: 'Reward requests',
          subtitle:
              'Read-only. Parents approve or decline their own children\'s requests.',
        ),
        DropdownButton<String>(
          key: const Key('redemptions.status'),
          value: _status,
          items: const [
            DropdownMenuItem(value: '', child: Text('All statuses')),
            DropdownMenuItem(value: 'pending', child: Text('Pending')),
            DropdownMenuItem(value: 'approved', child: Text('Approved')),
            DropdownMenuItem(value: 'rejected', child: Text('Declined')),
            DropdownMenuItem(value: 'fulfilled', child: Text('Given')),
            DropdownMenuItem(value: 'cancelled', child: Text('Cancelled')),
          ],
          onChanged: (v) => setState(() => _status = v ?? ''),
        ),
        const SizedBox(height: 12),
        PagedTable(
          reloadKey: _status,
          emptyMessage: 'No reward requests.',
          fetch: (offset, limit) => ref
              .read(adminApiProvider)
              .getList(
                '/api/v1/admin/redemptions',
                query: {
                  'limit': limit,
                  'offset': offset,
                  if (_status.isNotEmpty) 'status': _status,
                },
              ),
          columns: const [
            'Reward',
            'Child',
            'Family',
            'Stars',
            'Status',
            'Requested',
          ],
          cells: (context, row, reload) => [
            Text('${row['reward_name']}'),
            Text('${row['child_name']}'),
            Text('${row['family_name']}'),
            Text('${row['star_cost_at_request']}'),
            StatusPill(
              label: '${row['status']}',
              good: row['status'] != 'rejected' && row['status'] != 'cancelled',
            ),
            Text(shortDate(row['requested_at'])),
          ],
        ),
      ],
    );
  }
}
