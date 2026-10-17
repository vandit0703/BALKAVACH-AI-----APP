import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api.dart';
import '../core/session.dart';
import '../l10n/app_localizations.dart';
import '../ui/widgets.dart';

class BadgesPage extends ConsumerStatefulWidget {
  const BadgesPage({super.key});

  @override
  ConsumerState<BadgesPage> createState() => _BadgesPageState();
}

class _BadgesPageState extends ConsumerState<BadgesPage> {
  int _reload = 0;

  Map<String, String> _criteria(AppLocalizations l10n) => {
    'approved_tasks': l10n.badgeCriteriaApprovedTasks,
    'total_stars': l10n.badgeCriteriaTotalStars,
    'total_xp': l10n.badgeCriteriaTotalXp,
    'current_streak': l10n.badgeCriteriaStreak,
  };

  List<FormFieldSpec> _fields(
    AppLocalizations l10n, [
    Map<String, dynamic>? row,
  ]) => [
    FormFieldSpec(
      key: 'name',
      label: l10n.fieldName,
      required: true,
      maxLength: 100,
      initial: row?['name'],
    ),
    FormFieldSpec(
      key: 'description',
      label: l10n.fieldDescription,
      kind: FieldKind.multiline,
      maxLength: 2000,
      initial: row?['description'],
    ),
    FormFieldSpec(
      key: 'criteria_type',
      label: l10n.badgeEarnedBy,
      kind: FieldKind.choice,
      required: true,
      options: _criteria(l10n),
      initial: row?['criteria_type'],
    ),
    FormFieldSpec(
      key: 'threshold',
      label: l10n.badgeAmountNeeded,
      kind: FieldKind.integer,
      required: true,
      min: 1,
      max: 1000000,
      initial: (row?['criteria_value'] as Map<String, dynamic>?)?['threshold'],
    ),
    if (row != null)
      FormFieldSpec(
        key: 'is_active',
        label: l10n.badgeCanBeEarned,
        kind: FieldKind.toggle,
        initial: row['is_active'],
      ),
  ];

  Future<void> _create() async {
    final l10n = AppLocalizations.of(context);
    final values = await showFormDialog(
      context,
      title: l10n.badgeNewTitle,
      fields: _fields(l10n),
    );
    if (values == null || !mounted) return;
    final done = await runAction(
      context,
      () => ref.read(adminApiProvider).post('/api/v1/admin/badges', values),
      success: l10n.badgeCreated,
    );
    if (done) setState(() => _reload++);
  }

  Future<void> _edit(Map<String, dynamic> row) async {
    final l10n = AppLocalizations.of(context);
    final values = await showFormDialog(
      context,
      title: l10n.badgeEditTitle,
      fields: _fields(l10n, row),
    );
    if (values == null || !mounted) return;
    final done = await runAction(
      context,
      () => ref
          .read(adminApiProvider)
          .patch('/api/v1/admin/badges/${row['id']}', values),
      success: l10n.badgeSaved,
    );
    if (done) setState(() => _reload++);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final canWrite = ref.watch(sessionProvider)?.can('badges:write') ?? false;
    final criteria = _criteria(l10n);
    return ListView(
      children: [
        PageHeader(
          title: l10n.badgesTitle,
          subtitle: l10n.badgesSubtitle,
          actions: [
            if (canWrite)
              FilledButton.icon(
                key: const Key('badges.add'),
                onPressed: _create,
                icon: const Icon(Icons.add_rounded),
                label: Text(l10n.badgeNewTitle),
              ),
          ],
        ),
        PagedTable(
          reloadKey: _reload,
          fetch: (offset, limit) async {
            final all = await ref
                .read(adminApiProvider)
                .getList('/api/v1/admin/badges');
            return all.skip(offset).take(limit).toList();
          },
          columns: [
            l10n.colName,
            l10n.badgeEarnedBy,
            l10n.colAmount,
            l10n.colStatus,
            '',
          ],
          cells: (context, row, reload) => [
            Text('${row['name']}'),
            Text('${criteria[row['criteria_type']] ?? row['criteria_type']}'),
            Text(
              '${(row['criteria_value'] as Map<String, dynamic>?)?['threshold'] ?? '—'}',
            ),
            StatusPill(
              label: row['is_active'] == true
                  ? l10n.statusActive
                  : l10n.statusOff,
              good: row['is_active'] == true,
            ),
            if (canWrite)
              TextButton(
                key: Key('badge.edit.${row['id']}'),
                onPressed: () => _edit(row),
                child: Text(l10n.actionEdit),
              )
            else
              const SizedBox.shrink(),
          ],
        ),
      ],
    );
  }
}
