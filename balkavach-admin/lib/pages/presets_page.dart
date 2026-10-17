import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api.dart';
import '../core/locale.dart';
import '../core/session.dart';
import '../l10n/app_localizations.dart';
import '../ui/widgets.dart';

class PresetsPage extends ConsumerStatefulWidget {
  const PresetsPage({super.key});

  @override
  ConsumerState<PresetsPage> createState() => _PresetsPageState();
}

class _PresetsPageState extends ConsumerState<PresetsPage> {
  int _reload = 0;

  Future<Map<String, String>> _categoryOptions(AppLocalizations l10n) async {
    final rows = await ref
        .read(adminApiProvider)
        .getList('/api/v1/admin/task-categories');
    return {
      '': l10n.presetNoCategory,
      for (final row in rows)
        if (row['is_active'] == true)
          row['id'] as String: row['name'] as String,
    };
  }

  List<FormFieldSpec> _fields(
    AppLocalizations l10n,
    Map<String, String> categories, [
    Map<String, dynamic>? row,
  ]) => [
    FormFieldSpec(
      key: 'title',
      label: l10n.fieldTitle,
      required: true,
      maxLength: 180,
      initial: row?['title'],
    ),
    FormFieldSpec(
      key: 'description',
      label: l10n.fieldDescription,
      kind: FieldKind.multiline,
      maxLength: 5000,
      initial: row?['description'],
    ),
    FormFieldSpec(
      key: 'category_id',
      label: l10n.fieldCategory,
      kind: FieldKind.choice,
      options: categories,
      initial: row?['category_id'],
    ),
    FormFieldSpec(
      key: 'language_code',
      label: l10n.fieldLanguage,
      kind: FieldKind.choice,
      required: true,
      options: kLanguageNames,
      initial: row?['language_code'] ?? 'en',
    ),
    FormFieldSpec(
      key: 'suggested_star_reward',
      label: l10n.presetSuggestedStars,
      kind: FieldKind.integer,
      min: 0,
      max: 10000,
      initial: row?['suggested_star_reward'] ?? 1,
    ),
    FormFieldSpec(
      key: 'suggested_xp_reward',
      label: l10n.presetSuggestedXp,
      kind: FieldKind.integer,
      min: 0,
      max: 100000,
      initial: row?['suggested_xp_reward'] ?? 10,
    ),
    FormFieldSpec(
      key: 'age_min',
      label: l10n.presetYoungestAge,
      kind: FieldKind.integer,
      min: 0,
      max: 18,
      initial: row?['age_min'] ?? 3,
    ),
    FormFieldSpec(
      key: 'age_max',
      label: l10n.presetOldestAge,
      kind: FieldKind.integer,
      min: 0,
      max: 18,
      initial: row?['age_max'] ?? 17,
    ),
    if (row != null)
      FormFieldSpec(
        key: 'is_active',
        label: l10n.presetOffered,
        kind: FieldKind.toggle,
        initial: row['is_active'],
      ),
  ];

  Future<void> _create() async {
    final l10n = AppLocalizations.of(context);
    final Map<String, String> categories;
    try {
      categories = await _categoryOptions(l10n);
    } on ApiError catch (error) {
      if (mounted) showError(context, error);
      return;
    }
    if (!mounted) return;
    final values = await showFormDialog(
      context,
      title: l10n.presetNewTitle,
      fields: _fields(l10n, categories),
    );
    if (values == null || !mounted) return;
    final done = await runAction(
      context,
      () =>
          ref.read(adminApiProvider).post('/api/v1/admin/preset-tasks', values),
      success: l10n.presetCreated,
    );
    if (done) setState(() => _reload++);
  }

  Future<void> _edit(Map<String, dynamic> row) async {
    final l10n = AppLocalizations.of(context);
    final Map<String, String> categories;
    try {
      categories = await _categoryOptions(l10n);
    } on ApiError catch (error) {
      if (mounted) showError(context, error);
      return;
    }
    if (!mounted) return;
    final values = await showFormDialog(
      context,
      title: l10n.presetEditTitle,
      fields: _fields(l10n, categories, row),
    );
    if (values == null || !mounted) return;
    final done = await runAction(
      context,
      () => ref
          .read(adminApiProvider)
          .patch('/api/v1/admin/preset-tasks/${row['id']}', values),
      success: l10n.presetSaved,
    );
    if (done) setState(() => _reload++);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final canWrite = ref.watch(sessionProvider)?.can('content:write') ?? false;
    return ListView(
      children: [
        PageHeader(
          title: l10n.presetsTitle,
          subtitle: l10n.presetsSubtitle,
          actions: [
            if (canWrite)
              FilledButton.icon(
                key: const Key('presets.add'),
                onPressed: _create,
                icon: const Icon(Icons.add_rounded),
                label: Text(l10n.presetNewButton),
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
          columns: [
            l10n.fieldTitle,
            l10n.colCategory,
            l10n.fieldLanguage,
            l10n.colStarsXp,
            l10n.colAges,
            l10n.colStatus,
            '',
          ],
          cells: (context, row, reload) => [
            Text('${row['title']}'),
            Text('${row['category_name'] ?? '—'}'),
            Text(
              '${kLanguageNames[row['language_code']] ?? row['language_code']}',
            ),
            Text(
              '${row['suggested_star_reward']} / ${row['suggested_xp_reward']}',
            ),
            Text('${row['age_min']}–${row['age_max']}'),
            StatusPill(
              label: row['is_active'] == true
                  ? l10n.statusOffered
                  : l10n.statusHidden,
              good: row['is_active'] == true,
            ),
            if (canWrite)
              TextButton(
                key: Key('preset.edit.${row['id']}'),
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
