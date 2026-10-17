import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api.dart';
import '../core/locale.dart';
import '../core/session.dart';
import '../l10n/app_localizations.dart';
import '../ui/widgets.dart';

/// Application-wide settings the mobile app reads at start-up, plus this
/// panel's own language.
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
    final l10n = AppLocalizations.of(context);
    final current = (row['value'] as Map<String, dynamic>?) ?? const {};
    final values = await showFormDialog(
      context,
      title: l10n.settingsConsentTitle,
      fields: [
        FormFieldSpec(
          key: 'parent_guardian_terms',
          label: l10n.settingsConsentField,
          required: true,
          maxLength: 40,
          initial: current['parent_guardian_terms'],
          help: l10n.settingsConsentHelp,
        ),
      ],
    );
    if (values == null || !mounted) return;
    final ok = await confirm(
      context,
      title: l10n.settingsConsentConfirmTitle,
      body: l10n.settingsConsentConfirmBody(
        '${values['parent_guardian_terms']}',
      ),
      confirmLabel: l10n.settingsConsentPublish,
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
      success: l10n.settingsConsentPublished,
    );
    if (done) _reload();
  }

  Future<void> _editMaintenance(Map<String, dynamic> row) async {
    final l10n = AppLocalizations.of(context);
    final current = (row['value'] as Map<String, dynamic>?) ?? const {};
    final values = await showFormDialog(
      context,
      title: l10n.settingsMaintenanceTitle,
      fields: [
        FormFieldSpec(
          key: 'enabled',
          label: l10n.settingsMaintenanceShow,
          kind: FieldKind.toggle,
          initial: current['enabled'] == true,
        ),
        FormFieldSpec(
          key: 'message',
          label: l10n.settingsMaintenanceMessage,
          kind: FieldKind.multiline,
          maxLength: 300,
          initial: current['message'],
          help: l10n.settingsMaintenanceHelp,
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
      success: l10n.settingsMaintenanceSaved,
    );
    if (done) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final canWrite = ref.watch(sessionProvider)?.can('settings:write') ?? false;
    final language = ref.watch(localeProvider).languageCode;
    return ListView(
      children: [
        PageHeader(title: l10n.settingsTitle, subtitle: l10n.settingsSubtitle),
        SectionCard(
          title: l10n.settingsLanguageTitle,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.settingsLanguageHelp),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                key: const Key('settings.language'),
                showSelectedIcon: false,
                segments: [
                  for (final e in kLanguageNames.entries)
                    ButtonSegment(
                      value: e.key,
                      label: Text(
                        e.value,
                        key: Key('settings.language.${e.key}'),
                      ),
                    ),
                ],
                selected: {language},
                onSelectionChanged: (v) =>
                    ref.read(localeProvider.notifier).choose(v.first),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        AsyncBody<List<Map<String, dynamic>>>(
          future: _future,
          onRetry: _reload,
          builder: (context, rows) {
            final consent = _find(rows, 'consent_versions');
            final maintenance = _find(rows, 'maintenance');
            final versions =
                (consent['value'] as Map<String, dynamic>?) ?? const {};
            final maint =
                (maintenance['value'] as Map<String, dynamic>?) ?? const {};
            final message = maint['message'] as String?;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  child: ListTile(
                    key: const Key('settings.consent'),
                    contentPadding: const EdgeInsets.all(16),
                    title: Text(l10n.settingsConsentTitle),
                    subtitle: Text(
                      l10n.settingsConsentSummary(
                            '${versions['parent_guardian_terms'] ?? '—'}',
                          ) +
                          (consent['overridden'] == true
                              ? ''
                              : '  ${l10n.settingsConsentDraft}'),
                    ),
                    trailing: canWrite
                        ? FilledButton.tonal(
                            key: const Key('settings.consent.edit'),
                            onPressed: () => _editConsent(consent),
                            child: Text(l10n.actionChange),
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    key: const Key('settings.maintenance'),
                    contentPadding: const EdgeInsets.all(16),
                    title: Text(l10n.settingsMaintenanceTitle),
                    subtitle: Text(
                      maint['enabled'] == true
                          ? l10n.settingsMaintenanceShowing(
                              message != null && message.isNotEmpty
                                  ? message
                                  : l10n.settingsMaintenanceDefault,
                            )
                          : l10n.statusOff,
                    ),
                    trailing: canWrite
                        ? FilledButton.tonal(
                            key: const Key('settings.maintenance.edit'),
                            onPressed: () => _editMaintenance(maintenance),
                            child: Text(l10n.actionChange),
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
