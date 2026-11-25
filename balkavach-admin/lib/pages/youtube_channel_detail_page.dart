import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api.dart';
import '../core/locale.dart';
import '../core/session.dart';
import '../l10n/app_localizations.dart';
import '../ui/widgets.dart';

const _ageBands = <String, String>{
  '3-5': '3-5 (early childhood)',
  '3-8': '3-8',
  '3-12': '3-12',
  '3-15': '3-15 (all supported ages)',
  '6-8': '6-8',
  '6-12': '6-12',
  '6-15': '6-15',
  '9-12': '9-12',
  '9-15': '9-15 (including 11-15 coverage)',
  '13-15': '13-15',
};

class YouTubeChannelDetailPage extends ConsumerStatefulWidget {
  const YouTubeChannelDetailPage({required this.channelId, super.key});

  final String channelId;

  @override
  ConsumerState<YouTubeChannelDetailPage> createState() =>
      _YouTubeChannelDetailPageState();
}

class _YouTubeChannelDetailPageState
    extends ConsumerState<YouTubeChannelDetailPage> {
  final TextEditingController _search = TextEditingController();
  late Future<Map<String, dynamic>> _detailFuture;
  late Future<List<Map<String, dynamic>>> _historyFuture;
  Future<Map<String, dynamic>>? _videosFuture;
  String _formatFilter = 'all';
  String _statusFilter = 'all';
  String _query = '';
  int _offset = 0;
  static const int _pageSize = 20;
  bool _discovering = false;
  bool _saving = false;

  String get _base =>
      '/api/v1/admin/videos/youtube/channels/${widget.channelId}';
  bool get _canWrite => ref.watch(sessionProvider)?.can('video:write') ?? false;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _loadAll({bool resetVideos = true}) {
    final api = ref.read(adminApiProvider);
    setState(() {
      _detailFuture = api.getMap(_base);
      _historyFuture = api.getList('$_base/discovery-history');
      if (resetVideos) {
        _offset = 0;
        _videosFuture = _fetchVideos();
      }
    });
  }

  Future<Map<String, dynamic>> _fetchVideos() {
    final query = <String, dynamic>{
      'limit': _pageSize,
      'offset': _offset,
      if (_formatFilter != 'all') 'format': _formatFilter,
      if (_statusFilter != 'all') 'status': _statusFilter,
      if (_query.trim().isNotEmpty) 'query': _query.trim(),
    };
    return ref.read(adminApiProvider).getMap('$_base/videos', query: query);
  }

  void _applyFilters() {
    setState(() {
      _query = _search.text.trim();
      _offset = 0;
      _videosFuture = _fetchVideos();
    });
  }

  String _when(Object? value) {
    final parsed = value is String ? DateTime.tryParse(value) : null;
    if (parsed == null) return 'â€”';
    final local = parsed.toLocal();
    return local.toString().split('.').first;
  }

  String _ageLabel(Object? min, Object? max) {
    if (min == null || max == null) return 'Not configured';
    return '$min-$max';
  }

  Future<Map<String, String>?> _activeVideoCategories() async {
    try {
      final rows = await ref
          .read(adminApiProvider)
          .getList('/api/v1/admin/videos/categories');
      if (!mounted) return null;
      final options = <String, String>{
        '': 'No category',
        for (final row in rows)
          if (row['is_active'] == true && row['id'] is String)
            row['id'] as String: '${row['name'] ?? ''}',
      };
      return options;
    } on Object catch (error) {
      if (mounted) showMessage(context, 'Could not load categories: $error');
      return null;
    }
  }

  Future<void> _editChannel(Map<String, dynamic> channel) async {
    if (!_canWrite || _saving) return;
    final categories = await _activeVideoCategories();
    if (categories == null || !mounted) return;
    final currentBand =
        (channel['age_min'] != null && channel['age_max'] != null)
        ? '${channel['age_min']}-${channel['age_max']}'
        : '3-15';
    final initialBand = _ageBands.containsKey(currentBand)
        ? currentBand
        : '3-15';
    final categoryId = channel['category_id'] as String?;
    final l10n = AppLocalizations.of(context);
    final values = await showFormDialog(
      context,
      title: l10n.youtubeEditTrustedChannel,
      fields: [
        FormFieldSpec(
          key: 'channel_title',
          label: l10n.youtubeChannelNameLabel,
          kind: FieldKind.text,
          initial: '${channel['channel_title'] ?? ''}',
          required: true,
        ),
        FormFieldSpec(
          key: 'age_band',
          label: l10n.youtubeAgeRangeLabel,
          kind: FieldKind.choice,
          required: true,
          options: _ageBands,
          initial: initialBand,
        ),
        FormFieldSpec(
          key: 'language_code',
          label: l10n.youtubeLanguageLabel,
          kind: FieldKind.choice,
          options: kLanguageNames,
          initial: '${channel['language_code'] ?? 'en'}',
        ),
        FormFieldSpec(
          key: 'category_id',
          label: l10n.youtubeCategoryLabel,
          kind: FieldKind.choice,
          options: categories,
          initial: categories.containsKey(categoryId) ? categoryId : '',
        ),
        FormFieldSpec(
          key: 'rights_status',
          label: l10n.youtubeRightsStatusLabel,
          kind: FieldKind.choice,
          options: const {
            'unknown': 'Unknown / unreviewed',
            'cleared': 'Cleared',
            'restricted': 'Restricted / not cleared',
          },
          initial: _uiRights(channel['rights_status']),
        ),
        FormFieldSpec(
          key: 'notes',
          label: l10n.youtubeNotesLabel,
          kind: FieldKind.multiline,
          initial: '${channel['notes'] ?? ''}',
          maxLength: 2000,
        ),
      ],
      submitLabel: l10n.actionSave,
    );
    if (values == null || !mounted) {
      return;
    }
    setState(() => _saving = true);
    try {
      final band = '${values.remove('age_band')}'.split('-');
      final payload = <String, dynamic>{
        ...values,
        'age_min': int.parse(band.first),
        'age_max': int.parse(band.last),
      };
      if (payload['category_id'] == '') payload['category_id'] = null;
      if (payload['language_code'] == '') payload['language_code'] = null;
      await ref.read(adminApiProvider).patch(_base, payload);
      if (!mounted) return;
      showMessage(context, 'Channel settings updated.');
      _loadAll(resetVideos: false);
    } on Object catch (error) {
      if (mounted) showMessage(context, 'Could not update channel: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _uiRights(Object? value) {
    return switch ('$value') {
      'cleared' => 'cleared',
      'restricted' || 'not_cleared' => 'restricted',
      _ => 'unknown',
    };
  }

  Future<void> _discoverMore(Map<String, dynamic> channel) async {
    if (!_canWrite || _discovering) return;
    final l10n = AppLocalizations.of(context);
    final name = '${channel['channel_title'] ?? widget.channelId}';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.youtubeDiscoverMore),
        content: Text(
          '$name — ${l10n.youtubeFetchingUploads}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.youtubeCancel),
          ),
          FilledButton(
            key: const Key('form.submit'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.youtubeDiscoverNow),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _discovering = true);
    try {
      final result = await ref
          .read(adminApiProvider)
          .post('$_base/discover', const {});
      if (!mounted) return;
      final scanned = result['scanned_videos'] ?? 0;
      final created = result['new_videos'] ?? result['created'] ?? 0;
      final duplicates =
          result['duplicate_videos'] ?? result['skipped_existing'] ?? 0;
      final shorts = result['shorts_count'] ?? 0;
      final longs = result['long_videos_count'] ?? 0;
      final autoApproved =
          result['auto_approved_count'] ??
          result['automatically_published'] ??
          0;
      final pending =
          result['pending_review_count'] ?? result['pending_review'] ?? 0;
      final quarantined =
          result['quarantined_count'] ?? result['quarantined'] ?? 0;
      final unavailable =
          result['unavailable_count'] ?? result['unavailable'] ?? 0;
      final errors = result['error_count'] ?? 0;
      showMessage(
        context,
        'Discovery finished for $name. Scanned $scanned, new $created, duplicates $duplicates, Shorts $shorts, long $longs, auto-approved $autoApproved, pending $pending, quarantined $quarantined, unavailable $unavailable, errors $errors.',
      );
      _loadAll();
    } on Object catch (error) {
      if (mounted) showMessage(context, 'Failed to discover more videos: $error');
      _loadAll(resetVideos: false);
    } finally {
      if (mounted) setState(() => _discovering = false);
    }
  }

  Widget _statCard(
    String label,
    Object? value, {
    IconData icon = Icons.insights_outlined,
  }) {
    return SizedBox(
      width: 190,
      child: StatCard(icon: icon, label: label, value: '${value ?? 0}'),
    );
  }

  Widget _overview(Map<String, dynamic> detail) {
    final l10n = AppLocalizations.of(context);
    final channel = (detail['channel'] as Map<String, dynamic>? ?? const {});
    final counts = (detail['counts'] as Map<String, dynamic>? ?? const {});
    final status = '${detail['status'] ?? channel['status'] ?? '—'}';
    final isActive = status == 'approved' || channel['is_active'] == true;
    return SectionCard(
      title: l10n.youtubeChannelOverview,
      trailing: _canWrite
          ? Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _saving ? null : () => _editChannel(channel),
                  icon: const Icon(Icons.edit_outlined),
                  label: Text(l10n.youtubeEditChannel),
                ),
                FilledButton.icon(
                  key: const Key('youtube.channelDiscoverMore'),
                  onPressed: _discovering ? null : () => _discoverMore(channel),
                  icon: _discovering
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.travel_explore_outlined),
                  label: Text(
                    _discovering
                        ? l10n.youtubeDiscovering
                        : l10n.youtubeDiscoverMore,
                  ),
                ),
              ],
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              CircleAvatar(
                radius: 28,
                backgroundImage: channel['thumbnail_url'] is String
                    ? NetworkImage(channel['thumbnail_url'] as String)
                    : null,
                child: channel['thumbnail_url'] is String
                    ? null
                    : const Icon(Icons.smart_display_outlined),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${channel['channel_title'] ?? widget.channelId}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  SelectableText(
                    'Channel ID: ${channel['channel_id'] ?? widget.channelId}',
                  ),
                  if (channel['thumbnail_url'] is String)
                    SelectableText(
                      'Channel URL: https://www.youtube.com/channel/${channel['channel_id'] ?? widget.channelId}',
                    ),
                ],
              ),
              StatusPill(
                label: isActive ? 'Trusted / active' : 'Removed / inactive',
                good: isActive,
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_discovering)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Discovery in progress for this channel only. Scanning uploads, skipping duplicates, and applying the normal screening/review pipelineâ€¦',
                    ),
                  ),
                ],
              ),
            ),
          Wrap(
            spacing: 24,
            runSpacing: 8,
            children: [
              _kv(
                'Configured age range',
                _ageLabel(channel['age_min'], channel['age_max']),
              ),
              _kv('Language', channel['language_code'] ?? 'â€”'),
              _kv('Rights status', channel['rights_status'] ?? 'â€”'),
              _kv(
                'Last discovery',
                _when(
                  channel['last_discovery_at'] ?? detail['last_discovered_at'],
                ),
              ),
              _kv('Last verified', _when(detail['last_verified_at'])),
              _kv('Category', channel['category_id'] ?? 'â€”'),
              _kv('Discovery status', _discovering ? 'Running' : 'Idle'),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Video statistics',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _statCard(
                'Total videos',
                counts['total_videos'] ?? counts['discovered'],
                icon: Icons.video_library_outlined,
              ),
              _statCard(
                'Shorts',
                counts['shorts_count'] ?? counts['published_shorts'],
                icon: Icons.movie_filter_outlined,
              ),
              _statCard(
                'Long videos',
                counts['long_videos_count'] ?? counts['published_regular'],
                icon: Icons.movie_outlined,
              ),
              _statCard(
                'Published',
                counts['published'],
                icon: Icons.check_circle_outline,
              ),
              _statCard(
                'Pending review',
                counts['pending_review'],
                icon: Icons.pending_actions_outlined,
              ),
              _statCard(
                'Quarantined',
                counts['quarantined'],
                icon: Icons.warning_amber_rounded,
              ),
              _statCard(
                'Unavailable',
                counts['unavailable'],
                icon: Icons.visibility_off_outlined,
              ),
              _statCard(
                'Rejected',
                counts['rejected'],
                icon: Icons.cancel_outlined,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _kv(String label, Object? value) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: RichText(
      text: TextSpan(
        style: Theme.of(context).textTheme.bodyMedium,
        children: [
          TextSpan(
            text: '$label: ',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          TextSpan(text: '${value ?? 'â€”'}'),
        ],
      ),
    ),
  );

  Widget _videosSection() {
    final l10n = AppLocalizations.of(context);
    return SectionCard(
      title: l10n.youtubeVideosFromChannel,
      trailing: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 260,
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                hintText: l10n.youtubeSearchTitleOrId,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: _applyFilters,
                ),
              ),
              onSubmitted: (_) => _applyFilters(),
            ),
          ),
          DropdownButton<String>(
            value: _formatFilter,
            items: [
              DropdownMenuItem(value: 'all', child: Text(l10n.youtubeAllFormats)),
              DropdownMenuItem(value: 'short', child: Text(l10n.youtubeShortsOnly)),
              DropdownMenuItem(value: 'long', child: Text(l10n.youtubeLongOnly)),
            ],
            onChanged: (v) {
              if (v == null) return;
              setState(() {
                _formatFilter = v;
                _offset = 0;
                _videosFuture = _fetchVideos();
              });
            },
          ),
          DropdownButton<String>(
            value: _statusFilter,
            items: [
              DropdownMenuItem(value: 'all', child: Text(l10n.youtubeAll)),
              DropdownMenuItem(value: 'published', child: Text(l10n.youtubePublished)),
              DropdownMenuItem(
                value: 'pending_review',
                child: Text(l10n.youtubePendingReview),
              ),
              DropdownMenuItem(value: 'approved', child: Text(l10n.youtubeApproved)),
              DropdownMenuItem(
                value: 'quarantined',
                child: Text(l10n.youtubeQuarantined),
              ),
              DropdownMenuItem(
                value: 'unavailable',
                child: Text(l10n.youtubeUnavailable),
              ),
              DropdownMenuItem(value: 'rejected', child: Text(l10n.youtubeRejected)),
            ],
            onChanged: (v) {
              if (v == null) return;
              setState(() {
                _statusFilter = v;
                _offset = 0;
                _videosFuture = _fetchVideos();
              });
            },
          ),
          IconButton(
            onPressed: () => _loadAll(resetVideos: true),
            icon: const Icon(Icons.refresh),
            tooltip: l10n.youtubeRefresh,
          ),
        ],
      ),
      child: AsyncBody<Map<String, dynamic>>(
        future: _videosFuture ?? Future.value(const {'items': [], 'total': 0}),
        onRetry: () => _applyFilters(),
        builder: (context, data) {
          final items = (data['items'] as List<dynamic>? ?? const [])
              .cast<Map<String, dynamic>>();
          final total = (data['total'] as num?)?.toInt() ?? items.length;
          if (items.isEmpty) {
            return EmptyState(
              message: l10n.youtubeNoChannelVideos,
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Showing ${_offset + 1}â€“${_offset + items.length} of $total (newest first)',
              ),
              const SizedBox(height: 8),
              for (final item in items)
                Card(
                  child: ListTile(
                    leading: item['thumbnail_url'] is String
                        ? Image.network(
                            item['thumbnail_url'] as String,
                            width: 72,
                            height: 48,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) =>
                                const SizedBox(width: 72, height: 48),
                          )
                        : const SizedBox(
                            width: 72,
                            height: 48,
                            child: Icon(Icons.smart_display_outlined),
                          ),
                    title: Text(
                      '${item['title'] ?? item['youtube_video_id'] ?? 'â€”'}',
                    ),
                    subtitle: SelectableText(
                      'ID: ${item['youtube_video_id'] ?? 'â€”'} Â· ${item['video_format'] == 'short' ? 'Short' : 'Long'}'
                      ' Â· ${item['duration_seconds'] != null ? '${item['duration_seconds']}s' : 'duration ?'}'
                      ' Â· Topic: ${item['discovery_topic'] ?? 'â€”'} Â· Category: ${item['category_name'] ?? item['category_id'] ?? 'â€”'}'
                      ' Â· Age: ${_ageLabel(item['age_min'], item['age_max'])}'
                      ' Â· Status: ${item['review_status'] ?? 'â€”'} Â· Publication: ${item['publication_status'] ?? 'â€”'}'
                      ' Â· Discovered: ${_when(item['discovered_at'])}',
                    ),
                    isThreeLine: true,
                    trailing: item['video_format'] == 'short'
                        ? Chip(label: Text(l10n.youtubeFormatShort))
                        : Chip(label: Text(l10n.youtubeFormatLong)),
                  ),
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  OutlinedButton(
                    onPressed: _offset <= 0
                        ? null
                        : () {
                            setState(() {
                              _offset = (_offset - _pageSize).clamp(0, total);
                              _videosFuture = _fetchVideos();
                            });
                          },
                    child: Text(l10n.youtubePrevious),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: (_offset + _pageSize >= total)
                        ? null
                        : () {
                            setState(() {
                              _offset += _pageSize;
                              _videosFuture = _fetchVideos();
                            });
                          },
                    child: Text(l10n.youtubeNext),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _historySection() {
    final l10n = AppLocalizations.of(context);
    return SectionCard(
      title: l10n.youtubeDiscoveryHistory,
      child: AsyncBody<List<Map<String, dynamic>>>(
        future: _historyFuture,
        onRetry: () => _loadAll(resetVideos: false),
        builder: (context, runs) {
          if (runs.isEmpty) {
            return EmptyState(
              message: l10n.youtubeNoDiscoveryRuns,
            );
          }
          return Column(
            children: [
              for (final run in runs)
                ListTile(
                  leading: Icon(
                    run['status'] == 'completed'
                        ? Icons.check_circle_outline
                        : run['status'] == 'running'
                        ? Icons.sync
                        : Icons.error_outline,
                  ),
                  title: Text(
                    l10n.youtubeDiscoveryRunTitle(
                      '${run['id'] ?? '—'}',
                      '${run['trigger'] ?? 'manual'}',
                      '${run['status'] ?? '—'}',
                      _when(run['started_at']),
                    ),
                  ),
                  subtitle: Text(
                    '${l10n.youtubeDiscoveryRunSummary(
                      (run['scanned_videos'] as num?)?.toInt() ?? 0,
                      (run['new_videos'] as num?)?.toInt() ?? 0,
                      (run['duplicate_videos'] as num?)?.toInt() ?? 0,
                      (run['shorts_count'] as num?)?.toInt() ?? 0,
                      (run['long_videos_count'] as num?)?.toInt() ?? 0,
                      (run['auto_approved_count'] as num?)?.toInt() ?? 0,
                      (run['pending_review_count'] as num?)?.toInt() ?? 0,
                      (run['quarantined_count'] as num?)?.toInt() ?? 0,
                      (run['unavailable_count'] as num?)?.toInt() ?? 0,
                      (run['error_count'] as num?)?.toInt() ?? 0,
                    )}${run['error_message'] != null ? '\n${run['error_message']}' : ''}',
                  ),
                  isThreeLine: run['error_message'] != null,
                ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AsyncBody<Map<String, dynamic>>(
      future: _detailFuture,
      onRetry: () => _loadAll(),
      builder: (context, detail) {
        return ListView(
          children: [
            PageHeader(
              title: l10n.youtubeChannelDetailsTitle,
              subtitle: l10n.youtubeChannelDetailsSubtitle,
              actions: [
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back),
                  label: Text(l10n.youtubeBack),
                ),
              ],
            ),
            _overview(detail),
            _videosSection(),
            _historySection(),
            if (_saving || _discovering)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: LinearProgressIndicator(),
              ),
          ],
        );
      },
    );
  }
}
