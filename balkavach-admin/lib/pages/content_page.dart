import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api.dart';
import '../core/session.dart';
import '../ui/widgets.dart';

const _types = {
  'link': 'Link',
  'video': 'Video link',
  'article': 'Article',
  'document': 'Document',
  'activity': 'Activity',
};
const _languages = {
  'en': 'English',
  'hi': 'हिन्दी (Hindi)',
  'gu': 'ગુજરાતી (Gujarati)',
};

/// Educational content children see in the Learn tab. External https links
/// only: playback happens in the viewer's own browser or video app.
class ContentPage extends ConsumerStatefulWidget {
  const ContentPage({super.key});

  @override
  ConsumerState<ContentPage> createState() => _ContentPageState();
}

class _ContentPageState extends ConsumerState<ContentPage> {
  int _reload = 0;

  List<FormFieldSpec> _fields([Map<String, dynamic>? row]) => [
    FormFieldSpec(
      key: 'title',
      label: 'Title',
      required: true,
      maxLength: 200,
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
      key: 'content_type',
      label: 'Type',
      kind: FieldKind.choice,
      required: true,
      options: _types,
      initial: row?['content_type'] ?? 'link',
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
      key: 'content_url',
      label: 'Link (https)',
      kind: FieldKind.url,
      initial: row?['content_url'],
      help: 'Opens in the child\'s browser or video app',
    ),
    FormFieldSpec(
      key: 'thumbnail_url',
      label: 'Thumbnail link (https)',
      kind: FieldKind.url,
      initial: row?['thumbnail_url'],
    ),
    if (row != null)
      FormFieldSpec(
        key: 'is_active',
        label: 'Shown to children',
        kind: FieldKind.toggle,
        initial: row['is_active'],
      ),
  ];

  Future<void> _create() async {
    final values = await showFormDialog(
      context,
      title: 'New content',
      fields: _fields(),
    );
    if (values == null || !mounted) return;
    final done = await runAction(
      context,
      () => ref
          .read(adminApiProvider)
          .post('/api/v1/admin/educational-content', values),
      success: 'Content added',
    );
    if (done) setState(() => _reload++);
  }

  Future<void> _edit(Map<String, dynamic> row) async {
    final values = await showFormDialog(
      context,
      title: 'Edit content',
      fields: _fields(row),
    );
    if (values == null || !mounted) return;
    final done = await runAction(
      context,
      () => ref
          .read(adminApiProvider)
          .patch('/api/v1/admin/educational-content/${row['id']}', values),
      success: 'Content saved',
    );
    if (done) setState(() => _reload++);
  }

  @override
  Widget build(BuildContext context) {
    final canWrite = ref.watch(sessionProvider)?.can('content:write') ?? false;
    return ListView(
      children: [
        PageHeader(
          title: 'Learning content',
          subtitle: 'What children see under Learn & Watch, in their language',
          actions: [
            if (canWrite)
              FilledButton.icon(
                key: const Key('content.add'),
                onPressed: _create,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add content'),
              ),
          ],
        ),
        PagedTable(
          reloadKey: _reload,
          emptyMessage: 'No content yet.',
          fetch: (offset, limit) => ref
              .read(adminApiProvider)
              .getList(
                '/api/v1/admin/educational-content',
                query: {'limit': limit, 'offset': offset},
              ),
          columns: const ['Title', 'Type', 'Language', 'Link', 'Status', ''],
          cells: (context, row, reload) => [
            Text('${row['title']}'),
            Text('${_types[row['content_type']] ?? row['content_type']}'),
            Text('${_languages[row['language_code']] ?? row['language_code']}'),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 240),
              child: Text(
                '${row['content_url'] ?? '—'}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
            StatusPill(
              label: row['is_active'] == true ? 'Shown' : 'Hidden',
              good: row['is_active'] == true,
            ),
            if (canWrite)
              TextButton(
                key: Key('content.edit.${row['id']}'),
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
