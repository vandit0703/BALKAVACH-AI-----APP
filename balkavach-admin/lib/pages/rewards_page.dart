import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api.dart';
import '../core/session.dart';
import '../l10n/app_localizations.dart';
import '../ui/widgets.dart';

class RewardsPage extends ConsumerWidget {
  const RewardsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final canWrite = ref.watch(sessionProvider)?.can('rewards:write') ?? false;
    return ListView(
      children: [
        PageHeader(title: l10n.rewardsTitle, subtitle: l10n.rewardsSubtitle),
        PagedTable(
          emptyMessage: l10n.rewardsEmpty,
          fetch: (offset, limit) => ref
              .read(adminApiProvider)
              .getList(
                '/api/v1/admin/rewards',
                query: {'limit': limit, 'offset': offset},
              ),
          columns: [
            l10n.colReward,
            l10n.colFamily,
            l10n.colType,
            l10n.colStarCost,
            l10n.colStatus,
            '',
          ],
          cells: (context, row, reload) {
            final active = row['is_active'] == true;
            return [
              Text('${row['name']}'),
              Text('${row['family_name']}'),
              Text('${row['reward_type']}'),
              Text('${row['star_cost']}'),
              StatusPill(
                label: active ? l10n.statusActive : l10n.statusHidden,
                good: active,
              ),
              if (canWrite)
                TextButton(
                  key: Key('reward.toggle.${row['id']}'),
                  onPressed: () async {
                    final ok = await confirm(
                      context,
                      title: active
                          ? l10n.rewardHideTitle
                          : l10n.rewardShowTitle,
                      body: l10n.rewardConfirmBody(
                        '${row['name']}',
                        '${row['family_name']}',
                      ),
                      confirmLabel: active ? l10n.actionHide : l10n.actionShow,
                    );
                    if (!ok || !context.mounted) return;
                    final done = await runAction(
                      context,
                      () => ref.read(adminApiProvider).patch(
                        '/api/v1/admin/rewards/${row['id']}/active',
                        {'is_active': !active},
                      ),
                      success: active ? l10n.rewardHidden : l10n.rewardShown,
                    );
                    if (done) reload();
                  },
                  child: Text(active ? l10n.actionHide : l10n.actionShow),
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
    final l10n = AppLocalizations.of(context);
    final statuses = {
      'pending': l10n.redemptionPending,
      'approved': l10n.redemptionApproved,
      'rejected': l10n.redemptionDeclined,
      'fulfilled': l10n.redemptionGiven,
      'cancelled': l10n.redemptionCancelled,
    };
    return ListView(
      children: [
        PageHeader(
          title: l10n.redemptionsTitle,
          subtitle: l10n.redemptionsSubtitle,
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilterDropdown(
              fieldKey: const Key('redemptions.status'),
              value: _status,
              options: {'': l10n.redemptionAllStatuses, ...statuses},
              onChanged: (v) => setState(() => _status = v),
            ),
          ),
        ),
        PagedTable(
          reloadKey: _status,
          emptyMessage: l10n.redemptionsEmpty,
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
          columns: [
            l10n.colReward,
            l10n.colChild,
            l10n.colFamily,
            l10n.colStars,
            l10n.colStatus,
            l10n.colRequested,
          ],
          cells: (context, row, reload) => [
            Text('${row['reward_name']}'),
            Text('${row['child_name']}'),
            Text('${row['family_name']}'),
            Text('${row['star_cost_at_request']}'),
            StatusPill(
              label: statuses['${row['status']}'] ?? '${row['status']}',
              good: row['status'] != 'rejected' && row['status'] != 'cancelled',
            ),
            Text(shortDate(context, row['requested_at'])),
          ],
        ),
      ],
    );
  }
}
