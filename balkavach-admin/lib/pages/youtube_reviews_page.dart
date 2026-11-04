import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api.dart';
import '../core/locale.dart';
import '../core/session.dart';
import '../l10n/app_localizations.dart';
import '../ui/widgets.dart';

const _topics = {
  'early_learning': 'Early learning',
  'math': 'Mathematics',
  'science': 'Science',
  'coding': 'Coding and computer science',
  'stories': 'Educational stories',
  'academic_explainers': 'Academic explainers',
  'nature': 'Nature',
  'animals': 'Animals',
  'language': 'Language',
  'art': 'Art',
  'preschool': 'Preschool',
};

const _statuses = [
  'discovered',
  'pending_review',
  'approved',
  'rejected',
  'quarantined',
  'revoked',
  'unavailable',
];

const _ageBands = {
  '3-5': '3–5',
  '6-8': '6–8',
  '9-12': '9–12',
  '13-15': '13–15',
};

class YouTubeReviewsPage extends ConsumerStatefulWidget {
  const YouTubeReviewsPage({super.key});

  @override
  ConsumerState<YouTubeReviewsPage> createState() => _YouTubeReviewsPageState();
}

class _YouTubeReviewsPageState extends ConsumerState<YouTubeReviewsPage> {
  int _reload = 0;
  String _status = 'pending_review';
  String _publication = 'all';
  String _published = 'all';
  Map<String, dynamic>? _diagnostics;
  Object? _diagnosticsError;
  bool _bulkRunning = false;
  String _bulkProgress = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refreshDiagnostics();
    });
  }

  bool get _canWrite => ref.watch(sessionProvider)?.can('video:write') ?? false;

  /// Reload the table and the status counts after any action that changes them.
  void _reloadAll() {
    setState(() => _reload++);
    _refreshDiagnostics();
  }

  Future<void> _refreshDiagnostics() async {
    setState(() => _diagnosticsError = null);
    try {
      final value = await ref
          .read(adminApiProvider)
          .getMap('/api/v1/admin/videos/youtube/diagnostics');
      if (mounted) setState(() => _diagnostics = value);
    } on Object catch (error) {
      if (mounted) setState(() => _diagnosticsError = error);
    }
  }

  Future<void> _publishApproved() async {
    if (_bulkRunning) return;
    setState(() {
      _bulkRunning = true;
      _bulkProgress = 'Starting eligibility checks';
    });
    String? afterId;
    var checked = 0;
    var published = 0;
    try {
      do {
        final result = await ref.read(adminApiProvider).post(
          '/api/v1/admin/videos/youtube/publish-approved',
          {'limit': 50, 'after_id': ?afterId},
        );
        checked += (result['checked'] as num?)?.toInt() ?? 0;
        published += (result['newly_published'] as num?)?.toInt() ?? 0;
        afterId = result['next_after_id'] as String?;
        if (mounted) {
          setState(
            () => _bulkProgress =
                'Checked $checked videos; published $published. '
                '${result['approved_unpublished_remaining'] ?? 0} remain unpublished.',
          );
        }
      } while (afterId != null);
      if (mounted) {
        showMessage(
          context,
          'Checked $checked approved videos; published $published.',
        );
        _reloadAll();
      }
    } on Object {
      if (mounted) {
        showMessage(context, AppLocalizations.of(context).youtubeActionFailed);
      }
    } finally {
      if (mounted) setState(() => _bulkRunning = false);
    }
  }

  Future<void> _reevaluate(
    Map<String, dynamic> row,
    BuildContext dialogContext,
  ) async {
    final ok = await runAction(
      context,
      () => ref
          .read(adminApiProvider)
          .post(
            '/api/v1/admin/videos/youtube/reviews/${row['id']}/reevaluate',
            const {},
          ),
    );
    if (ok && mounted && dialogContext.mounted) {
      Navigator.pop(dialogContext);
      _reloadAll();
    }
  }

  Future<void> _discover() async {
    final l10n = AppLocalizations.of(context);
    final values = await showFormDialog(
      context,
      title: l10n.youtubeDiscover,
      fields: [
        FormFieldSpec(
          key: 'topic',
          label: l10n.youtubeTopic,
          kind: FieldKind.choice,
          required: true,
          options: _topics,
          initial: _topics.keys.first,
        ),
        FormFieldSpec(
          key: 'max_results',
          label: l10n.youtubeMaxResults,
          kind: FieldKind.integer,
          required: true,
          min: 1,
          max: 50,
          initial: 10,
        ),
      ],
      submitLabel: l10n.youtubeDiscover,
    );
    if (values == null || !mounted) return;
    final ok = await runAction(
      context,
      () => ref
          .read(adminApiProvider)
          .post('/api/v1/admin/videos/youtube/discover', values),
    );
    if (ok && mounted) _reloadAll();
  }

  Future<void> _processWaiting() async {
    if (_bulkRunning) return;
    setState(() => _bulkRunning = true);
    final l10n = AppLocalizations.of(context);
    try {
      final result = await ref.read(adminApiProvider).post(
        '/api/v1/admin/videos/youtube/auto-review',
        {'limit': 200, 'include_quarantined': true},
      );
      if (!mounted) return;
      int n(String key) => (result[key] as num?)?.toInt() ?? 0;
      final retry = n('retry_later');
      showMessage(
        context,
        retry > 0
            ? l10n.youtubeAutoReviewRetry('$retry')
            : l10n.youtubeAutoReviewResult(
                '${n('checked')}',
                '${n('auto_approved')}',
                '${n('needs_manual_review')}',
                '${n('newly_quarantined')}',
              ),
      );
      _reloadAll();
    } on Object {
      if (mounted) showMessage(context, l10n.youtubeActionFailed);
    } finally {
      if (mounted) setState(() => _bulkRunning = false);
    }
  }

  Future<void> _recheck() async {
    final ok = await runAction(
      context,
      () => ref.read(adminApiProvider).post(
        '/api/v1/admin/videos/youtube/recheck',
        {'limit': 200},
      ),
    );
    if (ok && mounted) _reloadAll();
  }

  Future<void> _trustChannel(
    Map<String, dynamic> row,
    BuildContext dialogContext,
  ) async {
    final l10n = AppLocalizations.of(context);
    final channelId = '${row['channel_id'] ?? ''}';
    if (channelId.isEmpty || !mounted) return;
    final values = await showFormDialog(
      context,
      title: l10n.youtubeTrustChannelTitle,
      fields: [
        FormFieldSpec(
          key: 'age_band',
          label: l10n.youtubeAgeBand,
          kind: FieldKind.choice,
          required: true,
          options: _ageBands,
          initial: _ageBands.keys.first,
        ),
        FormFieldSpec(
          key: 'language_code',
          label: l10n.fieldLanguage,
          kind: FieldKind.choice,
          required: true,
          options: kLanguageNames,
          initial: 'en',
        ),
        FormFieldSpec(
          key: 'rights_cleared',
          label: l10n.youtubeRightsCleared,
          kind: FieldKind.toggle,
          initial: false,
        ),
        FormFieldSpec(
          key: 'notes',
          label: l10n.fieldDescription,
          kind: FieldKind.multiline,
          maxLength: 2000,
        ),
      ],
      submitLabel: l10n.youtubeTrustChannel,
    );
    if (values == null || !mounted) return;
    if (values['rights_cleared'] != true) {
      showMessage(context, l10n.youtubeRightsRequired);
      return;
    }
    final range = (values.remove('age_band') as String).split('-');
    values
      ..remove('rights_cleared')
      ..['channel_id'] = channelId
      ..['channel_title'] = row['channel_title']
      ..['age_min'] = int.parse(range.first)
      ..['age_max'] = int.parse(range.last)
      ..['rights_status'] = 'cleared';
    final ok = await runAction(
      context,
      () => ref
          .read(adminApiProvider)
          .post('/api/v1/admin/videos/youtube/channels/trust', values),
    );
    if (ok && mounted && dialogContext.mounted) {
      Navigator.pop(dialogContext);
      _reloadAll();
    }
  }

  Future<void> _untrustChannel(
    Map<String, dynamic> row,
    BuildContext dialogContext,
  ) async {
    final channelId = '${row['channel_id'] ?? ''}';
    if (channelId.isEmpty || !mounted) return;
    final ok = await runAction(
      context,
      () => ref
          .read(adminApiProvider)
          .post(
            '/api/v1/admin/videos/youtube/channels/$channelId/untrust',
            const {},
          ),
    );
    if (ok && mounted && dialogContext.mounted) {
      Navigator.pop(dialogContext);
      _reloadAll();
    }
  }

  Future<void> _inspect(Map<String, dynamic> row) async {
    final l10n = AppLocalizations.of(context);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${row['title'] ?? l10n.youtubeReviewDetails}'),
        content: SizedBox(
          width: 600,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (row['thumbnail_url'] is String)
                  Image.network(
                    row['thumbnail_url'] as String,
                    height: 180,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                _metadata('Status', row['status']),
                _metadata('Channel ID', row['channel_id']),
                _metadata('Channel', row['channel_title']),
                _metadata('Publication', row['publication_source']),
                _metadata('Publication status', row['publication_status']),
                _metadata('Published at', row['published_at']),
                _metadata('Publication reason', row['publication_reason']),
                _metadata('Not published reason', row['not_published_reason']),
                _metadata('Source', row['source_url']),
                _metadata('Discovery topic', row['discovery_topic']),
                _metadata('YouTube category', row['youtube_category_id']),
                _metadata('Made for kids', row['made_for_kids']),
                _metadata('Duration (seconds)', row['duration_seconds']),
                _metadata('Language', row['language_code']),
                _metadata(
                  'Age range',
                  '${row['age_min'] ?? '—'}–${row['age_max'] ?? '—'}',
                ),
                _metadata(
                  'Category',
                  row['category_name'] ?? row['category_id'],
                ),
                _metadata('Child feed', switch (row['video_format']) {
                  'short' => 'Shorts',
                  'regular' => 'Regular videos',
                  _ => 'Unknown duration',
                }),
                _metadata('Rights', row['rights_status']),
                if ((row['description'] as String?)?.isNotEmpty ?? false)
                  _metadata('Description', row['description']),
                const SizedBox(height: 8),
                Text(
                  l10n.youtubeScreening,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                for (final flag
                    in (row['screening_flags'] as List<dynamic>? ?? const []))
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('• $flag'),
                  ),
                if ((row['review_notes'] as String?)?.isNotEmpty ?? false)
                  _metadata('Reviewer notes', row['review_notes']),
                if (row['last_verified_at'] != null)
                  _metadata('Last verified', row['last_verified_at']),
              ],
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () => _openSource(row),
            icon: const Icon(Icons.open_in_new),
            label: Text(l10n.youtubePreview),
          ),
          if (_canWrite &&
              (row['status'] == 'pending_review' ||
                  row['status'] == 'quarantined'))
            TextButton(
              onPressed: () => _reject(row, dialogContext),
              child: Text(l10n.youtubeActionReject),
            ),
          if (_canWrite && row['status'] == 'pending_review')
            FilledButton(
              onPressed: () => _approve(row, dialogContext),
              child: Text(l10n.youtubeActionApprove),
            ),
          if (_canWrite && row['status'] == 'quarantined')
            FilledButton.icon(
              key: Key('youtube.reevaluate.${row['id']}'),
              onPressed: () => _reevaluate(row, dialogContext),
              icon: const Icon(Icons.fact_check_outlined),
              label: Text(l10n.youtubeReevaluate),
            ),
          if (_canWrite && row['status'] == 'approved')
            FilledButton(
              onPressed: () => _revoke(row, dialogContext),
              child: Text(l10n.youtubeActionRevoke),
            ),
          if (_canWrite && row['channel_id'] != null)
            TextButton(
              onPressed: () => _trustChannel(row, dialogContext),
              child: Text(l10n.youtubeTrustChannel),
            ),
          if (_canWrite && row['channel_id'] != null)
            TextButton(
              onPressed: () => _untrustChannel(row, dialogContext),
              child: Text(l10n.youtubeUntrustChannel),
            ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(
              MaterialLocalizations.of(dialogContext).closeButtonLabel,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openSource(Map<String, dynamic> row) async {
    final l10n = AppLocalizations.of(context);
    final url = Uri.tryParse('${row['source_url'] ?? ''}');
    if (url == null || url.scheme != 'https' || url.host.isEmpty) {
      showMessage(context, l10n.youtubeActionFailed);
      return;
    }
    try {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication) &&
          mounted) {
        showMessage(context, l10n.youtubeActionFailed);
      }
    } on PlatformException {
      if (mounted) showMessage(context, l10n.youtubeActionFailed);
    }
  }

  /// Who decided and, when the video is not published, why not.
  Widget _decision(AppLocalizations l10n, Map<String, dynamic> row) {
    final approved = row['status'] == 'approved';
    final headline = !approved
        ? l10n.youtubeDecisionWaiting
        : row['publication_source'] == 'automatic'
        ? l10n.youtubeDecisionAutomatic
        : l10n.youtubeDecisionManual;
    final reason =
        (row['not_published_reason'] as String?) ??
        (row['publication_reason'] as String?);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(headline, key: Key('youtube.decision.${row['id']}')),
        if (reason != null && reason.isNotEmpty)
          Text(
            l10n.youtubeReasonLabel(reason),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );
  }

  Widget _metadata(String label, Object? value) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: SelectableText('$label: ${value ?? '—'}'),
  );

  Future<void> _approve(
    Map<String, dynamic> row,
    BuildContext dialogContext,
  ) async {
    final l10n = AppLocalizations.of(context);
    final values = await showFormDialog(
      context,
      title: l10n.youtubeActionApprove,
      fields: [
        FormFieldSpec(
          key: 'age_band',
          label: l10n.youtubeAgeBand,
          kind: FieldKind.choice,
          required: true,
          options: _ageBands,
          initial: _ageBands.keys.first,
        ),
        FormFieldSpec(
          key: 'language_code',
          label: l10n.fieldLanguage,
          kind: FieldKind.choice,
          required: true,
          options: kLanguageNames,
          initial: 'en',
        ),
        FormFieldSpec(
          key: 'rights_cleared',
          label: l10n.youtubeRightsCleared,
          kind: FieldKind.toggle,
          initial: false,
        ),
        FormFieldSpec(
          key: 'notes',
          label: l10n.fieldDescription,
          kind: FieldKind.multiline,
          maxLength: 2000,
        ),
      ],
      submitLabel: l10n.youtubeActionApprove,
    );
    if (values == null || !mounted) return;
    if (values['rights_cleared'] != true) {
      showMessage(context, l10n.youtubeRightsRequired);
      return;
    }
    final range = (values.remove('age_band') as String).split('-');
    values
      ..remove('rights_cleared')
      ..['age_min'] = int.parse(range.first)
      ..['age_max'] = int.parse(range.last)
      ..['rights_status'] = 'cleared';
    final ok = await runAction(
      context,
      () => ref
          .read(adminApiProvider)
          .post(
            '/api/v1/admin/videos/youtube/reviews/${row['id']}/approve',
            values,
          ),
    );
    if (ok && mounted && dialogContext.mounted) {
      Navigator.pop(dialogContext);
      _reloadAll();
    }
  }

  Future<void> _reject(
    Map<String, dynamic> row,
    BuildContext dialogContext,
  ) async {
    final l10n = AppLocalizations.of(context);
    final values = await showFormDialog(
      context,
      title: l10n.youtubeActionReject,
      fields: [
        FormFieldSpec(
          key: 'notes',
          label: l10n.youtubeRejectReason,
          kind: FieldKind.multiline,
          required: true,
          maxLength: 2000,
        ),
      ],
      submitLabel: l10n.youtubeActionReject,
    );
    if (values == null || !mounted) return;
    final ok = await runAction(
      context,
      () => ref
          .read(adminApiProvider)
          .post(
            '/api/v1/admin/videos/youtube/reviews/${row['id']}/reject',
            values,
          ),
    );
    if (ok && mounted && dialogContext.mounted) {
      Navigator.pop(dialogContext);
      _reloadAll();
    }
  }

  Future<void> _revoke(
    Map<String, dynamic> row,
    BuildContext dialogContext,
  ) async {
    final l10n = AppLocalizations.of(context);
    final values = await showFormDialog(
      context,
      title: l10n.youtubeActionRevoke,
      fields: [
        FormFieldSpec(
          key: 'reason',
          label: l10n.youtubeRejectReason,
          kind: FieldKind.multiline,
          required: true,
          maxLength: 2000,
        ),
      ],
      submitLabel: l10n.youtubeActionRevoke,
    );
    if (values == null || !mounted) return;
    final ok = await runAction(
      context,
      () => ref
          .read(adminApiProvider)
          .post(
            '/api/v1/admin/videos/youtube/reviews/${row['id']}/revoke',
            values,
          ),
    );
    if (ok && mounted && dialogContext.mounted) {
      Navigator.pop(dialogContext);
      _reloadAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListView(
      children: [
        PageHeader(
          title: l10n.youtubeReviewsTitle,
          subtitle: l10n.youtubeReviewsSubtitle,
          actions: [
            if (_canWrite)
              FilledButton.icon(
                key: const Key('youtube.autoReview'),
                onPressed: _bulkRunning ? null : _processWaiting,
                icon: const Icon(Icons.auto_mode_outlined),
                label: Text(l10n.youtubeAutoReview),
              ),
            if (_canWrite)
              OutlinedButton.icon(
                key: const Key('youtube.recheck'),
                onPressed: _recheck,
                icon: const Icon(Icons.sync),
                label: Text(l10n.youtubeRecheck),
              ),
            if (_canWrite)
              FilledButton.icon(
                key: const Key('youtube.discover'),
                onPressed: _discover,
                icon: const Icon(Icons.search),
                label: Text(l10n.youtubeDiscover),
              ),
            if (_canWrite)
              FilledButton.icon(
                key: const Key('youtube.publishApproved'),
                onPressed: _bulkRunning ? null : _publishApproved,
                icon: const Icon(Icons.publish_outlined),
                label: Text(l10n.youtubePublishApproved),
              ),
          ],
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: 260,
                child: DropdownButtonFormField<String>(
                  key: const Key('youtube.status'),
                  initialValue: _status,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: l10n.youtubeStatus),
                  items: [
                    DropdownMenuItem(
                      value: 'all',
                      child: Text(l10n.youtubeAll),
                    ),
                    for (final status in _statuses)
                      DropdownMenuItem(value: status, child: Text(status)),
                  ],
                  onChanged: (status) {
                    if (status != null) {
                      setState(() {
                        _status = status;
                        _reload++;
                      });
                    }
                  },
                ),
              ),
              SizedBox(
                width: 160,
                child: DropdownButtonFormField<String>(
                  key: const Key('youtube.publication'),
                  initialValue: _publication,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: l10n.youtubeSource),
                  items: [
                    DropdownMenuItem(
                      value: 'all',
                      child: Text(l10n.youtubeAllOption),
                    ),
                    DropdownMenuItem(
                      value: 'automatic',
                      child: Text(l10n.youtubeAutomatic),
                    ),
                    DropdownMenuItem(
                      value: 'manual',
                      child: Text(l10n.youtubeManual),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _publication = value;
                        _reload++;
                      });
                    }
                  },
                ),
              ),
              SizedBox(
                width: 150,
                child: DropdownButtonFormField<String>(
                  key: const Key('youtube.published'),
                  initialValue: _published,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: l10n.youtubeAvailability,
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 'all',
                      child: Text(l10n.youtubeAllOption),
                    ),
                    DropdownMenuItem(
                      value: 'true',
                      child: Text(l10n.youtubePublished),
                    ),
                    DropdownMenuItem(
                      value: 'false',
                      child: Text(l10n.youtubeUnpublished),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _published = value;
                        _reload++;
                      });
                    }
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: l10n.youtubeSummaryTitle,
          child: _diagnostics == null
              ? const SizedBox.shrink()
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 24,
                      runSpacing: 8,
                      children: [
                        for (final entry in <String, String>{
                          l10n.youtubeCountApproved: 'approved',
                          l10n.youtubeCountPending: 'pending_review',
                          l10n.youtubeCountQuarantined: 'quarantined',
                          l10n.youtubeCountRejected: 'rejected',
                          l10n.youtubeCountPublished: 'published',
                        }.entries)
                          Text(
                            '${entry.key}: ${_diagnostics![entry.value] ?? 0}',
                            key: Key('youtube.count.${entry.value}'),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.youtubeApprovedBySource(
                        '${_diagnostics!['approved_automatic'] ?? 0}',
                        '${_diagnostics!['approved_manual'] ?? 0}',
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.youtubeFreshness(
                        '${_diagnostics!['oldest_approved_verification'] ?? '—'}',
                        '${_diagnostics!['reverify_hours'] ?? 72}',
                        '${_diagnostics!['approved_stale'] ?? 0}',
                      ),
                      key: const Key('youtube.freshness'),
                    ),
                    const SizedBox(height: 4),
                    Text(l10n.youtubeAutoNote),
                  ],
                ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: l10n.youtubeDiagnosticsTitle,
          trailing: IconButton(
            key: const Key('youtube.refreshDiagnostics'),
            tooltip: l10n.youtubeDiagnosticsRefresh,
            onPressed: _refreshDiagnostics,
            icon: const Icon(Icons.refresh),
          ),
          child: _diagnosticsError != null
              ? Text(l10n.youtubeDiagnosticsUnavailable('$_diagnosticsError'))
              : _diagnostics == null
              ? const Text(
                  'Refresh diagnostics to inspect the production pipeline.',
                )
              : Wrap(
                  spacing: 24,
                  runSpacing: 8,
                  children: [
                    for (final entry in <String, String>{
                      'All video records':
                          '${_diagnostics!['total_video_records'] ?? 0}',
                      'Discovered': '${_diagnostics!['total_discovered'] ?? 0}',
                      'Automatic':
                          '${_diagnostics!['automatically_published'] ?? 0}',
                      'Manual': '${_diagnostics!['manually_published'] ?? 0}',
                      'Approved and published':
                          '${_diagnostics!['approved_published'] ?? 0}',
                      'Approved unpublished':
                          '${_diagnostics!['approved_unpublished'] ?? 0}',
                      'Eligible after DB checks':
                          '${_diagnostics!['eligible_approved_unpublished'] ?? 0}',
                      'Published Shorts rows':
                          '${_diagnostics!['published_shorts'] ?? 0}',
                      'Pending admin review':
                          '${_diagnostics!['pending_review_unpublished'] ?? 0}',
                      'Quarantined': '${_diagnostics!['quarantined'] ?? 0}',
                      'Rejected': '${_diagnostics!['rejected'] ?? 0}',
                      'Revoked': '${_diagnostics!['revoked'] ?? 0}',
                      'Unavailable': '${_diagnostics!['unavailable'] ?? 0}',
                      'Rights not cleared':
                          '${_diagnostics!['rights_not_cleared'] ?? 0}',
                      'Safety screening failed':
                          '${_diagnostics!['safety_screening_failed'] ?? 0}',
                      'Blocked by rights or safety':
                          '${_diagnostics!['blocked_by_rights_or_safety'] ?? 0}',
                      'Invalid age band':
                          '${_diagnostics!['invalid_age_band'] ?? 0}',
                    }.entries)
                      Text('${entry.key}: ${entry.value}'),
                    Text(
                      'Last discovery: ${_diagnostics!['last_discovery_run'] ?? '—'}',
                    ),
                    Text(
                      'Last discovery result: ${_diagnostics!['last_discovery_result'] ?? '—'}',
                    ),
                    for (final entry
                        in (_diagnostics!['quarantine_reasons']
                                    as Map<String, dynamic>? ??
                                const {})
                            .entries)
                      Text(
                        l10n.youtubeQuarantineReason(
                          entry.key,
                          '${entry.value}',
                        ),
                      ),
                    for (final entry
                        in (_diagnostics!['publication_failure_reasons']
                                    as Map<String, dynamic>? ??
                                const {})
                            .entries)
                      Text(
                        l10n.youtubeBlockedReason(entry.key, '${entry.value}'),
                      ),
                  ],
                ),
        ),
        if (_bulkRunning) ...[
          const LinearProgressIndicator(),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(_bulkProgress),
          ),
        ],
        const SizedBox(height: 12),
        PagedTable(
          key: const Key('youtube.reviews'),
          compactWidth: 1800,
          reloadKey: _reload,
          emptyMessage: l10n.youtubeCandidateEmpty,
          fetch: (offset, limit) => ref
              .read(adminApiProvider)
              .getList(
                '/api/v1/admin/videos/youtube/reviews',
                query: {
                  if (_status != 'all') 'status': _status,
                  if (_publication != 'all') 'publication_source': _publication,
                  if (_published != 'all') 'is_published': _published,
                  'limit': limit,
                  'offset': offset,
                },
              ),
          columns: [
            'Thumbnail',
            l10n.fieldTitle,
            'Channel',
            'Category / age',
            l10n.youtubeStatus,
            l10n.youtubeDecisionColumn,
            'Screening / rights',
            '',
          ],
          cells: (context, row, reload) => [
            row['thumbnail_url'] is String
                ? Image.network(
                    row['thumbnail_url'] as String,
                    width: 72,
                    height: 48,
                    fit: BoxFit.cover,
                  )
                : const SizedBox(width: 72, height: 48),
            Text('${row['title'] ?? '—'}'),
            Text('${row['channel_title'] ?? '—'}'),
            Text(
              '${row['category_name'] ?? row['category_id'] ?? '—'}\nAge ${row['age_min'] ?? '—'}–${row['age_max'] ?? '—'}',
            ),
            StatusPill(
              label: '${row['status'] ?? '—'}',
              good: row['status'] == 'approved',
            ),
            _decision(l10n, row),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.youtubeRights('${row['rights_status'] ?? '—'}')),
                Text(
                  (row['screening_flags'] as List<dynamic>? ?? const []).join(
                    ', ',
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
            TextButton(
              key: Key('youtube.inspect.${row['id']}'),
              onPressed: () => _inspect(row),
              child: Text(l10n.youtubeActionOpen),
            ),
          ],
        ),
      ],
    );
  }
}
