import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api.dart';
import '../core/session.dart';
import '../l10n/app_localizations.dart';
import '../ui/widgets.dart';
import 'mission_variation_editor.dart';

class MissionsPage extends ConsumerStatefulWidget {
  const MissionsPage({super.key});

  @override
  ConsumerState<MissionsPage> createState() => _MissionsPageState();
}

class _MissionsPageState extends ConsumerState<MissionsPage> {
  final _search = TextEditingController();
  String _query = '';
  String _state = '';
  int _catalogRevision = 0;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final canWrite = ref.watch(sessionProvider)?.can('tasks:write') ?? false;
    return ListView(
      children: [
        PageHeader(title: l10n.missionsTitle, subtitle: l10n.missionsSubtitle),
        FilterBar(
          searchKey: const Key('missions.search'),
          applyKey: const Key('missions.apply'),
          searchLabel: l10n.missionsSearch,
          controller: _search,
          onSearch: (v) => setState(() => _query = v),
          filters: [
            FilterDropdown(
              fieldKey: const Key('missions.state'),
              value: _state,
              options: {
                '': l10n.filterAll,
                'true': l10n.statusActive,
                'false': l10n.statusDeactivated,
              },
              onChanged: (v) => setState(() => _state = v),
            ),
          ],
        ),
        _DailyMissionCatalog(
          revision: _catalogRevision,
          canWrite: canWrite,
          onChanged: () => setState(() => _catalogRevision++),
        ),
        PagedTable(
          reloadKey: '$_query|$_state',
          emptyMessage: l10n.missionsEmpty,
          fetch: (offset, limit) => ref
              .read(adminApiProvider)
              .getList(
                '/api/v1/admin/tasks',
                query: {
                  'limit': limit,
                  'offset': offset,
                  if (_query.isNotEmpty) 'q': _query,
                  if (_state.isNotEmpty) 'is_active': _state,
                },
              ),
          columns: [
            l10n.colMission,
            l10n.colFamily,
            l10n.colCategory,
            l10n.colChild,
            l10n.colStarsXp,
            l10n.colVideoRequirement,
            l10n.colStatus,
            '',
          ],
          cells: (context, row, reload) {
            final active = row['is_active'] == true;
            return [
              Text('${row['title']}'),
              Text('${row['family_name']}'),
              Text('${row['category_name'] ?? '—'}'),
              Text('${row['assigned_child_name'] ?? l10n.missionAnyChild}'),
              Text('${row['star_reward']} / ${row['xp_reward']}'),
              Text(
                row['required_video_seconds'] == null
                    ? '—'
                    : l10n.missionCatalogMinutes(
                        ((row['required_video_seconds'] as num).toInt() + 59) ~/
                            60,
                      ),
              ),
              StatusPill(
                label: active ? l10n.statusActive : l10n.statusDeactivated,
                good: active,
              ),
              if (canWrite)
                TextButton(
                  key: Key('mission.toggle.${row['id']}'),
                  onPressed: () async {
                    final ok = await confirm(
                      context,
                      title: active
                          ? l10n.missionDeactivateTitle
                          : l10n.missionReactivateTitle,
                      body: l10n.missionConfirmBody(
                        '${row['title']}',
                        '${row['family_name']}',
                      ),
                      confirmLabel: active
                          ? l10n.actionDeactivate
                          : l10n.actionReactivate,
                    );
                    if (!ok || !context.mounted) return;
                    final done = await runAction(
                      context,
                      () => ref.read(adminApiProvider).patch(
                        '/api/v1/admin/tasks/${row['id']}/active',
                        {'is_active': !active},
                      ),
                      success: active
                          ? l10n.missionDeactivated
                          : l10n.missionReactivated,
                    );
                    if (done) reload();
                  },
                  child: Text(
                    active ? l10n.actionDeactivate : l10n.actionReactivate,
                  ),
                )
              else
                const SizedBox.shrink(),
            ];
          },
        ),
      ],
    );
  }
}

class _DailyMissionCatalog extends ConsumerWidget {
  const _DailyMissionCatalog({
    required this.revision,
    required this.canWrite,
    required this.onChanged,
  });

  final int revision;
  final bool canWrite;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return FutureBuilder<List<Map<String, dynamic>>>(
      key: ValueKey(revision),
      future: ref
          .read(adminApiProvider)
          .getList('/api/v1/admin/daily-missions/templates'),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final templates = snapshot.data!;
        return Card(
          child: ExpansionTile(
            title: Text(l10n.navMissions),
            subtitle: Text(l10n.colActiveMissions),
            children: [
              _CatalogHealth(revision: revision),
              for (final template in templates)
                _TemplateTile(
                  template: template,
                  canWrite: canWrite,
                  onChanged: onChanged,
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Rotation capacity per weekday theme: how many complete, published templates a child can rotate through.
class _CatalogHealth extends ConsumerStatefulWidget {
  const _CatalogHealth({required this.revision});

  final int revision;

  @override
  ConsumerState<_CatalogHealth> createState() => _CatalogHealthState();
}

class _CatalogHealthState extends ConsumerState<_CatalogHealth> {
  late Future<Map<String, dynamic>> _health = _load();

  // Loaded once per revision, not on every rebuild (a window resize must not re-request).
  Future<Map<String, dynamic>> _load() => ref
      .read(adminApiProvider)
      .getMap('/api/v1/admin/daily-missions/catalogue-health');

  @override
  void didUpdateWidget(_CatalogHealth oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revision != widget.revision) _health = _load();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return FutureBuilder<Map<String, dynamic>>(
      future: _health,
      builder: (context, snapshot) {
        // The health view is advisory: if it cannot load, the template list below still works.
        if (!snapshot.hasData) return const SizedBox.shrink();
        final health = snapshot.data!;
        final themes = (health['themes'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
        final fallbacks = health['fallbacks'] as Map<String, dynamic>;
        return Padding(
          key: const Key('catalog.health'),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.missionHealthTitle,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              for (final theme in themes)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        theme['insufficient'] == true
                            ? Icons.warning_amber_rounded
                            : Icons.check_circle_outline,
                        size: 18,
                        color: theme['insufficient'] == true
                            ? Theme.of(context).colorScheme.error
                            : null,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.missionHealthTheme(
                                _themeLabel('${theme['theme']}'),
                                theme['eligible'] as int,
                                theme['published'] as int,
                                theme['templates'] as int,
                              ),
                              key: Key('catalog.health.${theme['theme']}'),
                            ),
                            Text(
                              theme['insufficient'] == true
                                  ? l10n.missionHealthLow(
                                      health['min_eligible_per_theme'] as int,
                                      theme['shortfall'] as int,
                                    )
                                  : l10n.missionHealthOk,
                              style: TextStyle(
                                color: theme['insufficient'] == true
                                    ? Theme.of(context).colorScheme.error
                                    : null,
                              ),
                            ),
                            if (theme['healthy'] != null)
                              Text(
                                l10n.missionHealthActivities(
                                  (theme['verified_distinct'] as int?) ?? 0,
                                  health['min_eligible_per_theme'] as int,
                                ),
                                key: Key(
                                  'catalog.health.activities.${theme['theme']}',
                                ),
                                style: TextStyle(
                                  color:
                                      theme['healthy'] == true ||
                                          theme['insufficient'] == true
                                      ? null
                                      : Theme.of(context).colorScheme.error,
                                ),
                              ),
                            if (((theme['unverified'] as List<dynamic>?) ??
                                    const [])
                                .isNotEmpty)
                              Text(
                                l10n.missionHealthActivitiesUnchecked(
                                  (theme['unverified'] as List<dynamic>).length,
                                ),
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 4),
              if (health['totals'] != null)
                Text(
                  l10n.missionHealthTotals(
                    (health['totals'] as Map<String, dynamic>)['published']
                        as int,
                    (health['totals'] as Map<String, dynamic>)['unpublished']
                        as int,
                    (health['totals'] as Map<String, dynamic>)['incomplete']
                        as int,
                    (health['totals'] as Map<String, dynamic>)['templates']
                        as int,
                  ),
                  key: const Key('catalog.health.totals'),
                ),
              Text(
                l10n.missionHealthFallbacks(
                  fallbacks['count'] as int,
                  fallbacks['days'] as int,
                ),
                key: const Key('catalog.health.fallbacks'),
              ),
              const Divider(),
            ],
          ),
        );
      },
    );
  }
}

/// `monday_sound_detective` -> `Monday: sound detective`.
String _themeLabel(String key) {
  final parts = key.split('_');
  if (parts.length < 2) return key;
  final day = parts.first[0].toUpperCase() + parts.first.substring(1);
  return '$day: ${parts.sublist(1).join(' ')}';
}

const _bands = ['4_6', '7_10', '11_15'];
const _languages = {'en': 'English', 'gu': 'ગુજરાતી', 'hi': 'हिन्दी'};

String _ageRange(String band) => band.replaceAll('_', '–');

List<String> _missingOf(Map<String, dynamic> template) => [
  for (final item in (template['missing'] as List<dynamic>? ?? const []))
    '$item',
];

String _describeMissing(List<String> missing) => missing
    .map((item) {
      final parts = item.split(':');
      return '${_ageRange(parts.first)} ${parts.last.toUpperCase()}';
    })
    .join(', ');

/// One catalogue template: its completeness, a way to inspect every version, and the publish switch.
class _TemplateTile extends ConsumerWidget {
  const _TemplateTile({
    required this.template,
    required this.canWrite,
    required this.onChanged,
  });

  final Map<String, dynamic> template;
  final bool canWrite;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final missing = _missingOf(template);
    final complete = missing.isEmpty;
    return ListTile(
      title: Text('${template['slug']}'),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${template['theme']} - ${template['mission_type']}'),
          Text(
            l10n.missionCatalogShown(template['assignment_count'] as int? ?? 0),
            key: Key('catalog.shown.${template['id']}'),
          ),
          Text(
            complete
                ? l10n.missionCatalogComplete
                : l10n.missionCatalogMissing(
                    missing.length,
                    _describeMissing(missing),
                  ),
            key: Key('catalog.status.${template['id']}'),
            style: TextStyle(
              color: complete ? null : Theme.of(context).colorScheme.error,
            ),
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: Key('catalog.view.${template['id']}'),
            tooltip: l10n.missionCatalogViewVersions,
            icon: const Icon(Icons.visibility_outlined),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => _TemplateDetailDialog(
                templateId: '${template['id']}',
                canWrite: canWrite,
              ),
            ),
          ),
          if (canWrite)
            Switch(
              key: Key('catalog.publish.${template['id']}'),
              value: template['is_published'] == true,
              onChanged: (publish) async {
                if (publish && !complete) {
                  showMessage(
                    context,
                    l10n.missionCatalogCannotPublish(_describeMissing(missing)),
                  );
                  return;
                }
                var done = false;
                try {
                  await ref
                      .read(adminApiProvider)
                      .patch(
                        '/api/v1/admin/daily-missions/templates/${template['id']}/publish',
                        {},
                        query: {'publish': publish},
                      );
                  done = true;
                  if (context.mounted) {
                    showMessage(
                      context,
                      publish ? l10n.statusActive : l10n.statusDeactivated,
                    );
                  }
                } on ApiError catch (error) {
                  if (!context.mounted) return;
                  if (error.code == 'daily_template_instructions_incomplete') {
                    await showPublishProblems(context, error.details);
                  } else {
                    showError(context, error);
                  }
                }
                if (done) onChanged();
              },
            ),
        ],
      ),
    );
  }
}

/// Every age band x language of one template, with the text a child (and the reviewing parent) will see.
class _TemplateDetailDialog extends ConsumerStatefulWidget {
  const _TemplateDetailDialog({
    required this.templateId,
    this.canWrite = false,
  });

  final String templateId;
  final bool canWrite;

  @override
  ConsumerState<_TemplateDetailDialog> createState() =>
      _TemplateDetailDialogState();
}

class _TemplateDetailDialogState extends ConsumerState<_TemplateDetailDialog> {
  late Future<Map<String, dynamic>> _detail = _load();

  Future<Map<String, dynamic>> _load() => ref
      .read(adminApiProvider)
      .getMap('/api/v1/admin/daily-missions/templates/${widget.templateId}');
  String _band = _bands.first;
  String _language = 'en';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      content: SizedBox(
        width: 560,
        child: FutureBuilder<Map<String, dynamic>>(
          future: _detail,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Text(describeError(l10n, snapshot.error!));
            }
            if (!snapshot.hasData) {
              return const SizedBox(
                height: 80,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final detail = snapshot.data!;
            final variations = (detail['variations'] as List<dynamic>)
                .cast<Map<String, dynamic>>();
            Map<String, dynamic>? find(String band, String language) {
              for (final v in variations) {
                if (v['age_band'] == band && v['locale'] == language) return v;
              }
              return null;
            }

            final chosen = find(_band, _language);
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${detail['slug']}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  for (final band in _bands)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          SizedBox(
                            width: 96,
                            child: Text(
                              l10n.missionCatalogAges(_ageRange(band)),
                            ),
                          ),
                          for (final entry in _languages.entries)
                            _VersionChip(
                              chipKey: Key('catalog.cell.$band.${entry.key}'),
                              name: entry.value,
                              exists: find(band, entry.key) != null,
                              selected: band == _band && entry.key == _language,
                              onSelected: () => setState(() {
                                _band = band;
                                _language = entry.key;
                              }),
                            ),
                        ],
                      ),
                    ),
                  const Divider(),
                  Text(
                    l10n.missionCatalogPreview,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  if (chosen == null)
                    Text(
                      l10n.missionCatalogVersionMissing,
                      key: const Key('catalog.preview.missing'),
                    )
                  else ...[
                    Text(
                      '${chosen['title']}',
                      key: const Key('catalog.preview.title'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      '${l10n.missionCatalogMinutes(chosen['duration_minutes'] as int)} · '
                      '${l10n.missionCatalogMaterials((chosen['required_materials'] as List<dynamic>).join(', '))}',
                    ),
                    const SizedBox(height: 8),
                    SelectableText(
                      '${chosen['preview']}',
                      key: const Key('catalog.preview.text'),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.missionCatalogSafety(
                        '${chosen['safety_instructions']}',
                      ),
                    ),
                    if (chosen['issues'] is Map<String, dynamic>) ...[
                      const SizedBox(height: 8),
                      MissionIssueList(
                        key: const Key('catalog.issues.errors'),
                        title: l10n.missionEditErrors,
                        issues:
                            ((chosen['issues']
                                            as Map<String, dynamic>)['errors']
                                        as List<dynamic>? ??
                                    const [])
                                .cast<Map<String, dynamic>>(),
                      ),
                      MissionIssueList(
                        key: const Key('catalog.issues.warnings'),
                        title: l10n.missionEditWarnings,
                        isError: false,
                        issues:
                            ((chosen['issues']
                                            as Map<String, dynamic>)['warnings']
                                        as List<dynamic>? ??
                                    const [])
                                .cast<Map<String, dynamic>>(),
                      ),
                    ],
                    if (widget.canWrite)
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                          key: const Key('catalog.edit'),
                          icon: const Icon(Icons.edit_outlined),
                          label: Text(l10n.missionEditEdit),
                          onPressed: () async {
                            final saved = await showDialog<bool>(
                              context: context,
                              builder: (_) => VariationEditorDialog(
                                templateId: widget.templateId,
                                variation: chosen,
                              ),
                            );
                            if (saved == true && mounted) {
                              setState(() {
                                _detail = _load();
                              });
                            }
                          },
                        ),
                      ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.actionClose),
        ),
      ],
    );
  }
}

class _VersionChip extends StatelessWidget {
  const _VersionChip({
    required this.chipKey,
    required this.name,
    required this.exists,
    required this.selected,
    required this.onSelected,
  });

  final Key chipKey;
  final String name;
  final bool exists;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ChoiceChip(
      key: chipKey,
      avatar: Icon(
        exists ? Icons.check_circle_outline : Icons.error_outline,
        size: 18,
      ),
      label: Text(
        exists ? name : '$name · ${l10n.missionCatalogVersionMissing}',
      ),
      selected: selected,
      onSelected: (_) => onSelected(),
    );
  }
}
