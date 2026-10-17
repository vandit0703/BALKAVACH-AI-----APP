import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api.dart';
import '../l10n/app_localizations.dart';
import '../ui/widgets.dart';

/// Every administrative change, newest first. Read-only.
class AuditPage extends ConsumerWidget {
  const AuditPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return ListView(
      children: [
        PageHeader(title: l10n.auditTitle, subtitle: l10n.auditSubtitle),
        PagedTable(
          emptyMessage: l10n.auditEmpty,
          fetch: (offset, limit) => ref
              .read(adminApiProvider)
              .getList(
                '/api/v1/admin/audit-logs',
                query: {'limit': limit, 'offset': offset},
              ),
          columns: [l10n.colWhen, l10n.colAction, l10n.colItem, l10n.colAdmin],
          cells: (context, row, reload) => [
            Text(shortDate(context, row['created_at'])),
            Text('${row['action']}'),
            Text('${row['entity_type']}'),
            Text(_short(row['actor_user_id'])),
          ],
        ),
      ],
    );
  }

  static String _short(Object? id) =>
      id is String && id.length >= 8 ? id.substring(0, 8) : '—';
}
