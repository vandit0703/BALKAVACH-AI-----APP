import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/async/refresh_quietly.dart';
import '../../../shared/models/app_assets.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/brand_header.dart';
import '../../../shared/widgets/buttons.dart';
import '../../../shared/widgets/gamification.dart';
import '../../../shared/widgets/illustration.dart';
import '../../../shared/widgets/lazy_list_page.dart';
import '../../../shared/widgets/state_views.dart';
import '../../child_profile/presentation/family_providers.dart';
import '../../missions/domain/mission_models.dart';
import '../../missions/presentation/mission_providers.dart';
import '../../missions/presentation/widgets/mission_visuals.dart';
import '../domain/review_models.dart';
import 'approval_providers.dart';

enum _Tab { pending, approved, retry }

/// Mission Approvals (Stitch `parent_mission_approval`).
///
/// Photo proof is shown only when a submission carries a `proof_url`; the
/// backend has no upload endpoint yet (B2), so most submissions have a note.
class ApprovalsScreen extends ConsumerWidget {
  const ApprovalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final family = ref.watch(currentFamilyProvider);
    return Scaffold(
      appBar: AppBar(title: BrandTitle(title: l10n.approvalsAppBar)),
      body: switch (family) {
        AsyncData(value: final f?) => _InboxBody(familyId: f.id),
        AsyncData() => EmptyView(message: l10n.familyMissing),
        AsyncError(:final error) => ErrorView(
          error: error,
          onRetry: () => ref.invalidate(currentFamilyProvider),
        ),
        _ => const LoadingView(),
      },
    );
  }
}

class _InboxBody extends ConsumerStatefulWidget {
  const _InboxBody({required this.familyId});

  final String familyId;

  @override
  ConsumerState<_InboxBody> createState() => _InboxBodyState();
}

class _InboxBodyState extends ConsumerState<_InboxBody> {
  _Tab _tab = _Tab.pending;
  String? _childFilter;

  Future<void> _refresh() async {
    ref
      ..invalidate(familyMissionsProvider(widget.familyId))
      ..invalidate(approvalInboxProvider(widget.familyId));
    await refreshQuietly(
      ref.read(approvalInboxProvider(widget.familyId).future),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final inbox = ref.watch(approvalInboxProvider(widget.familyId));
    final children =
        ref.watch(familyChildrenProvider(widget.familyId)).value ?? const [];

    List<ReviewItem> visible(List<ReviewItem> items) => _childFilter == null
        ? items
        : items.where((i) => i.submission.childId == _childFilter).toList();

    final header = <Widget>[
      _Header(pending: inbox.value?.pending.length),
      if (children.length > 1)
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            ChoiceChip(
              label: Text(l10n.filterAllChildren),
              selected: _childFilter == null,
              onSelected: (_) => setState(() => _childFilter = null),
            ),
            for (final child in children)
              ChoiceChip(
                label: Text(child.displayName),
                selected: _childFilter == child.id,
                onSelected: (_) => setState(() => _childFilter = child.id),
              ),
          ],
        ),
    ];

    final Widget page = switch (inbox) {
      AsyncData(:final value) => _loaded(context, l10n, header, value, visible),
      AsyncError(:final error) => LazyListPage(
        header: [
          ...header,
          ErrorView(error: error, onRetry: _refresh),
        ],
        itemCount: 0,
        itemBuilder: (_, _) => const SizedBox.shrink(),
      ),
      _ => LazyListPage(
        header: [...header, const LoadingView()],
        itemCount: 0,
        itemBuilder: (_, _) => const SizedBox.shrink(),
      ),
    };
    return RefreshIndicator(onRefresh: _refresh, child: page);
  }

  Widget _loaded(
    BuildContext context,
    AppLocalizations l10n,
    List<Widget> header,
    ApprovalInbox inbox,
    List<ReviewItem> Function(List<ReviewItem>) visible,
  ) {
    final items = switch (_tab) {
      _Tab.pending => visible(inbox.pending),
      _Tab.approved => visible(inbox.approved),
      _Tab.retry => visible(inbox.retry),
    };
    final emptyMessage = switch (_tab) {
      _Tab.pending => l10n.approvalsPendingEmpty,
      _Tab.approved => l10n.approvalsApprovedEmpty,
      _Tab.retry => l10n.approvalsRetryEmpty,
    };

    return LazyListPage(
      header: [
        ...header,
        _TabPills(
          selected: _tab,
          counts: {
            _Tab.pending: visible(inbox.pending).length,
            _Tab.approved: visible(inbox.approved).length,
            _Tab.retry: visible(inbox.retry).length,
          },
          onSelected: (tab) => setState(() => _tab = tab),
        ),
        if (inbox.truncated) InlineNotice(message: l10n.approvalsTruncated),
        if (inbox.failedCount > 0)
          _PartialFailureNotice(count: inbox.failedCount, onRetry: _refresh),
        if (items.isEmpty)
          EmptyView(
            message: emptyMessage,
            image: _tab == _Tab.pending ? AppImages.pandaCheering : null,
          ),
      ],
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return _tab == _Tab.pending
            ? _PendingCard(
                key: Key('review.${item.submission.id}'),
                familyId: widget.familyId,
                item: item,
              )
            : _ReviewedTile(item: item);
      },
      footer: [if (_tab == _Tab.pending) _TipCard()],
    );
  }
}

class _PartialFailureNotice extends StatelessWidget {
  const _PartialFailureNotice({required this.count, required this.onRetry});

  final int count;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.sm,
      children: [
        InlineNotice(
          key: const Key('approvals.partial'),
          icon: Icons.cloud_off_rounded,
          message: l10n.approvalsPartial(count),
        ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: SecondaryButton(
            key: const Key('approvals.partial.retry'),
            dense: true,
            label: l10n.retry,
            icon: Icons.refresh_rounded,
            onPressed: onRetry,
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.pending});

  final int? pending;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: AppSpacing.xs,
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Semantics(
              header: true,
              child: Text(
                l10n.approvalsTitle,
                style: context.text.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (pending != null && pending! > 0)
              EyebrowPill(
                icon: Icons.pending_actions_rounded,
                label: l10n.approvalsActions(pending!),
              ),
          ],
        ),
        Text(
          l10n.approvalsSubtitle,
          style: context.text.bodyMedium?.copyWith(
            color: context.colors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _TabPills extends StatelessWidget {
  const _TabPills({
    required this.selected,
    required this.counts,
    required this.onSelected,
  });

  final _Tab selected;
  final Map<_Tab, int> counts;
  final ValueChanged<_Tab> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final labels = {
      _Tab.pending: l10n.approvalsTabPending,
      _Tab.approved: l10n.approvalsTabApproved,
      _Tab.retry: l10n.approvalsTabRetry,
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xs),
        child: Row(
          children: [
            for (final tab in _Tab.values)
              Expanded(
                child: Semantics(
                  selected: tab == selected,
                  button: true,
                  child: Material(
                    color: tab == selected
                        ? colors.primary
                        : Colors.transparent,
                    shape: const StadiumBorder(),
                    child: InkWell(
                      key: Key('approvals.tab.${tab.name}'),
                      customBorder: const StadiumBorder(),
                      onTap: () => onSelected(tab),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          minHeight: AppTouch.parentMin,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.xs,
                            vertical: AppSpacing.xs,
                          ),
                          child: Wrap(
                            alignment: WrapAlignment.center,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 6,
                            runSpacing: 2,
                            children: [
                              Text(
                                labels[tab]!,
                                style: context.text.labelLarge?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: tab == selected
                                      ? colors.onPrimary
                                      : colors.onSurfaceVariant,
                                ),
                              ),
                              _CountBadge(
                                count: counts[tab] ?? 0,
                                selected: tab == selected,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count, required this.selected});

  final int count;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: selected
            ? colors.onPrimary.withValues(alpha: 0.2)
            : colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        child: Text(
          '$count',
          style: context.text.labelMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: selected ? colors.onPrimary : colors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _PendingCard extends ConsumerStatefulWidget {
  const _PendingCard({required this.familyId, required this.item, super.key});

  final String familyId;
  final ReviewItem item;

  @override
  ConsumerState<_PendingCard> createState() => _PendingCardState();
}

class _PendingCardState extends ConsumerState<_PendingCard> {
  ReviewDecision? _busy;

  String get _childName =>
      widget.item.childName ?? AppLocalizations.of(context).someChild;

  Future<void> _review(ReviewDecision decision) async {
    final l10n = AppLocalizations.of(context);
    String? note;
    if (decision != ReviewDecision.approved) {
      final result = await showDialog<String>(
        context: context,
        builder: (_) => _NoteDialog(
          title: decision == ReviewDecision.resubmissionRequested
              ? l10n.approvalsRetryTitle(_childName)
              : l10n.approvalsDeclineTitle(_childName),
          confirmLabel: decision == ReviewDecision.resubmissionRequested
              ? l10n.approvalsRetry
              : l10n.approvalsDecline,
        ),
      );
      if (result == null || !mounted) return;
      note = result;
    }
    setState(() => _busy = decision);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await reviewSubmission(
        ref,
        familyId: widget.familyId,
        item: widget.item,
        decision: decision,
        note: note,
      );
      final stars = widget.item.mission?.starReward ?? 0;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(switch (decision) {
              ReviewDecision.approved => l10n.approvalsApprovedToast(
                _childName,
                stars,
              ),
              ReviewDecision.resubmissionRequested => l10n.approvalsRetryToast(
                _childName,
              ),
              ReviewDecision.rejected => l10n.approvalsDeclinedToast,
            }),
          ),
        );
    } on ConflictException {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.approvalsAlreadyReviewed)));
    } on ApiException catch (error) {
      if (mounted) showErrorSnackBar(context, error);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final submission = widget.item.submission;
    final mission = widget.item.mission;
    final stars = mission?.starReward ?? 0;
    final child = widget.item.child;
    final avatar = child == null
        ? null
        : ref.watch(childAvatarProvider(child.id));
    final locale = Localizations.localeOf(context).toLanguageTag();
    final when = DateFormat.MMMd(
      locale,
    ).add_jm().format(submission.submittedAt.toLocal());
    final proofUrl = submission.proofUrl;
    final note = submission.proofNote?.trim();
    final busy = _busy != null;

    return AppCard(
      radius: AppRadius.hero,
      padding: const EdgeInsets.all(AppSpacing.md + 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.md,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ChildAvatar(name: _childName, option: avatar, size: 56),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 2,
                  children: [
                    Text(_childName, style: context.text.titleLarge),
                    Text(
                      l10n.approvalsMissionLabel(
                        mission?.title ?? l10n.approvalsMissionRemoved,
                      ),
                      style: context.text.titleSmall?.copyWith(
                        color: colors.primary,
                      ),
                    ),
                    Text(
                      when,
                      style: context.text.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              StarPill(count: stars, prefix: '+'),
            ],
          ),
          if (proofUrl != null && submission.proofType == 'image')
            _ProofImage(url: proofUrl),
          if (note != null && note.isNotEmpty)
            _NoteQuote(name: _childName, note: note)
          else
            Text(
              l10n.approvalsNoNote,
              style: context.text.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          Row(
            children: [
              Icon(
                Icons.lock_outline_rounded,
                size: 18,
                color: colors.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  l10n.approvalsPrivacy,
                  style: context.text.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          PrimaryButton(
            key: const Key('review.approve'),
            label: l10n.approvalsApprove(stars),
            icon: Icons.military_tech_rounded,
            backgroundColor: colors.secondary,
            loading: _busy == ReviewDecision.approved,
            onPressed: busy ? null : () => _review(ReviewDecision.approved),
          ),
          SecondaryButton(
            key: const Key('review.retry'),
            label: l10n.approvalsAskRetry,
            icon: Icons.edit_note_rounded,
            onPressed: busy
                ? null
                : () => _review(ReviewDecision.resubmissionRequested),
          ),
          TextButton(
            key: const Key('review.decline'),
            onPressed: busy ? null : () => _review(ReviewDecision.rejected),
            child: Text(l10n.approvalsDecline),
          ),
        ],
      ),
    );
  }
}

/// The child's proof photo. Photos stored by the server are fetched with the
/// parent's token; an older absolute URL is loaded directly.
class _ProofImage extends ConsumerWidget {
  const _ProofImage({required this.url});

  final String url;

  bool get _isServerPhoto => url.startsWith('/');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    Widget unavailable() => ColoredBox(
      color: context.colors.surfaceContainerHigh,
      child: Center(
        child: Text(
          l10n.approvalsProofUnavailable,
          textAlign: TextAlign.center,
        ),
      ),
    );

    Widget image(ImageProvider provider, {BoxFit fit = BoxFit.cover}) => Image(
      image: provider,
      fit: fit,
      semanticLabel: l10n.approvalsProofImage,
      errorBuilder: (context, error, stackTrace) => unavailable(),
    );

    final ImageProvider? provider = _isServerPhoto
        ? ref.watch(proofImageProvider(url)).value == null
              ? null
              : MemoryImage(ref.watch(proofImageProvider(url)).value!)
        : NetworkImage(url);
    final loadFailed =
        _isServerPhoto && ref.watch(proofImageProvider(url)).hasError;

    return ClipRRect(
      borderRadius: AppRadius.hero,
      child: AspectRatio(
        aspectRatio: 4 / 3,
        child: loadFailed
            ? unavailable()
            : provider == null
            ? const Center(child: CircularProgressIndicator())
            : Semantics(
                button: true,
                hint: l10n.approvalsProofZoom,
                child: InkWell(
                  key: const Key('review.proof'),
                  onTap: () => showDialog<void>(
                    context: context,
                    builder: (dialogContext) => Dialog.fullscreen(
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: InteractiveViewer(
                              maxScale: 5,
                              child: image(provider, fit: BoxFit.contain),
                            ),
                          ),
                          Positioned(
                            top: AppSpacing.md,
                            right: AppSpacing.md,
                            child: IconButton.filled(
                              tooltip: l10n.close,
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  child: image(provider),
                ),
              ),
      ),
    );
  }
}

class _NoteQuote extends StatelessWidget {
  const _NoteQuote({required this.name, required this.note});

  final String name;
  final String note;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.format_quote_rounded, color: colors.primary, size: 28),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: AppSpacing.xs,
                children: [
                  Text(
                    l10n.approvalsNoteFrom(name),
                    style: context.text.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '“$note”',
                    style: context.text.bodyLarge?.copyWith(
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewedTile extends ConsumerWidget {
  const _ReviewedTile({required this.item});

  final ReviewItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final categories =
        ref.watch(taskCategoriesProvider).value ?? const <TaskCategory>[];
    final mission = item.mission;
    final category = categories
        .where((c) => c.id == mission?.categoryId)
        .firstOrNull;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final reviewedAt =
        item.submission.reviewedAt ?? item.submission.submittedAt;
    final when = DateFormat.MMMd(locale).add_jm().format(reviewedAt.toLocal());
    final name = item.childName ?? l10n.someChild;

    final Widget trailing = switch (item.status) {
      'approved' => StatusChip(
        label: l10n.approvalsStarsCredited(mission?.starReward ?? 0),
        icon: Icons.verified_rounded,
        background: colors.secondaryContainer,
        foreground: colors.onSecondaryContainer,
      ),
      'rejected' => StatusChip(
        label: l10n.statusRejected,
        icon: Icons.do_not_disturb_on_outlined,
        background: colors.errorContainer,
        foreground: colors.onErrorContainer,
      ),
      _ => StatusChip(
        label: l10n.approvalsRetrySent,
        icon: Icons.replay_rounded,
        background: colors.surfaceContainerHigh,
        foreground: colors.primary,
      ),
    };

    return AppCard(
      color: colors.surfaceContainerLow,
      elevated: false,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: AppSpacing.sm,
        children: [
          Row(
            children: [
              CategoryIcon(
                visual: CategoryVisual.of(context, category),
                size: 48,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      mission?.title ?? l10n.approvalsMissionRemoved,
                      style: context.text.titleMedium,
                    ),
                    Text(
                      '$name • $when',
                      style: context.text.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          trailing,
        ],
      ),
    );
  }
}

class _TipCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    return AppCard(
      color: colors.surfaceContainer,
      elevated: false,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: colors.tertiaryFixed,
            child: Icon(
              Icons.lightbulb_outline_rounded,
              color: colors.onTertiaryFixed,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: AppSpacing.xs,
              children: [
                Text(l10n.approvalsTipTitle, style: context.text.titleMedium),
                Text(l10n.approvalsTipBody, style: context.text.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Asks for an optional note to send with a retry or decline.
class _NoteDialog extends StatefulWidget {
  const _NoteDialog({required this.title, required this.confirmLabel});

  final String title;
  final String confirmLabel;

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        key: const Key('review.note'),
        controller: _note,
        maxLength: 2000,
        minLines: 2,
        maxLines: 4,
        decoration: InputDecoration(labelText: l10n.approvalsNoteLabel),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const Key('review.note.confirm'),
          onPressed: () => Navigator.pop(context, _note.text),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
