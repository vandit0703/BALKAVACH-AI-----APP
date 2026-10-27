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

const _ageBands = {'4-7': '4–7', '8-11': '8–11', '12-15': '12–15'};

class YouTubeReviewsPage extends ConsumerStatefulWidget {
  const YouTubeReviewsPage({super.key});

  @override
  ConsumerState<YouTubeReviewsPage> createState() => _YouTubeReviewsPageState();
}

class _YouTubeReviewsPageState extends ConsumerState<YouTubeReviewsPage> {
  int _reload = 0;
  String _status = 'pending_review';

  bool get _canWrite => ref.watch(sessionProvider)?.can('video:write') ?? false;

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
    if (ok && mounted) setState(() => _reload++);
  }

  Future<void> _recheck() async {
    final ok = await runAction(
      context,
      () => ref.read(adminApiProvider).post(
        '/api/v1/admin/videos/youtube/recheck',
        {'limit': 200},
      ),
    );
    if (ok && mounted) setState(() => _reload++);
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
                _metadata('Channel', row['channel_title']),
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
            label: Text(l10n.youtubeOpenSource),
          ),
          if (_canWrite &&
              (row['status'] == 'pending_review' ||
                  row['status'] == 'quarantined'))
            TextButton(
              onPressed: () => _reject(row, dialogContext),
              child: Text(l10n.youtubeActionReject),
            ),
          if (_canWrite &&
              (row['status'] == 'pending_review' ||
                  row['status'] == 'quarantined'))
            FilledButton(
              onPressed: () => _approve(row, dialogContext),
              child: Text(l10n.youtubeActionApprove),
            ),
          if (_canWrite && row['status'] == 'approved')
            FilledButton(
              onPressed: () => _revoke(row, dialogContext),
              child: Text(l10n.youtubeActionRevoke),
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
      setState(() => _reload++);
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
      setState(() => _reload++);
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
      setState(() => _reload++);
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
          ],
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: 260,
            child: DropdownButtonFormField<String>(
              key: const Key('youtube.status'),
              initialValue: _status,
              isExpanded: true,
              decoration: InputDecoration(labelText: l10n.youtubeStatus),
              items: [
                DropdownMenuItem(value: 'all', child: Text(l10n.youtubeAll)),
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
        ),
        const SizedBox(height: 12),
        PagedTable(
          key: const Key('youtube.reviews'),
          reloadKey: _reload,
          emptyMessage: l10n.youtubeCandidateEmpty,
          fetch: (offset, limit) => ref
              .read(adminApiProvider)
              .getList(
                '/api/v1/admin/videos/youtube/reviews',
                query: {
                  if (_status != 'all') 'status': _status,
                  'limit': limit,
                  'offset': offset,
                },
              ),
          columns: [
            l10n.fieldTitle,
            'Channel',
            l10n.youtubeStatus,
            l10n.youtubeScreening,
            '',
          ],
          cells: (context, row, reload) => [
            Text('${row['title'] ?? '—'}'),
            Text('${row['channel_title'] ?? '—'}'),
            StatusPill(
              label: '${row['status'] ?? '—'}',
              good: row['status'] == 'approved',
            ),
            Text(
              (row['screening_flags'] as List<dynamic>? ?? const []).join(', '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
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
