import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/buttons.dart';
import '../../../shared/widgets/state_views.dart';
import '../../learning/data/video_feed_repository.dart';
import '../data/family_repository.dart';

/// Parent view & approval for child video interests (DEC-04).
class ParentChildInterestsCard extends ConsumerStatefulWidget {
  const ParentChildInterestsCard({
    required this.familyId,
    required this.childId,
    super.key,
  });

  final String familyId;
  final String childId;

  @override
  ConsumerState<ParentChildInterestsCard> createState() =>
      _ParentChildInterestsCardState();
}

class _ParentChildInterestsCardState
    extends ConsumerState<ParentChildInterestsCard> {
  /// The last server-confirmed state for [_ParentChildInterestsCardState._owner].
  ChildInterests? _data;
  Set<String> _selected = {};
  Object? _error;
  bool _loading = true;
  bool _saving = false;

  /// Which family/child the state above belongs to. A response for any other
  /// child (the widget was reused for a sibling) is dropped.
  late String _owner = _ownerKey;

  String get _ownerKey => '${widget.familyId}/${widget.childId}';

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant ParentChildInterestsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.familyId != widget.familyId ||
        oldWidget.childId != widget.childId) {
      // Never show (or save) one child's topics on another child's profile.
      _owner = _ownerKey;
      _data = null;
      _selected = {};
      _error = null;
      _saving = false;
      unawaited(_load());
    }
  }

  bool get _dirty {
    final data = _data;
    if (data == null) return false;
    final saved = data.interests.toSet();
    return saved.length != _selected.length || !saved.containsAll(_selected);
  }

  Future<void> _load() async {
    final owner = _ownerKey;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ref
          .read(familyRepositoryProvider)
          .getChildInterests(widget.familyId, widget.childId);
      if (!mounted || owner != _owner) return;
      setState(() {
        _data = data;
        _selected = data.interests.toSet();
        _loading = false;
      });
    } on Object catch (e) {
      if (!mounted || owner != _owner) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  /// Sends [interests] as the child's approved topics. The UI changes only
  /// after the server confirms; on failure the parent's selection is kept.
  Future<void> _save({
    required List<String> interests,
    required bool clearPending,
  }) async {
    if (_saving) return; // one request at a time
    final owner = _ownerKey;
    setState(() => _saving = true);
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final updated = await ref
          .read(familyRepositoryProvider)
          .updateChildInterests(
            widget.familyId,
            widget.childId,
            interests,
            clearPending: clearPending,
          );
      if (!mounted || owner != _owner) return;
      setState(() {
        _data = updated;
        _selected = updated.interests.toSet();
        _saving = false;
      });
      messenger.showSnackBar(SnackBar(content: Text(l10n.interestsSaved)));
    } on Object catch (e) {
      if (!mounted || owner != _owner) return;
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text(_errorText(l10n, e))));
    }
  }

  /// 404 from these routes means the child is not in this parent's family
  /// (the server checks membership); 503 means the server lacks the columns.
  String _errorText(AppLocalizations l10n, Object error) => switch (error) {
    NotFoundException() => l10n.interestsChildNotLinked,
    ServerException(statusCode: 503) => l10n.interestsUnavailable,
    _ => describeError(l10n, error),
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final muted = context.text.bodySmall?.copyWith(
      color: context.colors.onSurfaceVariant,
    );
    return AppCard(
      key: const Key('parent.interests.card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.sm,
        children: [
          SectionHeader(title: l10n.interestsTitle),
          Text(l10n.interestsParentSubtitle, style: muted),
          if (_loading && _data == null)
            const LinearProgressIndicator(key: Key('parent.interests.loading'))
          else if (_data == null)
            ErrorView(
              key: const Key('parent.interests.error'),
              error: _error ?? const UnknownApiException(message: 'No data'),
              message: _error == null ? null : _errorText(l10n, _error!),
              onRetry: _load,
            )
          else if (_data!.availableCategories.isEmpty)
            Text(l10n.interestsEmpty, key: const Key('parent.interests.empty'))
          else ...[
            Text(
              l10n.interestsParentActiveTitle,
              style: context.text.titleSmall,
            ),
            if (_data!.interests.isEmpty)
              Text(
                l10n.interestsActiveNone,
                key: const Key('parent.interests.activeNone'),
                style: muted,
              )
            else
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  for (final slug in _data!.interests)
                    Chip(
                      key: Key('parent.interests.active.$slug'),
                      label: Text(_nameFor(slug)),
                    ),
                ],
              ),
            if (_data!.pendingRequests.isNotEmpty)
              Container(
                key: const Key('parent.interests.pending'),
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: context.colors.secondaryContainer,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: AppSpacing.xs,
                  children: [
                    Text(
                      l10n.interestsPendingTitle,
                      style: context.text.titleSmall,
                    ),
                    Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xs,
                      children: [
                        for (final slug in _data!.pendingRequests)
                          Chip(
                            key: Key('parent.interests.pendingItem.$slug'),
                            label: Text(_nameFor(slug)),
                          ),
                      ],
                    ),
                    Text(l10n.interestsApproveHint, style: muted),
                    Wrap(
                      spacing: AppSpacing.sm,
                      children: [
                        // The child's request is the full set of topics they
                        // want (their picker starts from the approved ones),
                        // so approving replaces the approved set with it.
                        FilledButton(
                          key: const Key('parent.interests.approve'),
                          onPressed: _saving
                              ? null
                              : () => _save(
                                  interests: _data!.pendingRequests,
                                  clearPending: true,
                                ),
                          child: Text(l10n.interestsApproveAll),
                        ),
                        // Dismissing keeps the server's approved topics; it
                        // never saves unsaved chip edits behind the parent's
                        // back.
                        TextButton(
                          key: const Key('parent.interests.reject'),
                          onPressed: _saving
                              ? null
                              : () => _save(
                                  interests: _data!.interests,
                                  clearPending: true,
                                ),
                          child: Text(l10n.interestsRejectAll),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            Text(
              l10n.interestsParentChooseTitle,
              style: context.text.titleSmall,
            ),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final cat in _data!.availableCategories)
                  FilterChip(
                    key: Key('parent.interest.${cat.slug}'),
                    label: Text(cat.name),
                    selected: _selected.contains(cat.slug),
                    onSelected: _saving
                        ? null
                        : (v) => setState(() {
                            if (v) {
                              _selected.add(cat.slug);
                            } else {
                              _selected.remove(cat.slug);
                            }
                          }),
                  ),
              ],
            ),
            // Saving the parent's own choice leaves a child request waiting.
            PrimaryButton(
              key: const Key('parent.interests.save'),
              label: l10n.interestsSave,
              loading: _saving,
              onPressed: _dirty
                  ? () => _save(
                      interests: _selected.toList(),
                      clearPending: false,
                    )
                  : null,
            ),
          ],
        ],
      ),
    );
  }

  String _nameFor(String slug) {
    final cats = _data?.availableCategories ?? const <InterestCategoryOption>[];
    for (final cat in cats) {
      if (cat.slug == slug) return cat.name;
    }
    return slug;
  }
}

/// Parent link-code / QR generator card (DEC-05).
class ParentChildLinkCard extends ConsumerStatefulWidget {
  const ParentChildLinkCard({
    required this.familyId,
    required this.childId,
    super.key,
  });

  final String familyId;
  final String childId;

  @override
  ConsumerState<ParentChildLinkCard> createState() =>
      _ParentChildLinkCardState();
}

class _ParentChildLinkCardState extends ConsumerState<ParentChildLinkCard> {
  ChildLinkCode? _code;
  bool _loading = false;
  Object? _error;
  Timer? _timer;
  Duration _remaining = Duration.zero;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _generate() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(familyRepositoryProvider)
          .createChildLinkCode(widget.familyId, widget.childId);
      if (!mounted) return;
      _timer?.cancel();
      setState(() {
        _code = result;
        _loading = false;
        _remaining = result.expiresAt.difference(DateTime.now().toUtc());
      });
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || _code == null) return;
        final diff = _code!.expiresAt.difference(DateTime.now().toUtc());
        setState(() => _remaining = diff.isNegative ? Duration.zero : diff);
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final code = _code;
    return AppCard(
      key: const Key('parent.link.card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.sm,
        children: [
          SectionHeader(title: l10n.childLinkTitle),
          Text(
            l10n.childLinkSubtitle,
            style: context.text.bodySmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
          if (_error != null)
            InlineNotice(
              icon: Icons.error_outline_rounded,
              message: describeError(l10n, _error!),
            ),
          if (code != null) ...[
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: context.colors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Column(
                spacing: AppSpacing.xs,
                children: [
                  const Icon(Icons.qr_code_2_rounded, size: 72),
                  SelectableText(
                    code.code,
                    key: const Key('parent.link.code'),
                    style: context.text.headlineMedium?.copyWith(
                      letterSpacing: 3,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SelectableText(
                    code.qrPayload,
                    style: context.text.bodySmall?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    _remaining <= Duration.zero
                        ? l10n.childLinkExpired
                        : l10n.childLinkExpires(
                            _remaining.inMinutes,
                            _remaining.inSeconds % 60,
                          ),
                    style: context.text.labelMedium?.copyWith(
                      color: _remaining <= Duration.zero
                          ? context.colors.error
                          : context.colors.primary,
                    ),
                  ),
                  OutlinedButton.icon(
                    key: const Key('parent.link.copy'),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: code.code));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l10n.childLinkCopied)),
                      );
                    },
                    icon: const Icon(Icons.copy_rounded),
                    label: Text(l10n.childLinkCopy),
                  ),
                ],
              ),
            ),
          ],
          SecondaryButton(
            key: const Key('parent.link.generate'),
            label: l10n.childLinkGenerate,
            icon: Icons.qr_code_rounded,
            onPressed: _loading ? null : _generate,
          ),
        ],
      ),
    );
  }
}

/// Child-side interests viewer & change-request card (DEC-04).
///
/// Shows the parent-approved active topics, any requests still waiting for a
/// parent, and lets the child ask for changes. A request never changes the
/// active topics: only a parent's approval does (server-enforced).
class ChildInterestsCard extends ConsumerStatefulWidget {
  const ChildInterestsCard({super.key});

  @override
  ConsumerState<ChildInterestsCard> createState() => _ChildInterestsCardState();
}

class _ChildInterestsCardState extends ConsumerState<ChildInterestsCard> {
  /// The last successful server answer.
  ChildInterests? _data;
  Set<String> _requested = {};

  /// The child changed the selection since the last server answer; a refresh
  /// must not overwrite what they picked.
  bool _edited = false;
  bool _loading = true;
  bool _sending = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  void _apply(ChildInterests parsed) {
    _data = parsed;
    if (!_edited) {
      _requested = parsed.pendingRequests.isNotEmpty
          ? parsed.pendingRequests.toSet()
          : parsed.interests.toSet();
    }
  }

  /// Every call is a fresh request with the current session's token.
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final json = await ref.read(videoFeedRepositoryProvider).getMyInterests();
      if (!mounted) return;
      final parsed = ChildInterests.fromJson(json);
      setState(() {
        _apply(parsed);
        _loading = false;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _submitRequest() async {
    // One request at a time; an empty request would leave the parent nothing
    // to review (the server refuses it with 422).
    if (_sending || _requested.isEmpty) return;
    setState(() => _sending = true);
    final l10n = AppLocalizations.of(context);
    try {
      final json = await ref
          .read(videoFeedRepositoryProvider)
          .requestInterests(_requested.toList());
      if (!mounted) return;
      final parsed = ChildInterests.fromJson(json);
      setState(() {
        _edited = false;
        _apply(parsed);
        _sending = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.interestsRequestSent)));
    } on Object catch (e) {
      if (!mounted) return;
      // The child's selection stays as it was, so they can simply try again.
      setState(() => _sending = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_errorText(l10n, e))));
    }
  }

  /// `GET /videos/interests` never answers 404 itself (a child session gets
  /// 401/403): a 404 means the server does not offer interests yet.
  String _errorText(AppLocalizations l10n, Object error) => switch (error) {
    NotFoundException() => l10n.interestsUnavailable,
    ServerException(statusCode: 503) => l10n.interestsUnavailable,
    ValidationException(code: 'interest_request_empty') =>
      l10n.interestsRequestPickOne,
    _ => describeError(l10n, error),
  };

  String _nameFor(String slug) {
    for (final cat
        in _data?.availableCategories ?? const <InterestCategoryOption>[]) {
      if (cat.slug == slug) return cat.name;
    }
    return slug;
  }

  Widget _topicChips(String keyPrefix, List<String> slugs) => Wrap(
    spacing: AppSpacing.xs,
    runSpacing: AppSpacing.xs,
    children: [
      for (final slug in slugs)
        Chip(key: Key('$keyPrefix.$slug'), label: Text(_nameFor(slug))),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final data = _data;
    final muted = context.text.bodySmall?.copyWith(
      color: context.colors.onSurfaceVariant,
    );
    return AppCard(
      key: const Key('child.interests.card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.sm,
        children: [
          SectionHeader(title: l10n.interestsTitle),
          Text(l10n.interestsChildSubtitle, style: muted),
          if (_loading && data == null)
            const LinearProgressIndicator(key: Key('child.interests.loading'))
          else if (data == null)
            ErrorView(
              key: const Key('child.interests.error'),
              error: _error!,
              message: _errorText(l10n, _error!),
              onRetry: _load,
            )
          else ...[
            Text(l10n.interestsActiveTitle, style: context.text.titleSmall),
            if (data.interests.isEmpty)
              Text(
                l10n.interestsActiveNone,
                key: const Key('child.interests.activeNone'),
                style: muted,
              )
            else
              _topicChips('child.interests.active', data.interests),
            if (data.pendingRequests.isNotEmpty) ...[
              Text(
                l10n.interestsPendingChildTitle,
                key: const Key('child.interests.pending'),
                style: context.text.titleSmall,
              ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: EyebrowPill(
                  icon: Icons.hourglass_top_rounded,
                  label: l10n.interestsPendingBadge,
                ),
              ),
              _topicChips('child.interests.pendingItem', data.pendingRequests),
            ],
            if (data.availableCategories.isEmpty)
              Text(l10n.interestsEmpty, key: const Key('child.interests.empty'))
            else ...[
              Text(l10n.interestsAskTitle, style: context.text.titleSmall),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  for (final cat in data.availableCategories)
                    FilterChip(
                      key: Key('child.interest.${cat.slug}'),
                      label: Text(cat.name),
                      selected: _requested.contains(cat.slug),
                      onSelected: _sending
                          ? null
                          : (v) => setState(() {
                              _edited = true;
                              if (v) {
                                _requested.add(cat.slug);
                              } else {
                                _requested.remove(cat.slug);
                              }
                            }),
                    ),
                ],
              ),
              if (_requested.isEmpty)
                Text(
                  l10n.interestsRequestPickOne,
                  key: const Key('child.interests.pickOne'),
                  style: muted,
                ),
              if (_sending)
                const LinearProgressIndicator(
                  key: Key('child.interests.sending'),
                ),
              SecondaryButton(
                key: const Key('child.interests.request'),
                label: l10n.interestsRequestSave,
                onPressed: _sending || _requested.isEmpty
                    ? null
                    : _submitRequest,
              ),
            ],
          ],
        ],
      ),
    );
  }
}
