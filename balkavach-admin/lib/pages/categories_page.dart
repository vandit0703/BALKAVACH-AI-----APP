import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api.dart';
import '../core/session.dart';
import '../l10n/app_localizations.dart';
import '../ui/widgets.dart';

class CategoriesPage extends ConsumerStatefulWidget {
  const CategoriesPage({super.key});

  @override
  ConsumerState<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends ConsumerState<CategoriesPage> {
  int _reload = 0;

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
      key: 'icon_name',
      label: l10n.fieldIconName,
      maxLength: 100,
      initial: row?['icon_name'],
      help: row == null ? l10n.fieldIconNameHelp : null,
    ),
    if (row != null)
      FormFieldSpec(
        key: 'is_active',
        label: l10n.categoryVisibleToParents,
        kind: FieldKind.toggle,
        initial: row['is_active'],
      ),
  ];

  Future<void> _create() async {
    final l10n = AppLocalizations.of(context);
    final values = await showFormDialog(
      context,
      title: l10n.categoryNewTitle,
      fields: _fields(l10n),
    );
    if (values == null || !mounted) return;
    final done = await runAction(
      context,
      () => ref.read(adminApiProvider).post('/api/v1/tasks/categories', values),
      success: l10n.categoryCreated,
    );
    if (done) setState(() => _reload++);
  }

  Future<void> _edit(Map<String, dynamic> row) async {
    final l10n = AppLocalizations.of(context);
    final values = await showFormDialog(
      context,
      title: l10n.categoryEditTitle,
      fields: _fields(l10n, row),
    );
    if (values == null || !mounted) return;
    final done = await runAction(
      context,
      () => ref
          .read(adminApiProvider)
          .patch('/api/v1/admin/task-categories/${row['id']}', values),
      success: l10n.categorySaved,
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
          title: l10n.categoriesTitle,
          subtitle: l10n.categoriesSubtitle,
          actions: [
            if (canWrite)
              FilledButton.icon(
                key: const Key('categories.add'),
                onPressed: _create,
                icon: const Icon(Icons.add_rounded),
                label: Text(l10n.categoryNewTitle),
              ),
          ],
        ),
        PagedTable(
          reloadKey: _reload,
          fetch: (offset, limit) async {
            final all = await ref
                .read(adminApiProvider)
                .getList('/api/v1/admin/task-categories');
            return all.skip(offset).take(limit).toList();
          },
          columns: [
            l10n.colName,
            l10n.colDescription,
            l10n.colIcon,
            l10n.colStatus,
            '',
          ],
          cells: (context, row, reload) => [
            Text('${row['name']}'),
            Text('${row['description'] ?? '—'}'),
            Text('${row['icon_name'] ?? '—'}'),
            StatusPill(
              label: row['is_active'] == true
                  ? l10n.statusVisible
                  : l10n.statusHidden,
              good: row['is_active'] == true,
            ),
            if (canWrite)
              TextButton(
                key: Key('category.edit.${row['id']}'),
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
