import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api.dart';

/// Title row with optional actions, used at the top of every page.
class PageHeader extends StatelessWidget {
  const PageHeader({
    required this.title,
    this.subtitle,
    this.actions = const [],
    super.key,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        spacing: 16,
        runSpacing: 8,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: text.headlineSmall),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: text.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          if (actions.isNotEmpty)
            Wrap(spacing: 8, runSpacing: 8, children: actions),
        ],
      ),
    );
  }
}

/// Plain-language message for an API failure, with an optional retry.
class ErrorBox extends StatelessWidget {
  const ErrorBox({required this.error, this.onRetry, super.key});

  final Object error;
  final VoidCallback? onRetry;

  static String describe(Object error) {
    if (error is ApiError) {
      if (error.isForbidden) return 'You do not have permission to do this.';
      if (error.isNetwork) return error.message;
      return error.message;
    }
    return 'Something went wrong.';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 40, color: scheme.error),
            const SizedBox(height: 8),
            Text(
              describe(error),
              key: const Key('error.message'),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const Key('error.retry'),
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try again'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String body,
  String confirmLabel = 'Confirm',
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('confirm.yes'),
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

void showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Runs [action], showing [success] or the error. Returns whether it worked.
Future<bool> runAction(
  BuildContext context,
  Future<Object?> Function() action, {
  String? success,
}) async {
  try {
    await action();
    if (success != null && context.mounted) showMessage(context, success);
    return true;
  } on ApiError catch (error) {
    if (context.mounted) showMessage(context, ErrorBox.describe(error));
    return false;
  }
}

// ---- simple form engine -----------------------------------------------------------------

enum FieldKind { text, multiline, integer, url, choice, toggle }

/// One input of a [showFormDialog].
class FormFieldSpec {
  const FormFieldSpec({
    required this.key,
    required this.label,
    this.kind = FieldKind.text,
    this.required = false,
    this.initial,
    this.options = const {},
    this.min,
    this.max,
    this.maxLength,
    this.help,
  });

  final String key;
  final String label;
  final FieldKind kind;
  final bool required;
  final Object? initial;

  /// For [FieldKind.choice]: value → label. A `''` value means "none".
  final Map<String, String> options;
  final int? min;
  final int? max;
  final int? maxLength;
  final String? help;
}

/// Shows a form and returns the entered values (typed: ints are `int`,
/// blanks are omitted unless they were required), or `null` if cancelled.
Future<Map<String, dynamic>?> showFormDialog(
  BuildContext context, {
  required String title,
  required List<FormFieldSpec> fields,
  String submitLabel = 'Save',
}) {
  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (context) =>
        _FormDialog(title: title, fields: fields, submitLabel: submitLabel),
  );
}

class _FormDialog extends StatefulWidget {
  const _FormDialog({
    required this.title,
    required this.fields,
    required this.submitLabel,
  });

  final String title;
  final List<FormFieldSpec> fields;
  final String submitLabel;

  @override
  State<_FormDialog> createState() => _FormDialogState();
}

class _FormDialogState extends State<_FormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _controllers = {
    for (final f in widget.fields)
      if (f.kind != FieldKind.choice && f.kind != FieldKind.toggle)
        f.key: TextEditingController(text: f.initial?.toString() ?? ''),
  };
  late final Map<String, Object?> _picked = {
    for (final f in widget.fields)
      if (f.kind == FieldKind.choice || f.kind == FieldKind.toggle)
        f.key: f.initial,
  };

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  String? _validate(FormFieldSpec f, String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return f.required ? 'Required' : null;
    if (f.maxLength != null && value.length > f.maxLength!) {
      return 'At most ${f.maxLength} characters';
    }
    if (f.kind == FieldKind.integer) {
      final n = int.tryParse(value);
      if (n == null) return 'Enter a whole number';
      if (f.min != null && n < f.min!) return 'At least ${f.min}';
      if (f.max != null && n > f.max!) return 'At most ${f.max}';
    }
    if (f.kind == FieldKind.url) {
      final uri = Uri.tryParse(value);
      if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
        return 'Enter a full https:// link';
      }
    }
    return null;
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final result = <String, dynamic>{};
    for (final f in widget.fields) {
      switch (f.kind) {
        case FieldKind.choice:
          final v = _picked[f.key] as String?;
          if (v != null && v.isNotEmpty) {
            result[f.key] = v;
          } else if (f.initial != null) {
            result[f.key] = null; // explicit clear
          }
        case FieldKind.toggle:
          result[f.key] = _picked[f.key] == true;
        case FieldKind.integer:
          final raw = _controllers[f.key]!.text.trim();
          if (raw.isNotEmpty) result[f.key] = int.parse(raw);
        case FieldKind.text || FieldKind.multiline || FieldKind.url:
          final raw = _controllers[f.key]!.text.trim();
          if (raw.isNotEmpty) {
            result[f.key] = raw;
          } else if (f.initial != null && f.initial.toString().isNotEmpty) {
            result[f.key] = null; // explicit clear of an existing value
          }
      }
    }
    Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final f in widget.fields)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: _field(f),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('form.submit'),
          onPressed: _submit,
          child: Text(widget.submitLabel),
        ),
      ],
    );
  }

  Widget _field(FormFieldSpec f) {
    final label = f.required ? '${f.label} *' : f.label;
    switch (f.kind) {
      case FieldKind.toggle:
        return SwitchListTile(
          key: Key('field.${f.key}'),
          contentPadding: EdgeInsets.zero,
          title: Text(f.label),
          subtitle: f.help == null ? null : Text(f.help!),
          value: _picked[f.key] == true,
          onChanged: (v) => setState(() => _picked[f.key] = v),
        );
      case FieldKind.choice:
        final current = (_picked[f.key] as String?) ?? '';
        return DropdownButtonFormField<String>(
          key: Key('field.${f.key}'),
          initialValue: f.options.containsKey(current) ? current : null,
          isExpanded: true,
          decoration: InputDecoration(labelText: label, helperText: f.help),
          items: [
            for (final e in f.options.entries)
              DropdownMenuItem(value: e.key, child: Text(e.value)),
          ],
          validator: (v) =>
              f.required && (v == null || v.isEmpty) ? 'Required' : null,
          onChanged: (v) => _picked[f.key] = v,
        );
      case FieldKind.integer ||
          FieldKind.text ||
          FieldKind.url ||
          FieldKind.multiline:
        return TextFormField(
          key: Key('field.${f.key}'),
          controller: _controllers[f.key],
          maxLines: f.kind == FieldKind.multiline ? 4 : 1,
          minLines: f.kind == FieldKind.multiline ? 2 : 1,
          keyboardType: f.kind == FieldKind.integer
              ? TextInputType.number
              : null,
          decoration: InputDecoration(labelText: label, helperText: f.help),
          validator: (v) => _validate(f, v),
        );
    }
  }
}

// ---- paged table ----------------------------------------------------------------------------

typedef PageFetch =
    Future<List<Map<String, dynamic>>> Function(int offset, int limit);

/// A scrollable table loaded one page at a time from the server.
class PagedTable extends ConsumerStatefulWidget {
  const PagedTable({
    required this.fetch,
    required this.columns,
    required this.cells,
    this.emptyMessage = 'Nothing to show.',
    this.pageSize = 25,
    this.reloadKey = 0,
    super.key,
  });

  final PageFetch fetch;
  final List<String> columns;

  /// Builds one row's cells; must match [columns].
  final List<Widget> Function(
    BuildContext context,
    Map<String, dynamic> row,
    VoidCallback reload,
  )
  cells;
  final String emptyMessage;
  final int pageSize;

  /// Change this to force a reload (for example after a search).
  final Object reloadKey;

  @override
  ConsumerState<PagedTable> createState() => _PagedTableState();
}

class _PagedTableState extends ConsumerState<PagedTable> {
  int _page = 0;
  late Future<List<Map<String, dynamic>>> _future = _load();

  Future<List<Map<String, dynamic>>> _load() =>
      widget.fetch(_page * widget.pageSize, widget.pageSize);

  void _reload() => setState(() {
    _future = _load();
  });

  @override
  void didUpdateWidget(PagedTable old) {
    super.didUpdateWidget(old);
    if (old.reloadKey != widget.reloadKey) {
      _page = 0;
      _future = _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return ErrorBox(error: snapshot.error!, onRetry: _reload);
        }
        final rows = snapshot.data;
        if (rows == null) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (rows.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Text(
                    widget.emptyMessage,
                    key: const Key('table.empty'),
                  ),
                ),
              )
            else
              Card(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: [
                      for (final c in widget.columns)
                        DataColumn(label: Text(c)),
                    ],
                    rows: [
                      for (final row in rows)
                        DataRow(
                          cells: [
                            for (final cell in widget.cells(
                              context,
                              row,
                              _reload,
                            ))
                              DataCell(cell),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    key: const Key('table.previous'),
                    tooltip: 'Previous page',
                    onPressed: _page == 0
                        ? null
                        : () {
                            _page--;
                            _reload();
                          },
                    icon: const Icon(Icons.chevron_left_rounded),
                  ),
                  Text('Page ${_page + 1}'),
                  IconButton(
                    key: const Key('table.next'),
                    tooltip: 'Next page',
                    onPressed: rows.length < widget.pageSize
                        ? null
                        : () {
                            _page++;
                            _reload();
                          },
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// A small coloured label for statuses.
class StatusPill extends StatelessWidget {
  const StatusPill({required this.label, this.good = true, super.key});

  final String label;
  final bool good;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: good ? scheme.secondaryContainer : scheme.errorContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Text(
          label,
          style: TextStyle(
            color: good ? scheme.onSecondaryContainer : scheme.onErrorContainer,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

String shortDate(Object? iso) {
  if (iso is! String) return '—';
  final parsed = DateTime.tryParse(iso);
  if (parsed == null) return '—';
  final local = parsed.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
}
