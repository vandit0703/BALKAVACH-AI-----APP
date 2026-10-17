import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api.dart';
import '../core/locale.dart';
import '../core/session.dart';
import '../l10n/app_localizations.dart';
import '../ui/widgets.dart';

/// Educational content children see in the Learn tab. External https links
/// only: playback happens in the viewer's own browser or video app.
class ContentPage extends ConsumerStatefulWidget {
  const ContentPage({super.key});

  @override
  ConsumerState<ContentPage> createState() => _ContentPageState();
}

class _ContentPageState extends ConsumerState<ContentPage> {
  int _reload = 0;

  Map<String, String> _types(AppLocalizations l10n) => {
    'link': l10n.contentTypeLink,
    'video': l10n.contentTypeVideo,
    'article': l10n.contentTypeArticle,
    'document': l10n.contentTypeDocument,
    'activity': l10n.contentTypeActivity,
  };

  List<FormFieldSpec> _fields(
    AppLocalizations l10n, [
    Map<String, dynamic>? row,
  ]) => [
    FormFieldSpec(
      key: 'title',
      label: l10n.fieldTitle,
      required: true,
      maxLength: 200,
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
      key: 'content_type',
      label: l10n.fieldType,
      kind: FieldKind.choice,
      required: true,
      options: _types(l10n),
      initial: row?['content_type'] ?? 'link',
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
      key: 'content_url',
      label: l10n.contentLink,
      kind: FieldKind.url,
      initial: row?['content_url'],
      help: l10n.contentLinkHelp,
    ),
    FormFieldSpec(
      key: 'thumbnail_url',
      label: l10n.contentThumbnail,
      kind: FieldKind.url,
      initial: row?['thumbnail_url'],
    ),
    if (row != null)
      FormFieldSpec(
        key: 'is_active',
        label: l10n.contentShownToChildren,
        kind: FieldKind.toggle,
        initial: row['is_active'],
      ),
  ];

  Future<void> _create() async {
    final l10n = AppLocalizations.of(context);
    final values = await showFormDialog(
      context,
      title: l10n.contentNewTitle,
      fields: _fields(l10n),
    );
    if (values == null || !mounted) return;
    final done = await runAction(
      context,
      () => ref
          .read(adminApiProvider)
          .post('/api/v1/admin/educational-content', values),
      success: l10n.contentAdded,
    );
    if (done) setState(() => _reload++);
  }

  Future<void> _edit(Map<String, dynamic> row) async {
    final l10n = AppLocalizations.of(context);
    final values = await showFormDialog(
      context,
      title: l10n.contentEditTitle,
      fields: _fields(l10n, row),
    );
    if (values == null || !mounted) return;
    final done = await runAction(
      context,
      () => ref
          .read(adminApiProvider)
          .patch('/api/v1/admin/educational-content/${row['id']}', values),
      success: l10n.contentSaved,
    );
    if (done) setState(() => _reload++);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final canWrite = ref.watch(sessionProvider)?.can('content:write') ?? false;
    final types = _types(l10n);
    return ListView(
      children: [
        PageHeader(
          title: l10n.contentTitle,
          subtitle: l10n.contentSubtitle,
          actions: [
            if (canWrite)
              FilledButton.icon(
                key: const Key('content.add'),
                onPressed: _create,
                icon: const Icon(Icons.add_rounded),
                label: Text(l10n.contentAddButton),
              ),
          ],
        ),
        PagedTable(
          reloadKey: _reload,
          emptyMessage: l10n.contentEmpty,
          fetch: (offset, limit) => ref
              .read(adminApiProvider)
              .getList(
                '/api/v1/admin/educational-content',
                query: {'limit': limit, 'offset': offset},
              ),
          columns: [
            l10n.fieldTitle,
            l10n.fieldType,
            l10n.fieldLanguage,
            l10n.colLink,
            l10n.colStatus,
            '',
          ],
          cells: (context, row, reload) => [
            Text('${row['title']}'),
            Text('${types[row['content_type']] ?? row['content_type']}'),
            Text(
              '${kLanguageNames[row['language_code']] ?? row['language_code']}',
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 240),
              child: Text(
                '${row['content_url'] ?? '—'}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
            StatusPill(
              label: row['is_active'] == true
                  ? l10n.statusShown
                  : l10n.statusHidden,
              good: row['is_active'] == true,
            ),
            if (canWrite)
              TextButton(
                key: Key('content.edit.${row['id']}'),
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
