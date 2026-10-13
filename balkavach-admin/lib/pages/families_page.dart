import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api.dart';
import '../core/session.dart';
import '../ui/widgets.dart';

class FamiliesPage extends ConsumerStatefulWidget {
  const FamiliesPage({super.key});

  @override
  ConsumerState<FamiliesPage> createState() => _FamiliesPageState();
}

class _FamiliesPageState extends ConsumerState<FamiliesPage> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _open(Map<String, dynamic> family) async {
    final api = ref.read(adminApiProvider);
    try {
      final detail = await api.getMap('/api/v1/admin/families/${family['id']}');
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => _FamilyDialog(detail: detail),
      );
    } on ApiError catch (error) {
      if (mounted) showMessage(context, ErrorBox.describe(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const PageHeader(
          title: 'Families',
          subtitle: 'Households, their parents and children',
        ),
        Row(
          children: [
            SizedBox(
              width: 280,
              child: TextField(
                key: const Key('families.search'),
                controller: _search,
                decoration: const InputDecoration(
                  labelText: 'Search family name',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
                onSubmitted: (v) => setState(() => _query = v.trim()),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.tonal(
              key: const Key('families.apply'),
              onPressed: () => setState(() => _query = _search.text.trim()),
              child: const Text('Search'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        PagedTable(
          reloadKey: _query,
          emptyMessage: 'No families match.',
          fetch: (offset, limit) => ref
              .read(adminApiProvider)
              .getList(
                '/api/v1/admin/families',
                query: {
                  'limit': limit,
                  'offset': offset,
                  if (_query.isNotEmpty) 'q': _query,
                },
              ),
          columns: const [
            'Family',
            'Parents',
            'Children',
            'Active missions',
            'Created',
            '',
          ],
          cells: (context, row, reload) => [
            Text('${row['family_name']}'),
            Text('${row['parent_count']}'),
            Text('${row['child_count']}'),
            Text('${row['active_task_count']}'),
            Text(shortDate(row['created_at'])),
            TextButton(
              key: Key('family.open.${row['id']}'),
              onPressed: () => _open(row),
              child: const Text('Details'),
            ),
          ],
        ),
      ],
    );
  }
}

class _FamilyDialog extends ConsumerStatefulWidget {
  const _FamilyDialog({required this.detail});

  final Map<String, dynamic> detail;

  @override
  ConsumerState<_FamilyDialog> createState() => _FamilyDialogState();
}

class _FamilyDialogState extends ConsumerState<_FamilyDialog> {
  late Map<String, dynamic> _detail = widget.detail;

  Future<void> _toggleChild(Map<String, dynamic> child) async {
    final active = child['is_active'] == true;
    final ok = await confirm(
      context,
      title: active
          ? 'Deactivate ${child['display_name']}?'
          : 'Reactivate ${child['display_name']}?',
      body: active
          ? 'The child is signed out everywhere and cannot sign in until reactivated. Their history is kept.'
          : 'The child can be started in child mode again.',
      confirmLabel: active ? 'Deactivate' : 'Reactivate',
    );
    if (!ok || !mounted) return;
    final api = ref.read(adminApiProvider);
    final done = await runAction(
      context,
      () => api.patch('/api/v1/admin/children/${child['id']}/status', {
        'is_active': !active,
      }),
      success: active ? 'Child deactivated' : 'Child reactivated',
    );
    if (!done || !mounted) return;
    final fresh = await api.getMap('/api/v1/admin/families/${_detail['id']}');
    if (mounted) setState(() => _detail = fresh);
  }

  @override
  Widget build(BuildContext context) {
    final canWrite = ref.watch(sessionProvider)?.can('families:write') ?? false;
    final parents = (_detail['parents'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    final children = (_detail['children'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    return AlertDialog(
      title: Text('${_detail['family_name']}'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Time zone: ${_detail['timezone']}'),
              const SizedBox(height: 12),
              Text('Parents', style: Theme.of(context).textTheme.titleSmall),
              for (final p in parents)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('${p['full_name']}'),
                  subtitle: Text('${p['email'] ?? '—'}'),
                  trailing: StatusPill(
                    label: p['is_active'] == true ? 'Active' : 'Deactivated',
                    good: p['is_active'] == true,
                  ),
                ),
              const SizedBox(height: 12),
              Text('Children', style: Theme.of(context).textTheme.titleSmall),
              if (children.isEmpty) const Text('No children yet.'),
              for (final c in children)
                ListTile(
                  key: Key('child.${c['id']}'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('${c['display_name']}'),
                  subtitle: Text('Added ${shortDate(c['created_at'])}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      StatusPill(
                        label: c['is_active'] == true
                            ? 'Active'
                            : 'Deactivated',
                        good: c['is_active'] == true,
                      ),
                      if (canWrite)
                        TextButton(
                          key: Key('child.toggle.${c['id']}'),
                          onPressed: () => _toggleChild(c),
                          child: Text(
                            c['is_active'] == true
                                ? 'Deactivate'
                                : 'Reactivate',
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
