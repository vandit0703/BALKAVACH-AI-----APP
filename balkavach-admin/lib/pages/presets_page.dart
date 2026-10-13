import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api.dart';
import '../core/session.dart';
import '../ui/widgets.dart';

const _languages = {
  'en': 'English',
  'hi': 'हिन्दी (Hindi)',
  'gu': 'ગુજરાતી (Gujarati)',
};

class PresetsPage extends ConsumerStatefulWidget {
  const PresetsPage({super.key});

  @override
  ConsumerState<PresetsPage> createState() => _PresetsPageState();
}

class _PresetsPageState extends ConsumerState<PresetsPage> {
  int _reload = 0;

  Future<Map<String, String>> _categoryOptions() async {
    final rows = await ref
        .read(adminApiProvider)
        .getList('/api/v1/admin/task-categories');
    return {
      '': 'No category',
      for (final row in rows)
        if (row['is_active'] == true)
          row['id'] as String: row['name'] as String,
    };
  }

  List<FormFieldSpec> _fields(
    Map<String, String> categories, [
    Map<String, dynamic>? row,
  ]) => [
    FormFieldSpec(
      key: 'title',
      label: 'Title',
      required: true,
      maxLength: 180,
      initial: row?['title'],
    ),
    FormFieldSpec(
      key: 'description',
      label: 'Description',
      kind: FieldKind.multiline,
      maxLength: 5000,
      initial: row?['description'],
    ),
    FormFieldSpec(
      key: 'category_id',
      label: 'Category',
      kind: FieldKind.choice,
      options: categories,
      initial: row?['category_id'],
    ),
    FormFieldSpec(
      key: 'language_code',
      label: 'Language',
      kind: FieldKind.choice,
      required: true,
      options: _languages,
      initial: row?['language_code'] ?? 'en',
    ),
    FormFieldSpec(
      key: 'suggested_star_reward',
      label: 'Suggested stars',
      kind: FieldKind.integer,
      min: 0,
      max: 10000,
      initial: row?['suggested_star_reward'] ?? 1,
    ),
    FormFieldSpec(
      key: 'suggested_xp_reward',
      label: 'Suggested XP',
      kind: FieldKind.integer,
      min: 0,
      max: 100000,
      initial: row?['suggested_xp_reward'] ?? 10,
    ),
    FormFieldSpec(
      key: 'age_min',
      label: 'Youngest age',
      kind: FieldKind.integer,
      min: 0,
      max: 18,
      initial: row?['age_min'] ?? 3,
    ),
    FormFieldSpec(
      key: 'age_max',
      label: 'Oldest age',
      kind: FieldKind.integer,
      min: 0,
      max: 18,
      initial: row?['age_max'] ?? 17,
    ),
    if (row != null)
      FormFieldSpec(
        key: 'is_active',
        label: 'Offered to parents',
        kind: FieldKind.toggle,
        initial: row['is_active'],
      ),
  ];

  Future<void> _create() async {
    final Map<String, String> categories;
    try {
      categories = await _categoryOptions();
    } on ApiError catch (error) {
      if (mounted) showMessage(context, ErrorBox.describe(error));
      return;
    }
    if (!mounted) return;
    final values = await showFormDialog(
      context,
      title: 'New preset mission',
      fields: _fields(categories),
    );
    if (values == null || !mounted) return;
    final done = await runAction(
      context,
      () =>
          ref.read(adminApiProvider).post('/api/v1/admin/preset-tasks', values),
      success: 'Preset created',
    );
    if (done) setState(() => _reload++);
  }

  Future<void> _edit(Map<String, dynamic> row) async {
    final Map<String, String> categories;
    try {
      categories = await _categoryOptions();
    } on ApiError catch (error) {
      if (mounted) showMessage(context, ErrorBox.describe(error));
      return;
    }
    if (!mounted) return;
    final values = await showFormDialog(
      context,
      title: 'Edit preset mission',
      fields: _fields(categories, row),
    );
    if (values == null || !mounted) return;
    final done = await runAction(
      context,
      () => ref
          .read(adminApiProvider)
          .patch('/api/v1/admin/preset-tasks/${row['id']}', values),
      success: 'Preset saved',
    );
    if (done) setState(() => _reload++);
  }

  @override
  Widget build(BuildContext context) {
    final canWrite = ref.watch(sessionProvider)?.can('content:write') ?? false;
    return ListView(
      children: [
        PageHeader(
          title: 'Preset missions',
          subtitle:
              'Ready-made ideas parents can start a mission from. The reward values are only suggestions.',
          actions: [
            if (canWrite)
              FilledButton.icon(
                key: const Key('presets.add'),
                onPressed: _create,
                icon: const Icon(Icons.add_rounded),
                label: const Text('New preset'),
              ),
          ],
        ),
        PagedTable(
          reloadKey: _reload,
          fetch: (offset, limit) => ref
              .read(adminApiProvider)
              .getList(
                '/api/v1/admin/preset-tasks',
                query: {'limit': limit, 'offset': offset},
              ),
          columns: const [
            'Title',
            'Category',
            'Language',
            'Stars / XP',
            'Ages',
            'Status',
            '',
          ],
          cells: (context, row, reload) => [
            Text('${row['title']}'),
            Text('${row['category_name'] ?? '—'}'),
            Text('${_languages[row['language_code']] ?? row['language_code']}'),
            Text(
              '${row['suggested_star_reward']} / ${row['suggested_xp_reward']}',
            ),
            Text('${row['age_min']}–${row['age_max']}'),
            StatusPill(
              label: row['is_active'] == true ? 'Offered' : 'Hidden',
              good: row['is_active'] == true,
            ),
            if (canWrite)
              TextButton(
                key: Key('preset.edit.${row['id']}'),
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
