import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api.dart';
import '../core/session.dart';
import '../ui/widgets.dart';

/// Application-wide settings the mobile app reads at start-up.
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  late Future<List<Map<String, dynamic>>> _future = _load();

  Future<List<Map<String, dynamic>>> _load() =>
      ref.read(adminApiProvider).getList('/api/v1/admin/settings');

  void _reload() => setState(() {
    _future = _load();
  });

  Map<String, dynamic> _find(List<Map<String, dynamic>> rows, String key) =>
      rows.firstWhere(
        (r) => r['key'] == key,
        orElse: () => {'key': key, 'value': null, 'overridden': false},
      );

  Future<void> _editConsent(Map<String, dynamic> row) async {
    final current = (row['value'] as Map<String, dynamic>?) ?? const {};
    final values = await showFormDialog(
      context,
      title: 'Consent document version',
      fields: [
        FormFieldSpec(
          key: 'parent_guardian_terms',
          label: 'Parent / guardian terms version',
          required: true,
          maxLength: 40,
          initial: current['parent_guardian_terms'],
          help:
              'Changing this asks every parent to accept again on their next launch.',
        ),
      ],
    );
    if (values == null || !mounted) return;
    final ok = await confirm(
      context,
      title: 'Ask all parents to accept again?',
      body:
          'The new version "${values['parent_guardian_terms']}" will be shown to every parent. Confirm that legal has approved the text.',
      confirmLabel: 'Publish version',
    );
    if (!ok || !mounted) return;
    final done = await runAction(
      context,
      () => ref.read(adminApiProvider).put(
        '/api/v1/admin/settings/consent_versions',
        {
          'value': {
            ...current,
            'parent_guardian_terms': values['parent_guardian_terms'],
          },
        },
      ),
      success: 'Consent version published',
    );
    if (done) _reload();
  }

  Future<void> _editMaintenance(Map<String, dynamic> row) async {
    final current = (row['value'] as Map<String, dynamic>?) ?? const {};
    final values = await showFormDialog(
      context,
      title: 'Maintenance notice',
      fields: [
        FormFieldSpec(
          key: 'enabled',
          label: 'Show a banner in the app',
          kind: FieldKind.toggle,
          initial: current['enabled'] == true,
        ),
        FormFieldSpec(
          key: 'message',
          label: 'Message',
          kind: FieldKind.multiline,
          maxLength: 300,
          initial: current['message'],
          help: 'Leave empty for the default sentence',
        ),
      ],
    );
    if (values == null || !mounted) return;
    final done = await runAction(
      context,
      () =>
          ref.read(adminApiProvider).put('/api/v1/admin/settings/maintenance', {
            'value': {
              'enabled': values['enabled'] == true,
              'message': (values['message'] as String?) ?? '',
            },
          }),
      success: 'Maintenance notice saved',
    );
    if (done) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final canWrite = ref.watch(sessionProvider)?.can('settings:write') ?? false;
    return ListView(
      children: [
        const PageHeader(
          title: 'Settings',
          subtitle: 'Read by the mobile app every time it starts',
        ),
        FutureBuilder<List<Map<String, dynamic>>>(
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
            final consent = _find(rows, 'consent_versions');
            final maintenance = _find(rows, 'maintenance');
            final versions =
                (consent['value'] as Map<String, dynamic>?) ?? const {};
            final maint =
                (maintenance['value'] as Map<String, dynamic>?) ?? const {};
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  child: ListTile(
                    key: const Key('settings.consent'),
                    title: const Text('Consent document version'),
                    subtitle: Text(
                      'Parent / guardian terms: ${versions['parent_guardian_terms'] ?? '—'}'
                      '${consent['overridden'] == true ? '' : '  (built-in draft: legal must confirm)'}',
                    ),
                    trailing: canWrite
                        ? FilledButton.tonal(
                            key: const Key('settings.consent.edit'),
                            onPressed: () => _editConsent(consent),
                            child: const Text('Change'),
                          )
                        : null,
                  ),
                ),
                Card(
                  child: ListTile(
                    key: const Key('settings.maintenance'),
                    title: const Text('Maintenance notice'),
                    subtitle: Text(
                      maint['enabled'] == true
                          ? 'Showing: ${(maint['message'] as String?)?.isNotEmpty == true ? maint['message'] : 'default message'}'
                          : 'Off',
                    ),
                    trailing: canWrite
                        ? FilledButton.tonal(
                            key: const Key('settings.maintenance.edit'),
                            onPressed: () => _editMaintenance(maintenance),
                            child: const Text('Change'),
                          )
                        : null,
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}
