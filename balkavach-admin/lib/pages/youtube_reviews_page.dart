import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api.dart';
import '../core/locale.dart';
import '../core/session.dart';
import '../l10n/app_localizations.dart';
import '../ui/widgets.dart';

const _ageBands = {
  '3-5': '3-5',
  '3-8': '3-8 (3-5 + 6-8)',
  '3-12': '3-12 (3-5 + 6-8 + 9-12)',
  '3-15': '3-15 (all age groups)',
  '6-8': '6-8',
  '6-12': '6-12 (6-8 + 9-12)',
  '6-15': '6-15 (6-8 + 9-12 + 13-15)',
  '9-12': '9-12',
  '9-15': '9-15 (9-12 + 13-15)',
  '13-15': '13-15',
};

class YouTubeReviewsPage extends C  onsumerStatefulWidget {
  const YouTubeReviewsPage({super.key});

  @override
  ConsumerState<YouTubeReviewsPage> createState() => _YouTubeReviewsPageState();
}

class _YouTubeReviewsPageState extends ConsumerState<YouTubeReviewsPage> {
  final TextEditingController _channelSearch = TextEditingController();
  List<Map<String, dynamic>> _channelResults = const [];
  List<Map<String, dynamic>> _trustedChannels = const [];

  /// `all`, `trusted` or `notTrusted`: filters the list on this device only.
  String _channelFilter = 'all';
  bool _searching = false;
  bool _loadingChannels = false;
  bool _actionRunning = false;
  String _reviewStatus = 'pending_review';
  int _reload = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refreshTrustedChannels();
    });
  }

  @override
  void dispose() {
    _channelSearch.dispose();
    super.dispose();
  }

  bool get _canWrite => ref.watch(sessionProvider)?.can('video:write') ?? false;

  void _reloadAll() {
    setState(() => _reload++);
    _refreshTrustedChannels();
  }

  Future<void> _refreshTrustedChannels() async {
    setState(() => _loadingChannels = true);
    try {
      final api = ref.read(adminApiProvider);
      final channels = <Map<String, dynamic>>[];
      var offset = 0;
      while (true) {
        final page = await api.getList(
          '/api/v1/admin/videos/youtube/channels',
          query: {'limit': 100, 'offset': offset},
        );
        channels.addAll(page);
        if (page.length < 100) break;
        offset += page.length;
      }
      if (mounted) setState(() => _trustedChannels = channels);
    } on Object catch (error) {
      if (mounted) showMessage(context, '$error');
    } finally {
      if (mounted) setState(() => _loadingChannels = false);
    }
  }

  Future<void> _searchChannels() async {
    final query = _channelSearch.text.trim();
    if (query.length < 2 || _searching) return;
    setState(() => _searching = true);
    try {
      final channels = await ref
          .read(adminApiProvider)
          .getList(
            '/api/v1/admin/videos/youtube/channels/discover',
            query: {'query': query, 'max_results': 10},
          );
      if (mounted) setState(() => _channelResults = channels);
    } on Object catch (error) {
      if (mounted) {
        setState(() => _channelResults = const []);
        showMessage(context, '$error');
      }
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<Map<String, String>?> _activeVideoCategories() async {
    final l10n = AppLocalizations.of(context);
    try {
      final rows = await ref
          .read(adminApiProvider)
          .getList('/api/v1/admin/videos/categories');
      if (!mounted) return null;
      final options = {
        for (final row in rows)
          if (row['is_active'] == true && row['id'] is String)
            row['id'] as String: '${row['name'] ?? ''}',
      };
      if (options.isNotEmpty) return options;
      showMessage(context, l10n.youtubeCategoriesRequired);
    } on Object catch (error) {
      if (mounted) {
        showMessage(context, '${l10n.youtubeCategoriesRequired}: $error');
      }
    }
    return null;
  }

  Future<void> _trustChannel(Map<String, dynamic> channel) async {
    if (!_canWrite || _actionRunning) return;
    final l10n = AppLocalizations.of(context);
    final categories = await _activeVideoCategories();
    if (categories == null || !mounted) return;
    final existingAge =
        (channel['age_min'] != null && channel['age_max'] != null)
        ? '${channel['age_min']}-${channel['age_max']}'
        : '3-15';
    final initialBand = _ageBands.containsKey(existingAge)
        ? existingAge
        : '3-15';
    final values = await showFormDialog(
      context,
      title: 'Trust / configure channel',
      fields: [
        FormFieldSpec(
          key: 'age_band',
          label: l10n.youtubeAgeBand,
          kind: FieldKind.choice,
          required: true,
          options: _ageBands,
          initial: initialBand,
        ),
        FormFieldSpec(
          key: 'language_code',
          label: l10n.fieldLanguage,
          kind: FieldKind.choice,
          options: kLanguageNames,
          initial: '${channel['language_code'] ?? 'en'}',
        ),
        FormFieldSpec(
          key: 'category_id',
          label: l10n.youtubeVideoCategory,
          kind: FieldKind.choice,
          options: categories,
          initial: categories.keys.first,
        ),
        FormFieldSpec(
          key: 'rights_cleared',
          label: l10n.youtubeRightsCleared,
          kind: FieldKind.toggle,
          initial: false,
        ),
        FormFieldSpec(
          key: 'notes',
          label: 'Notes',
          kind: FieldKind.multiline,
          initial: '${channel['notes'] ?? ''}',
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
    final band = '${values.remove('age_band')}'.split('-');
    final payload = <String, dynamic>{
      'channel_id': channel['channel_id'],
      'channel_title': channel['channel_title'],
      'thumbnail_url': channel['thumbnail_url'],
      'age_min': int.parse(band.first),
      'age_max': int.parse(band.last),
      'language_code': values['language_code'],
      'category_id': values['category_id'] == '' ? null : values['category_id'],
      'rights_status': 'cleared',
      'notes': values['notes'],
    };
    setState(() => _actionRunning = true);
    try {
      final result = await ref
          .read(adminApiProvider)
          .post('/api/v1/admin/videos/youtube/channels/trust', payload);
      if (!mounted) return;
      final discovery =
          result['initial_discovery'] as Map<String, dynamic>? ??
          const <String, dynamic>{};
      final count =
          (discovery['created'] as num?)?.toInt() ??
          (discovery['new_videos'] as num?)?.toInt() ??
          0;
      showMessage(
        context,
        'Channel trusted/configured. $count new videos discovered.',
      );
      _reloadAll();
    } on Object catch (error) {
      if (mounted) showMessage(context, '$error');
    } finally {
      if (mounted) setState(() => _actionRunning = false);
    }
  }

  String _when(Object? value) {
    final parsed = value is String ? DateTime.tryParse(value) : null;
    return parsed == null
        ? 'Ã¢â‚¬â€'
        : parsed.toLocal().toString().split('.').first;
  }

  Future<void> _untrustChannel(Map<String, dynamic> channel) async {
    if (!_canWrite || _actionRunning) return;
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.youtubeUntrustChannel),
        content: Text(l10n.youtubeUntrustConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(
              MaterialLocalizations.of(dialogContext).cancelButtonLabel,
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.youtubeUntrustChannel),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _actionRunning = true);
    try {
      await ref
          .read(adminApiProvider)
          .post(
            '/api/v1/admin/videos/youtube/channels/${channel['channel_id']}/untrust',
            const {},
          );
      if (mounted) _reloadAll();
    } on Object catch (error) {
      if (mounted) showMessage(context, '$error');
    } finally {
      if (mounted) setState(() => _actionRunning = false);
    }
  }

  Future<void> _approve(
    Map<String, dynamic> row,
    BuildContext dialogContext,
  ) async {
    final l10n = AppLocalizations.of(context);
    final categories = await _activeVideoCategories();
    if (categories == null || !mounted) return;
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
          key: 'category_id',
          label: l10n.youtubeVideoCategory,
          kind: FieldKind.choice,
          required: true,
          options: categories,
          initial: categories.keys.first,
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

  Future<void> _inspect(Map<String, dynamic> row) async {
    final l10n = AppLocalizations.of(context);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${row['title'] ?? l10n.youtubeReviewDetails}'),
        content: SizedBox(
          width: 520,
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
                _metadata('Channel', row['channel_title']),
                _metadata('Status', row['status']),
                _metadata('Rights', row['rights_status']),
                if ((row['screening_flags'] as List<dynamic>? ?? const [])
                    .isNotEmpty)
                  _metadata(
                    l10n.youtubeScreening,
                    (row['screening_flags'] as List<dynamic>).join(', '),
                  ),
                if (row['not_published_reason'] != null)
                  _metadata('Reason', row['not_published_reason']),
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
          if (_canWrite && row['status'] == 'pending_review') ...[
            TextButton(
              onPressed: () => _reject(row, dialogContext),
              child: Text(l10n.youtubeActionReject),
            ),
            FilledButton(
              onPressed: () => _approve(row, dialogContext),
              child: Text(l10n.youtubeActionApprove),
            ),
          ],
          if (_canWrite && row['status'] == 'quarantined')
            FilledButton.icon(
              key: Key('youtube.reevaluate.${row['id']}'),
              onPressed: () => _reevaluate(row, dialogContext),
              icon: const Icon(Icons.fact_check_outlined),
              label: Text(l10n.youtubeReevaluate),
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
    child: SelectableText('$label: ${value ?? 'Ã¢â‚¬â€'}'),
  );

  Widget _channelAvatar(Object? value, {double radius = 24}) {
    final url = value is String ? Uri.tryParse(value) : null;
    final safeUrl = url != null && url.scheme == 'https'
        ? value as String
        : null;
    return CircleAvatar(
      radius: radius,
      child: safeUrl == null
          ? const Icon(Icons.smart_display_outlined)
          : ClipOval(
              child: Image.network(
                safeUrl,
                width: radius * 2,
                height: radius * 2,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    const Icon(Icons.smart_display_outlined),
              ),
            ),
    );
  }

  Widget _channelSearchSection(AppLocalizations l10n) => SectionCard(
    title: l10n.youtubeDiscoverChannels,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('youtube.channelSearch'),
          controller: _channelSearch,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _searchChannels(),
          decoration: InputDecoration(
            hintText: l10n.youtubeChannelSearchHint,
            prefixIcon: const Icon(Icons.search),
            suffixIcon: IconButton(
              key: const Key('youtube.searchChannels'),
              tooltip: l10n.youtubeDiscoverChannels,
              onPressed: _searching ? null : _searchChannels,
              icon: _searching
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.arrow_forward),
            ),
          ),
        ),
        if (_channelResults.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final channel in _channelResults)
            ListTile(
              key: Key('youtube.searchResult.${channel['channel_id']}'),
              contentPadding: EdgeInsets.zero,
              leading: _channelAvatar(channel['thumbnail_url']),
              title: Text(
                channel['channel_title'] as String? ?? 'YouTube channel',
              ),
              subtitle: SelectableText('${channel['channel_id'] ?? ''}'),
              trailing: channel['is_trusted'] == true
                  ? StatusPill(label: l10n.youtubeChannelTrusted, good: true)
                  : _canWrite
                  ? OutlinedButton(
                      key: Key('youtube.trust.${channel['channel_id']}'),
                      onPressed: _actionRunning
                          ? null
                          : () => _trustChannel(channel),
                      child: Text(l10n.youtubeTrustChannel),
                    )
                  : null,
            ),
        ] else if (!_searching && _channelSearch.text.trim().length >= 2)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(l10n.youtubeNoChannelsFound),
          ),
      ],
    ),
  );

  Widget _trustedChannelsSection(AppLocalizations l10n) => SectionCard(
    title: l10n.youtubeTrustedChannels,
    trailing: IconButton(
      key: const Key('youtube.refreshChannels'),
      tooltip: MaterialLocalizations.of(context).refreshIndicatorSemanticLabel,
      onPressed: _loadingChannels ? null : _refreshTrustedChannels,
      icon: const Icon(Icons.refresh),
    ),
    child: _loadingChannels
        ? const LinearProgressIndicator()
        : _trustedChannels.isEmpty
        ? Text(l10n.youtubeNoTrustedChannels)
        : Column(
            children: [
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Wrap(
                  spacing: 8,
                  children: [
                    for (final (value, label) in [
                      ('all', l10n.youtubeChannelAll),
                      ('trusted', l10n.youtubeChannelActive),
                      ('notTrusted', l10n.youtubeChannelRemoved),
                    ])
                      ChoiceChip(
                        key: Key('youtube.channelFilter.$value'),
                        label: Text(label),
                        selected: _channelFilter == value,
                        onSelected: (_) =>
                            setState(() => _channelFilter = value),
                      ),
                  ],
                ),
              ),
              for (final channel in _trustedChannels.where(
                (c) => switch (_channelFilter) {
                  'trusted' => c['is_active'] == true,
                  'notTrusted' => c['is_active'] != true,
                  _ => true,
                },
              ))
                Card(
                  key: Key('youtube.channelRow.${channel['channel_id']}'),
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  child: ListTile(
                    onTap: () => context.go(
                      '/youtube-reviews/channels/${channel['channel_id']}',
                    ),
                    leading: _channelAvatar(channel['thumbnail_url']),
                    title: Text(
                      channel['channel_title'] as String? ?? 'YouTube channel',
                    ),
                    subtitle: Text(
                      'ID: ${channel['channel_id'] ?? 'Ã¢â‚¬â€'} Ã‚Â· Age: ${channel['age_min'] ?? 'Ã¢â‚¬â€'}-${channel['age_max'] ?? 'Ã¢â‚¬â€'} Ã‚Â· '
                      'Total: ${channel['total_videos'] ?? 'Ã¢â‚¬â€'} Ã‚Â· Shorts: ${channel['shorts_count'] ?? 'Ã¢â‚¬â€'} Ã‚Â· '
                      'Long: ${channel['long_videos_count'] ?? 'Ã¢â‚¬â€'} Ã‚Â· Last discovery: ${_when(channel['last_discovery_at'])}',
                    ),
                    isThreeLine: true,
                    trailing: Wrap(
                      spacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        StatusPill(
                          label: channel['is_active'] == true
                              ? l10n.youtubeChannelTrusted
                              : l10n.youtubeChannelNotTrusted,
                          good: channel['is_active'] == true,
                        ),
                        OutlinedButton.icon(
                          key: Key(
                            'youtube.viewDetails.${channel['channel_id']}',
                          ),
                          onPressed: () => context.go(
                            '/youtube-reviews/channels/${channel['channel_id']}',
                          ),
                          icon: const Icon(Icons.open_in_new),
                          label: const Text('View Details'),
                        ),
                        if (_canWrite)
                          IconButton(
                            key: Key(
                              'youtube.untrust.${channel['channel_id']}',
                            ),
                            tooltip: channel['is_active'] == true
                                ? l10n.youtubeUntrustChannel
                                : l10n.youtubeTrustChannel,
                            onPressed: _actionRunning
                                ? null
                                : () => channel['is_active'] == true
                                      ? _untrustChannel(channel)
                                      : _trustChannel(channel),
                            icon: Icon(
                              channel['is_active'] == true
                                  ? Icons.link_off
                                  : Icons.link,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
  );

  Widget _reviewSection(AppLocalizations l10n) => SectionCard(
    title: l10n.youtubeReviewQueue,
    trailing: SizedBox(
      width: 190,
      child: DropdownButtonFormField<String>(
        key: const Key('youtube.status'),
        initialValue: _reviewStatus,
        isExpanded: true,
        decoration: InputDecoration(labelText: l10n.youtubeStatus),
        items: [
          DropdownMenuItem(
            value: 'pending_review',
            child: Text(l10n.youtubeCountPending),
          ),
          DropdownMenuItem(
            value: 'quarantined',
            child: Text(l10n.youtubeCountQuarantined),
          ),
          DropdownMenuItem(value: 'all', child: Text(l10n.youtubeAll)),
        ],
        onChanged: (value) {
          if (value != null) setState(() => _reviewStatus = value);
        },
      ),
    ),
    child: PagedTable(
      key: const Key('youtube.reviews'),
      compactWidth: 1100,
      reloadKey: _reload,
      emptyMessage: l10n.youtubeNoReviewVideos,
      fetch: (offset, limit) => ref
          .read(adminApiProvider)
          .getList(
            '/api/v1/admin/videos/youtube/reviews',
            query: {
              if (_reviewStatus != 'all') 'status': _reviewStatus,
              'limit': limit,
              'offset': offset,
            },
          ),
      columns: [
        '',
        l10n.fieldTitle,
        'Channel',
        l10n.youtubeStatus,
        'Reason',
        '',
      ],
      cells: (context, row, reload) {
        final flags = (row['screening_flags'] as List<dynamic>? ?? const [])
            .join(', ');
        final reason = row['not_published_reason'] as String?;
        return [
          row['thumbnail_url'] is String
              ? Image.network(
                  row['thumbnail_url'] as String,
                  width: 64,
                  height: 44,
                  fit: BoxFit.cover,
                )
              : const SizedBox(width: 64, height: 44),
          Text('${row['title'] ?? 'Ã¢â‚¬â€'}'),
          Text('${row['channel_title'] ?? 'Ã¢â‚¬â€'}'),
          StatusPill(
            label: '${row['status'] ?? 'Ã¢â‚¬â€'}',
            good: row['status'] == 'approved',
          ),
          Text(
            reason?.isNotEmpty == true ? reason! : flags,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          TextButton(
            key: Key('youtube.inspect.${row['id']}'),
            onPressed: () => _inspect(row),
            child: Text(l10n.youtubeActionOpen),
          ),
        ];
      },
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListView(
      children: [
        PageHeader(
          title: l10n.youtubeReviewsTitle,
          subtitle: l10n.youtubeReviewsSubtitle,
        ),
        _channelSearchSection(l10n),
        _trustedChannelsSection(l10n),
        _reviewSection(l10n),
        if (_actionRunning) const LinearProgressIndicator(),
      ],
    );
  }
}
