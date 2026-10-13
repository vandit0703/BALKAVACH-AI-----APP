import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api.dart';
import '../core/session.dart';
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
    final canWrite = ref.watch(sessionProvider)?.can('tasks:write') ?? false;
    return ListView(
      children: [
        const PageHeader(
          title: 'Missions',
          subtitle:
              'Every family mission. Deactivating hides it from the child.',
        ),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 280,
              child: TextField(
                key: const Key('missions.search'),
                controller: _search,
                decoration: const InputDecoration(
                  labelText: 'Search title',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
                onSubmitted: (v) => setState(() => _query = v.trim()),
              ),
            ),
            DropdownButton<String>(
              key: const Key('missions.state'),
              value: _state,
              items: const [
                DropdownMenuItem(value: '', child: Text('All')),
                DropdownMenuItem(value: 'true', child: Text('Active')),
                DropdownMenuItem(value: 'false', child: Text('Deactivated')),
              ],
              onChanged: (v) => setState(() => _state = v ?? ''),
            ),
            FilledButton.tonal(
              key: const Key('missions.apply'),
              onPressed: () => setState(() => _query = _search.text.trim()),
              child: const Text('Search'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        PagedTable(
          reloadKey: '$_query|$_state',
          emptyMessage: 'No missions match.',
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
          columns: const [
            'Mission',
            'Family',
            'Category',
            'Child',
            'Stars / XP',
            'Status',
            '',
          ],
          cells: (context, row, reload) {
            final active = row['is_active'] == true;
            return [
              Text('${row['title']}'),
              Text('${row['family_name']}'),
              Text('${row['category_name'] ?? '—'}'),
              Text('${row['assigned_child_name'] ?? 'Any child'}'),
              Text('${row['star_reward']} / ${row['xp_reward']}'),
              StatusPill(
                label: active ? 'Active' : 'Deactivated',
                good: active,
              ),
              if (canWrite)
                TextButton(
                  key: Key('mission.toggle.${row['id']}'),
                  onPressed: () async {
                    final ok = await confirm(
                      context,
                      title: active
                          ? 'Deactivate mission?'
                          : 'Reactivate mission?',
                      body: '"${row['title']}" in ${row['family_name']}.',
                      confirmLabel: active ? 'Deactivate' : 'Reactivate',
                    );
                    if (!ok || !context.mounted) return;
                    final done = await runAction(
                      context,
                      () => ref.read(adminApiProvider).patch(
                        '/api/v1/admin/tasks/${row['id']}/active',
                        {'is_active': !active},
                      ),
                      success: active
                          ? 'Mission deactivated'
                          : 'Mission reactivated',
                    );
                    if (done) reload();
                  },
                  child: Text(active ? 'Deactivate' : 'Reactivate'),
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
