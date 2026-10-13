import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api.dart';
import '../ui/widgets.dart';

/// Every administrative change, newest first. Read-only.
class AuditPage extends ConsumerWidget {
  const AuditPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      children: [
        const PageHeader(
          title: 'Audit log',
          subtitle: 'Who changed what, and when',
        ),
        PagedTable(
          emptyMessage: 'No administrative changes recorded yet.',
          fetch: (offset, limit) => ref
              .read(adminApiProvider)
              .getList(
                '/api/v1/admin/audit-logs',
                query: {'limit': limit, 'offset': offset},
              ),
          columns: const ['When', 'Action', 'Item', 'Admin'],
          cells: (context, row, reload) => [
            Text(shortDate(row['created_at'])),
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
