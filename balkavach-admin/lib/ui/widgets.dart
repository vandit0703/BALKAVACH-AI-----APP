import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../core/api.dart';
import '../core/theme.dart';
import '../l10n/app_localizations.dart';

/// Below this width a table becomes a list of cards.
const kCompactTableWidth = 720.0;

// ---- page chrome ----------------------------------------------------------------------------

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
      padding: const EdgeInsets.only(bottom: 20),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        spacing: 16,
        runSpacing: 12,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  header: true,
                  child: Text(title, style: text.headlineMedium),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    style: text.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (actions.isNotEmpty)
            Wrap(spacing: 8, runSpacing: 8, children: actions),
        ],
      ),
    );
  }
}

/// A label with a leading icon and value, used for dashboard figures.
class StatCard extends StatelessWidget {
  const StatCard({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
    this.highlight = false,
    super.key,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  /// Draws attention to something that needs action (for example pending
  /// requests).
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tint = highlight ? scheme.tertiaryFixed : scheme.primaryFixed;
    final onTint = highlight ? scheme.onTertiaryFixed : scheme.primary;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: tint,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Icon(icon, color: onTint, size: 22),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    Text(
                      label,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (onTap != null)
                Icon(
                  Icons.chevron_right_rounded,
                  color: scheme.onSurfaceVariant,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A titled panel that groups related content on a page.
class SectionCard extends StatelessWidget {
  const SectionCard({
    required this.title,
    required this.child,
    this.trailing,
    super.key,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

// ---- states ---------------------------------------------------------------------------------

/// Plain-language message for an API failure, in the panel's language.
/// Backend messages are English-only, so known error codes and status classes
/// are mapped to localized text instead of being shown as they arrive.
String describeError(AppLocalizations l10n, Object error) {
  if (error is! ApiError) return l10n.errorGeneric;
  final byCode = switch (error.code) {
    'last_super_admin' => l10n.errorLastSuperAdmin,
    'email_in_use' || 'account_conflict' => l10n.errorEmailInUse,
    'username_in_use' => l10n.errorUsernameInUse,
    'category_conflict' => l10n.errorCategoryConflict,
    'invalid_setting' || 'unknown_setting' => l10n.errorInvalidSetting,
    'invalid_age_range' => l10n.errorInvalidAgeRange,
    _ => null,
  };
  if (byCode != null) return byCode;
  if (error.isNetwork) return l10n.errorNetwork;
  return switch (error.status) {
    401 => l10n.errorSessionExpired,
    403 => l10n.errorForbidden,
    404 => l10n.errorNotFound,
    409 => l10n.errorConflict,
    429 => l10n.errorTooManyRequests,
    422 => l10n.errorValidation,
    >= 500 => l10n.errorServer,
    _ => l10n.errorGeneric,
  };
}

/// Error with an optional retry. A 403 is shown as "no permission", not as a
/// failure to retry.
class ErrorBox extends StatelessWidget {
  const ErrorBox({required this.error, this.onRetry, super.key});

  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final denied = error is ApiError && (error as ApiError).isForbidden;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              denied ? Icons.lock_outline_rounded : Icons.error_outline_rounded,
              size: 40,
              color: scheme.error,
            ),
            const SizedBox(height: 8),
            Text(
              describeError(l10n, error),
              key: const Key('error.message'),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null && !denied) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const Key('error.retry'),
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(l10n.actionTryAgain),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.message,
    this.icon = Icons.inbox_outlined,
    this.textKey = const Key('table.empty'),
    super.key,
  });

  final String message;
  final IconData icon;
  final Key textKey;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 36, color: scheme.outline),
            const SizedBox(height: 8),
            Text(message, key: textKey, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class LoadingBlock extends StatelessWidget {
  const LoadingBlock({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: AppLocalizations.of(context).loading,
      child: const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(),
        ),
      ),
    );
  }
}

/// A [FutureBuilder] with the panel's loading and error states.
class AsyncBody<T> extends StatelessWidget {
  const AsyncBody({
    required this.future,
    required this.builder,
    required this.onRetry,
    super.key,
  });

  final Future<T> future;
  final Widget Function(BuildContext context, T data) builder;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return ErrorBox(error: snapshot.error!, onRetry: onRetry);
        }
        if (!snapshot.hasData) return const LoadingBlock();
        return builder(context, snapshot.data as T);
      },
    );
  }
}

// ---- toolbars -------------------------------------------------------------------------------

/// Search box plus filters, laid out as one row on wide screens and stacked on
/// narrow ones.
class FilterBar extends StatelessWidget {
  const FilterBar({
    required this.searchKey,
    required this.searchLabel,
    required this.controller,
    required this.onSearch,
    this.applyKey,
    this.filters = const [],
    super.key,
  });

  final Key searchKey;
  final Key? applyKey;
  final String searchLabel;
  final TextEditingController controller;
  final ValueChanged<String> onSearch;
  final List<Widget> filters;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 240, maxWidth: 360),
            child: TextField(
              key: searchKey,
              controller: controller,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                labelText: searchLabel,
                prefixIcon: const Icon(Icons.search_rounded),
              ),
              onSubmitted: (value) => onSearch(value.trim()),
            ),
          ),
          ...filters,
          FilledButton.tonal(
            key: applyKey,
            onPressed: () => onSearch(controller.text.trim()),
            child: Text(l10n.actionSearch),
          ),
        ],
      ),
    );
  }
}

/// A compact dropdown used for filters.
class FilterDropdown extends StatelessWidget {
  const FilterDropdown({
    required this.fieldKey,
    required this.value,
    required this.options,
    required this.onChanged,
    super.key,
  });

  final Key fieldKey;
  final String value;

  /// value → label.
  final Map<String, String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: kInputRadius,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            key: fieldKey,
            value: value,
            borderRadius: kInputRadius,
            items: [
              for (final e in options.entries)
                DropdownMenuItem(value: e.key, child: Text(e.value)),
            ],
            onChanged: (v) => onChanged(v ?? ''),
          ),
        ),
      ),
    );
  }
}

// ---- dialogs and feedback -----------------------------------------------------------------

Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String body,
  String? confirmLabel,
}) async {
  final l10n = AppLocalizations.of(context);
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(
          key: const Key('confirm.yes'),
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirmLabel ?? l10n.actionConfirm),
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

/// Shows [error] in the panel's language.
void showError(BuildContext context, Object error) =>
    showMessage(context, describeError(AppLocalizations.of(context), error));

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
    if (context.mounted) showError(context, error);
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
  String? submitLabel,
}) {
  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (context) => _FormDialog(
      title: title,
      fields: fields,
      submitLabel: submitLabel ?? AppLocalizations.of(context).actionSave,
    ),
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

  String? _validate(AppLocalizations l10n, FormFieldSpec f, String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return f.required ? l10n.validationRequired : null;
    if (f.maxLength != null && value.length > f.maxLength!) {
      return l10n.validationMaxLength('${f.maxLength}');
    }
    if (f.kind == FieldKind.integer) {
      final n = int.tryParse(value);
      if (n == null) return l10n.validationWholeNumber;
      if (f.min != null && n < f.min!) {
        return l10n.validationAtLeast('${f.min}');
      }
      if (f.max != null && n > f.max!) {
        return l10n.validationAtMost('${f.max}');
      }
    }
    if (f.kind == FieldKind.url) {
      final uri = Uri.tryParse(value);
      if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
        return l10n.validationHttps;
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
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, minWidth: 240),
        child: SizedBox(
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
                      child: _field(l10n, f),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(
          key: const Key('form.submit'),
          onPressed: _submit,
          child: Text(widget.submitLabel),
        ),
      ],
    );
  }

  Widget _field(AppLocalizations l10n, FormFieldSpec f) {
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
          validator: (v) => f.required && (v == null || v.isEmpty)
              ? l10n.validationRequired
              : null,
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
          validator: (v) => _validate(l10n, f, v),
        );
    }
  }
}

// ---- paged table ----------------------------------------------------------------------------

typedef PageFetch =
    Future<List<Map<String, dynamic>>> Function(int offset, int limit);

/// A table loaded one page at a time from the server. On narrow screens each
/// row becomes a card: the first cell is the title, the rest are labelled
/// values, and a column with an empty heading holds the row's actions.
class PagedTable extends ConsumerStatefulWidget {
  const PagedTable({
    required this.fetch,
    required this.columns,
    required this.cells,
    this.emptyMessage,
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

  /// Defaults to a generic "Nothing to show."
  final String? emptyMessage;
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
    final l10n = AppLocalizations.of(context);
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return ErrorBox(error: snapshot.error!, onRetry: _reload);
        }
        final rows = snapshot.data;
        if (rows == null) return const LoadingBlock();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (rows.isEmpty)
              EmptyState(message: widget.emptyMessage ?? l10n.tableEmpty)
            else
              LayoutBuilder(
                builder: (context, box) => box.maxWidth < kCompactTableWidth
                    ? _cards(context, rows)
                    : _table(context, rows, box.maxWidth),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    key: const Key('table.previous'),
                    tooltip: l10n.tablePrevious,
                    onPressed: _page == 0
                        ? null
                        : () {
                            _page--;
                            _reload();
                          },
                    icon: const Icon(Icons.chevron_left_rounded),
                  ),
                  Text(l10n.tablePage('${_page + 1}')),
                  IconButton(
                    key: const Key('table.next'),
                    tooltip: l10n.tableNext,
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

  Widget _table(
    BuildContext context,
    List<Map<String, dynamic>> rows,
    double width,
  ) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: width - 2),
          child: DataTable(
            columns: [
              for (final c in widget.columns) DataColumn(label: Text(c)),
            ],
            rows: [
              for (final row in rows)
                DataRow(
                  cells: [
                    for (final cell in widget.cells(context, row, _reload))
                      DataCell(cell),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cards(BuildContext context, List<Map<String, dynamic>> rows) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Column(
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Builder(
                  builder: (context) {
                    final cells = widget.cells(context, row, _reload);
                    final actions = <Widget>[];
                    final details = <Widget>[];
                    for (var i = 1; i < cells.length; i++) {
                      if (widget.columns[i].isEmpty) {
                        actions.add(cells[i]);
                      } else {
                        details.add(
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 112,
                                  child: Text(
                                    widget.columns[i],
                                    style: text.labelMedium?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Align(
                                    alignment: AlignmentDirectional.centerStart,
                                    child: cells[i],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DefaultTextStyle.merge(
                          style: text.titleSmall,
                          child: cells.first,
                        ),
                        ...details,
                        if (actions.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Wrap(spacing: 4, children: actions),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ---- badges and dates -------------------------------------------------------------------

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
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// A date and time in the viewer's time zone, formatted for the panel's
/// language. `—` when [iso] is missing or unreadable.
String shortDate(BuildContext context, Object? iso) {
  if (iso is! String) return '—';
  final parsed = DateTime.tryParse(iso);
  if (parsed == null) return '—';
  final locale = Localizations.localeOf(context).languageCode;
  return DateFormat.yMMMd(locale).add_Hm().format(parsed.toLocal());
}
