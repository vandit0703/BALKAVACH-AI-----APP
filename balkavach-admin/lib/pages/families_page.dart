import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api.dart';
import '../core/session.dart';
import '../l10n/app_localizations.dart';
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
      if (mounted) showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListView(
      children: [
        PageHeader(title: l10n.familiesTitle, subtitle: l10n.familiesSubtitle),
        FilterBar(
          searchKey: const Key('families.search'),
          applyKey: const Key('families.apply'),
          searchLabel: l10n.familiesSearch,
          controller: _search,
          onSearch: (v) => setState(() => _query = v),
        ),
        PagedTable(
          reloadKey: _query,
          emptyMessage: l10n.familiesEmpty,
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
          columns: [
            l10n.colFamily,
            l10n.colParents,
            l10n.colChildren,
            l10n.colActiveMissions,
            l10n.colCreated,
            '',
          ],
          cells: (context, row, reload) => [
            Text('${row['family_name']}'),
            Text('${row['parent_count']}'),
            Text('${row['child_count']}'),
            Text('${row['active_task_count']}'),
            Text(shortDate(context, row['created_at'])),
            TextButton(
              key: Key('family.open.${row['id']}'),
              onPressed: () => _open(row),
              child: Text(l10n.actionDetails),
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
    final l10n = AppLocalizations.of(context);
    final active = child['is_active'] == true;
    final name = '${child['display_name']}';
    final ok = await confirm(
      context,
      title: active
          ? l10n.childDeactivateTitle(name)
          : l10n.childReactivateTitle(name),
      body: active ? l10n.childDeactivateBody : l10n.childReactivateBody,
      confirmLabel: active ? l10n.actionDeactivate : l10n.actionReactivate,
    );
    if (!ok || !mounted) return;
    final api = ref.read(adminApiProvider);
    final done = await runAction(
      context,
      () => api.patch('/api/v1/admin/children/${child['id']}/status', {
        'is_active': !active,
      }),
      success: active ? l10n.childDeactivated : l10n.childReactivated,
    );
    if (!done || !mounted) return;
    try {
      final fresh = await api.getMap('/api/v1/admin/families/${_detail['id']}');
      if (mounted) setState(() => _detail = fresh);
    } on ApiError catch (error) {
      if (mounted) showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final canWrite = ref.watch(sessionProvider)?.can('families:write') ?? false;
    final parents = (_detail['parents'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    final children = (_detail['children'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    String status(bool active) =>
        active ? l10n.statusActive : l10n.statusDeactivated;
    return AlertDialog(
      title: Text('${_detail['family_name']}'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.familyTimeZone('${_detail['timezone']}')),
              const SizedBox(height: 12),
              Text(
                l10n.familyParents,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              for (final p in parents)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('${p['full_name']}'),
                  subtitle: Text('${p['email'] ?? '—'}'),
                  trailing: StatusPill(
                    label: status(p['is_active'] == true),
                    good: p['is_active'] == true,
                  ),
                ),
              const SizedBox(height: 12),
              Text(
                l10n.familyChildren,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              if (children.isEmpty) Text(l10n.familyNoChildren),
              for (final c in children)
                ListTile(
                  key: Key('child.${c['id']}'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('${c['display_name']}'),
                  subtitle: Text(
                    l10n.familyChildAdded(shortDate(context, c['created_at'])),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      StatusPill(
                        label: status(c['is_active'] == true),
                        good: c['is_active'] == true,
                      ),
                      if (canWrite)
                        TextButton(
                          key: Key('child.toggle.${c['id']}'),
                          onPressed: () => _toggleChild(c),
                          child: Text(
                            c['is_active'] == true
                                ? l10n.actionDeactivate
                                : l10n.actionReactivate,
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
          child: Text(l10n.actionClose),
        ),
      ],
    );
  }
}
