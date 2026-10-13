import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api.dart';
import '../core/session.dart';
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
    final ok = await confirm(
      context,
      title: active ? 'Reactivate account?' : 'Deactivate account?',
      body: active
          ? '${user['full_name']} will be able to sign in again.'
          : '${user['full_name']} will be signed out and unable to sign in until reactivated.',
      confirmLabel: active ? 'Reactivate' : 'Deactivate',
    );
    if (!ok || !mounted) return;
    final done = await runAction(
      context,
      () => ref.read(adminApiProvider).patch(
        '/api/v1/admin/users/${user['id']}/status',
        {'is_active': active},
      ),
      success: active ? 'Account reactivated' : 'Account deactivated',
    );
    if (done) reload();
  }

  Future<void> _roles(Map<String, dynamic> user) async {
    final api = ref.read(adminApiProvider);
    final List<Map<String, dynamic>> roles;
    try {
      roles = await api.getList('/api/v1/admin/roles');
    } on ApiError catch (error) {
      if (mounted) showMessage(context, ErrorBox.describe(error));
      return;
    }
    if (!mounted) return;
    final result = await showFormDialog(
      context,
      title: 'Roles for ${user['full_name']}',
      submitLabel: 'Apply',
      fields: [
        FormFieldSpec(
          key: 'role_id',
          label: 'Role',
          kind: FieldKind.choice,
          required: true,
          options: {
            for (final r in roles) r['id'] as String: r['name'] as String,
          },
        ),
        const FormFieldSpec(
          key: 'remove',
          label: 'Remove this role instead of assigning it',
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
      success: remove ? 'Role removed' : 'Role assigned',
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final canWrite = session?.can('users:write') ?? false;
    final canRoles = session?.can('admin_roles:write') ?? false;
    return ListView(
      children: [
        const PageHeader(
          title: 'Users',
          subtitle: 'Parents, children and administrators',
        ),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 280,
              child: TextField(
                key: const Key('users.search'),
                controller: _search,
                decoration: const InputDecoration(
                  labelText: 'Search name or email',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
                onSubmitted: (value) => setState(() => _query = value.trim()),
              ),
            ),
            DropdownButton<String>(
              key: const Key('users.role'),
              value: _role,
              items: const [
                DropdownMenuItem(value: '', child: Text('All roles')),
                DropdownMenuItem(value: 'parent', child: Text('Parents')),
                DropdownMenuItem(value: 'child', child: Text('Children')),
                DropdownMenuItem(value: 'admin', child: Text('Admins')),
                DropdownMenuItem(value: 'staff', child: Text('Staff')),
              ],
              onChanged: (value) => setState(() => _role = value ?? ''),
            ),
            FilledButton.tonal(
              key: const Key('users.apply'),
              onPressed: () => setState(() => _query = _search.text.trim()),
              child: const Text('Search'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        PagedTable(
          reloadKey: '$_query|$_role',
          emptyMessage: 'No users match.',
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
          columns: const [
            'Name',
            'Email',
            'Role',
            'Status',
            'Last sign-in',
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
                label: active ? 'Active' : 'Deactivated',
                good: active,
              ),
              Text(shortDate(row['last_login_at'])),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (canWrite)
                    TextButton(
                      key: Key('user.toggle.${row['id']}'),
                      onPressed: () => _setActive(row, !active, reload),
                      child: Text(active ? 'Deactivate' : 'Reactivate'),
                    ),
                  if (canRoles && isAdmin)
                    TextButton(
                      key: Key('user.roles.${row['id']}'),
                      onPressed: () => _roles(row),
                      child: const Text('Roles'),
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
