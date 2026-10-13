import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api.dart';
import '../core/session.dart';
import '../ui/widgets.dart';

const _criteria = {
  'approved_tasks': 'Approved missions',
  'total_stars': 'Total stars',
  'total_xp': 'Total XP',
  'current_streak': 'Day streak',
};

class BadgesPage extends ConsumerStatefulWidget {
  const BadgesPage({super.key});

  @override
  ConsumerState<BadgesPage> createState() => _BadgesPageState();
}

class _BadgesPageState extends ConsumerState<BadgesPage> {
  int _reload = 0;

  Future<void> _create() async {
    final values = await showFormDialog(
      context,
      title: 'New badge',
      fields: const [
        FormFieldSpec(
          key: 'name',
          label: 'Name',
          required: true,
          maxLength: 100,
        ),
        FormFieldSpec(
          key: 'description',
          label: 'Description',
          kind: FieldKind.multiline,
          maxLength: 2000,
        ),
        FormFieldSpec(
          key: 'criteria_type',
          label: 'Earned by',
          kind: FieldKind.choice,
          required: true,
          options: _criteria,
        ),
        FormFieldSpec(
          key: 'threshold',
          label: 'Amount needed',
          kind: FieldKind.integer,
          required: true,
          min: 1,
          max: 1000000,
        ),
      ],
    );
    if (values == null || !mounted) return;
    final done = await runAction(
      context,
      () => ref.read(adminApiProvider).post('/api/v1/admin/badges', values),
      success: 'Badge created',
    );
    if (done) setState(() => _reload++);
  }

  Future<void> _edit(Map<String, dynamic> row) async {
    final threshold =
        (row['criteria_value'] as Map<String, dynamic>?)?['threshold'];
    final values = await showFormDialog(
      context,
      title: 'Edit badge',
      fields: [
        FormFieldSpec(
          key: 'name',
          label: 'Name',
          required: true,
          maxLength: 100,
          initial: row['name'],
        ),
        FormFieldSpec(
          key: 'description',
          label: 'Description',
          kind: FieldKind.multiline,
          maxLength: 2000,
          initial: row['description'],
        ),
        FormFieldSpec(
          key: 'criteria_type',
          label: 'Earned by',
          kind: FieldKind.choice,
          required: true,
          options: _criteria,
          initial: row['criteria_type'],
        ),
        FormFieldSpec(
          key: 'threshold',
          label: 'Amount needed',
          kind: FieldKind.integer,
          required: true,
          min: 1,
          max: 1000000,
          initial: threshold,
        ),
        FormFieldSpec(
          key: 'is_active',
          label: 'Can be earned',
          kind: FieldKind.toggle,
          initial: row['is_active'],
        ),
      ],
    );
    if (values == null || !mounted) return;
    final done = await runAction(
      context,
      () => ref
          .read(adminApiProvider)
          .patch('/api/v1/admin/badges/${row['id']}', values),
      success: 'Badge saved',
    );
    if (done) setState(() => _reload++);
  }

  @override
  Widget build(BuildContext context) {
    final canWrite = ref.watch(sessionProvider)?.can('badges:write') ?? false;
    return ListView(
      children: [
        PageHeader(
          title: 'Badges',
          subtitle:
              'Awarded automatically when a child reaches the amount. Garden decorations unlock with the default badges.',
          actions: [
            if (canWrite)
              FilledButton.icon(
                key: const Key('badges.add'),
                onPressed: _create,
                icon: const Icon(Icons.add_rounded),
                label: const Text('New badge'),
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
          columns: const ['Name', 'Earned by', 'Amount', 'Status', ''],
          cells: (context, row, reload) => [
            Text('${row['name']}'),
            Text('${_criteria[row['criteria_type']] ?? row['criteria_type']}'),
            Text(
              '${(row['criteria_value'] as Map<String, dynamic>?)?['threshold'] ?? '—'}',
            ),
            StatusPill(
              label: row['is_active'] == true ? 'Active' : 'Off',
              good: row['is_active'] == true,
            ),
            if (canWrite)
              TextButton(
                key: Key('badge.edit.${row['id']}'),
                onPressed: () => _edit(row),
                child: const Text('Edit'),
              )
            else
              const SizedBox.shrink(),
          ],
        ),
      ],
    );
  }
}
