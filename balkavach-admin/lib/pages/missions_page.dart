import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api.dart';
import '../core/session.dart';
import '../l10n/app_localizations.dart';
import '../ui/widgets.dart';

class MissionsPage extends ConsumerStatefulWidget {
  const MissionsPage({super.key});

  @override
  ConsumerState<MissionsPage> createState() => _MissionsPageState();
}

class _MissionsPageState extends ConsumerState<MissionsPage> {
  final _search = TextEditingController();
  String _query = '';
  String _state = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final canWrite = ref.watch(sessionProvider)?.can('tasks:write') ?? false;
    return ListView(
      children: [
        PageHeader(title: l10n.missionsTitle, subtitle: l10n.missionsSubtitle),
        FilterBar(
          searchKey: const Key('missions.search'),
          applyKey: const Key('missions.apply'),
          searchLabel: l10n.missionsSearch,
          controller: _search,
          onSearch: (v) => setState(() => _query = v),
          filters: [
            FilterDropdown(
              fieldKey: const Key('missions.state'),
              value: _state,
              options: {
                '': l10n.filterAll,
                'true': l10n.statusActive,
                'false': l10n.statusDeactivated,
              },
              onChanged: (v) => setState(() => _state = v),
            ),
          ],
        ),
        PagedTable(
          reloadKey: '$_query|$_state',
          emptyMessage: l10n.missionsEmpty,
          fetch: (offset, limit) => ref
              .read(adminApiProvider)
              .getList(
                '/api/v1/admin/tasks',
                query: {
                  'limit': limit,
                  'offset': offset,
                  if (_query.isNotEmpty) 'q': _query,
                  if (_state.isNotEmpty) 'is_active': _state,
                },
              ),
          columns: [
            l10n.colMission,
            l10n.colFamily,
            l10n.colCategory,
            l10n.colChild,
            l10n.colStarsXp,
            l10n.colStatus,
            '',
          ],
          cells: (context, row, reload) {
            final active = row['is_active'] == true;
            return [
              Text('${row['title']}'),
              Text('${row['family_name']}'),
              Text('${row['category_name'] ?? '—'}'),
              Text('${row['assigned_child_name'] ?? l10n.missionAnyChild}'),
              Text('${row['star_reward']} / ${row['xp_reward']}'),
              StatusPill(
                label: active ? l10n.statusActive : l10n.statusDeactivated,
                good: active,
              ),
              if (canWrite)
                TextButton(
                  key: Key('mission.toggle.${row['id']}'),
                  onPressed: () async {
                    final ok = await confirm(
                      context,
                      title: active
                          ? l10n.missionDeactivateTitle
                          : l10n.missionReactivateTitle,
                      body: l10n.missionConfirmBody(
                        '${row['title']}',
                        '${row['family_name']}',
                      ),
                      confirmLabel: active
                          ? l10n.actionDeactivate
                          : l10n.actionReactivate,
                    );
                    if (!ok || !context.mounted) return;
                    final done = await runAction(
                      context,
                      () => ref.read(adminApiProvider).patch(
                        '/api/v1/admin/tasks/${row['id']}/active',
                        {'is_active': !active},
                      ),
                      success: active
                          ? l10n.missionDeactivated
                          : l10n.missionReactivated,
                    );
                    if (done) reload();
                  },
                  child: Text(
                    active ? l10n.actionDeactivate : l10n.actionReactivate,
                  ),
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
