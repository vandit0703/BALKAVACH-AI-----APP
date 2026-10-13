import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api.dart';
import '../core/session.dart';
import '../ui/widgets.dart';

class CategoriesPage extends ConsumerStatefulWidget {
  const CategoriesPage({super.key});

  @override
  ConsumerState<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends ConsumerState<CategoriesPage> {
  int _reload = 0;

  Future<void> _create() async {
    final values = await showFormDialog(
      context,
      title: 'New category',
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
          key: 'icon_name',
          label: 'Icon name',
          maxLength: 100,
          help: 'For example book-open or palette',
        ),
      ],
    );
    if (values == null || !mounted) return;
    final done = await runAction(
      context,
      () => ref.read(adminApiProvider).post('/api/v1/tasks/categories', values),
      success: 'Category created',
    );
    if (done) setState(() => _reload++);
  }

  Future<void> _edit(Map<String, dynamic> row) async {
    final values = await showFormDialog(
      context,
      title: 'Edit category',
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
          key: 'icon_name',
          label: 'Icon name',
          maxLength: 100,
          initial: row['icon_name'],
        ),
        FormFieldSpec(
          key: 'is_active',
          label: 'Visible to parents',
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
          .patch('/api/v1/admin/task-categories/${row['id']}', values),
      success: 'Category saved',
    );
    if (done) setState(() => _reload++);
  }

  @override
  Widget build(BuildContext context) {
    final canWrite = ref.watch(sessionProvider)?.can('content:write') ?? false;
    return ListView(
      children: [
        PageHeader(
          title: 'Mission categories',
          subtitle: 'The groups parents pick from when creating a mission',
          actions: [
            if (canWrite)
              FilledButton.icon(
                key: const Key('categories.add'),
                onPressed: _create,
                icon: const Icon(Icons.add_rounded),
                label: const Text('New category'),
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
          columns: const ['Name', 'Description', 'Icon', 'Status', ''],
          cells: (context, row, reload) => [
            Text('${row['name']}'),
            Text('${row['description'] ?? '—'}'),
            Text('${row['icon_name'] ?? '—'}'),
            StatusPill(
              label: row['is_active'] == true ? 'Visible' : 'Hidden',
              good: row['is_active'] == true,
            ),
            if (canWrite)
              TextButton(
                key: Key('category.edit.${row['id']}'),
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
