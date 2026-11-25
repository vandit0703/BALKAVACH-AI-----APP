import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  ChildInterests? _data;
  Set<String> _selected = {};
  Object? _error;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ref
          .read(familyRepositoryProvider)
          .getChildInterests(widget.familyId, widget.childId);
      if (!mounted) return;
      setState(() {
        _data = data;
        _selected = data.interests.toSet();
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

  Future<void> _save({
    required List<String> interests,
    bool clearPending = true,
  }) async {
    setState(() => _saving = true);
    final l10n = AppLocalizations.of(context);
    try {
      final updated = await ref
          .read(familyRepositoryProvider)
          .updateChildInterests(
            widget.familyId,
            widget.childId,
            interests,
            clearPending: clearPending,
          );
      if (!mounted) return;
      setState(() {
        _data = updated;
        _selected = updated.interests.toSet();
        _saving = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.interestsSaved)));
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(describeError(l10n, e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppCard(
      key: const Key('parent.interests.card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.sm,
        children: [
          SectionHeader(title: l10n.interestsTitle),
          Text(
            l10n.interestsParentSubtitle,
            style: context.text.bodySmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
          if (_loading)
            const LinearProgressIndicator()
          else if (_error != null)
            ErrorView(error: _error!, onRetry: _load)
          else if (_data == null || _data!.availableCategories.isEmpty)
            Text(l10n.interestsEmpty)
          else ...[
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
                          Chip(label: Text(_nameFor(slug))),
                      ],
                    ),
                    Wrap(
                      spacing: AppSpacing.sm,
                      children: [
                        FilledButton(
                          key: const Key('parent.interests.approve'),
                          onPressed: _saving
                              ? null
                              : () => _save(
                                  interests: {
                                    ..._selected,
                                    ..._data!.pendingRequests,
                                  }.toList(),
                                  clearPending: true,
                                ),
                          child: Text(l10n.interestsApproveAll),
                        ),
                        TextButton(
                          key: const Key('parent.interests.reject'),
                          onPressed: _saving
                              ? null
                              : () => _save(
                                  interests: _selected.toList(),
                                  clearPending: true,
                                ),
                          child: Text(l10n.interestsRejectAll),
                        ),
                      ],
                    ),
                  ],
                ),
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
            PrimaryButton(
              key: const Key('parent.interests.save'),
              label: l10n.interestsSave,
              loading: _saving,
              onPressed: () => _save(
                interests: _selected.toList(),
                clearPending: false,
              ),
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
class ChildInterestsCard extends ConsumerStatefulWidget {
  const ChildInterestsCard({super.key});

  @override
  ConsumerState<ChildInterestsCard> createState() => _ChildInterestsCardState();
}

class _ChildInterestsCardState extends ConsumerState<ChildInterestsCard> {
  ChildInterests? _data;
  Set<String> _requested = {};
  bool _loading = true;
  bool _sending = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

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
        _data = parsed;
        _requested = parsed.pendingRequests.isNotEmpty
            ? parsed.pendingRequests.toSet()
            : parsed.interests.toSet();
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
    setState(() => _sending = true);
    final l10n = AppLocalizations.of(context);
    try {
      final json = await ref
          .read(videoFeedRepositoryProvider)
          .requestInterests(_requested.toList());
      if (!mounted) return;
      final parsed = ChildInterests.fromJson(json);
      setState(() {
        _data = parsed;
        _sending = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.interestsRequestSent)));
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(describeError(l10n, e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppCard(
      key: const Key('child.interests.card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.sm,
        children: [
          SectionHeader(title: l10n.interestsTitle),
          Text(
            l10n.interestsChildSubtitle,
            style: context.text.bodySmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
          if (_loading)
            const LinearProgressIndicator()
          else if (_error != null)
            ErrorView(error: _error!, onRetry: _load)
          else if (_data == null || _data!.availableCategories.isEmpty)
            Text(l10n.interestsEmpty)
          else ...[
            if (_data!.pendingRequests.isNotEmpty)
              EyebrowPill(
                icon: Icons.hourglass_top_rounded,
                label: l10n.interestsPendingBadge,
              ),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final cat in _data!.availableCategories)
                  FilterChip(
                    key: Key('child.interest.${cat.slug}'),
                    label: Text(cat.name),
                    selected: _requested.contains(cat.slug),
                    onSelected: _sending
                        ? null
                        : (v) => setState(() {
                            if (v) {
                              _requested.add(cat.slug);
                            } else {
                              _requested.remove(cat.slug);
                            }
                          }),
                  ),
              ],
            ),
            SecondaryButton(
              key: const Key('child.interests.request'),
              label: l10n.interestsRequestSave,
              onPressed: _sending ? null : _submitRequest,
            ),
          ],
        ],
      ),
    );
  }
}
