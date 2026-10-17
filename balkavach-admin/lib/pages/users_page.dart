import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api.dart';
import '../core/session.dart';
import '../l10n/app_localizations.dart';
import '../ui/widgets.dart';

class UsersPage extends ConsumerStatefulWidget {
  const UsersPage({super.key});

  @override
  ConsumerState<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends ConsumerState<UsersPage> {
  final _search = TextEditingController();
  String _query = '';
  String _role = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _setActive(
    Map<String, dynamic> user,
    bool active,
    VoidCallback reload,
  ) async {
    final l10n = AppLocalizations.of(context);
    final name = '${user['full_name']}';
    final ok = await confirm(
      context,
      title: active ? l10n.userReactivateTitle : l10n.userDeactivateTitle,
      body: active
          ? l10n.userReactivateBody(name)
          : l10n.userDeactivateBody(name),
      confirmLabel: active ? l10n.actionReactivate : l10n.actionDeactivate,
    );
    if (!ok || !mounted) return;
    final done = await runAction(
      context,
      () => ref.read(adminApiProvider).patch(
        '/api/v1/admin/users/${user['id']}/status',
        {'is_active': active},
      ),
      success: active ? l10n.userReactivated : l10n.userDeactivated,
    );
    if (done) reload();
  }

  Future<void> _roles(Map<String, dynamic> user) async {
    final l10n = AppLocalizations.of(context);
    final api = ref.read(adminApiProvider);
    final List<Map<String, dynamic>> roles;
    try {
      roles = await api.getList('/api/v1/admin/roles');
    } on ApiError catch (error) {
      if (mounted) showError(context, error);
      return;
    }
    if (!mounted) return;
    final result = await showFormDialog(
      context,
      title: l10n.userRolesTitle('${user['full_name']}'),
      submitLabel: l10n.actionApply,
      fields: [
        FormFieldSpec(
          key: 'role_id',
          label: l10n.fieldRole,
          kind: FieldKind.choice,
          required: true,
          options: {
            for (final r in roles) r['id'] as String: r['name'] as String,
          },
        ),
        FormFieldSpec(
          key: 'remove',
          label: l10n.userRolesRemove,
          kind: FieldKind.toggle,
          initial: false,
        ),
      ],
    );
    if (result == null || !mounted) return;
    final roleId = result['role_id'] as String;
    final remove = result['remove'] == true;
    await runAction(
      context,
      () => remove
          ? api.delete('/api/v1/admin/users/${user['id']}/roles/$roleId')
          : api.post('/api/v1/admin/users/${user['id']}/roles', {
              'role_id': roleId,
            }),
      success: remove ? l10n.userRoleRemoved : l10n.userRoleAssigned,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final session = ref.watch(sessionProvider);
    final canWrite = session?.can('users:write') ?? false;
    final canRoles = session?.can('admin_roles:write') ?? false;
    return ListView(
      children: [
        PageHeader(title: l10n.usersTitle, subtitle: l10n.usersSubtitle),
        FilterBar(
          searchKey: const Key('users.search'),
          applyKey: const Key('users.apply'),
          searchLabel: l10n.usersSearch,
          controller: _search,
          onSearch: (value) => setState(() => _query = value),
          filters: [
            FilterDropdown(
              fieldKey: const Key('users.role'),
              value: _role,
              options: {
                '': l10n.usersAllRoles,
                'parent': l10n.rolesParents,
                'child': l10n.rolesChildren,
                'admin': l10n.rolesAdmins,
                'staff': l10n.rolesStaff,
              },
              onChanged: (value) => setState(() => _role = value),
            ),
          ],
        ),
        PagedTable(
          reloadKey: '$_query|$_role',
          emptyMessage: l10n.usersEmpty,
          fetch: (offset, limit) => ref
              .read(adminApiProvider)
              .getList(
                '/api/v1/admin/users',
                query: {
                  'limit': limit,
                  'offset': offset,
                  if (_query.isNotEmpty) 'q': _query,
                  if (_role.isNotEmpty) 'role': _role,
                },
              ),
          columns: [
            l10n.colName,
            l10n.colEmail,
            l10n.colRole,
            l10n.colStatus,
            l10n.colLastSignIn,
            '',
          ],
          cells: (context, row, reload) {
            final active = row['is_active'] == true;
            final isAdmin = row['role'] == 'admin' || row['role'] == 'staff';
            return [
              Text('${row['full_name']}'),
              Text('${row['email'] ?? '—'}'),
              Text('${row['role']}'),
              StatusPill(
                label: active ? l10n.statusActive : l10n.statusDeactivated,
                good: active,
              ),
              Text(shortDate(context, row['last_login_at'])),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (canWrite)
                    TextButton(
                      key: Key('user.toggle.${row['id']}'),
                      onPressed: () => _setActive(row, !active, reload),
                      child: Text(
                        active ? l10n.actionDeactivate : l10n.actionReactivate,
                      ),
                    ),
                  if (canRoles && isAdmin)
                    TextButton(
                      key: Key('user.roles.${row['id']}'),
                      onPressed: () => _roles(row),
                      child: Text(l10n.actionRoles),
                    ),
                ],
              ),
            ];
          },
        ),
      ],
    );
  }
}
