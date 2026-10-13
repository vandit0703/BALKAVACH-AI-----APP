import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_exception.dart';
import '../../../core/responsive/breakpoints.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/validation/validators.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/buttons.dart';
import '../../../shared/widgets/state_views.dart';
import '../../child_profile/presentation/family_providers.dart';
import '../data/rewards_repository.dart';

/// Create (`rewardId == null`) or edit a reward in the parent's family.
class RewardFormScreen extends ConsumerStatefulWidget {
  const RewardFormScreen({this.rewardId, super.key});

  final String? rewardId;

  @override
  ConsumerState<RewardFormScreen> createState() => _RewardFormScreenState();
}

class _RewardFormScreenState extends ConsumerState<RewardFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _cost = TextEditingController(text: '5');
  String _type = 'custom';
  bool _saving = false;
  bool _filled = false;
  Object? _error;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _cost.dispose();
    super.dispose();
  }

  void _fillFrom(Reward reward) {
    if (_filled) return;
    _filled = true;
    _name.text = reward.name;
    _description.text = reward.description ?? '';
    _cost.text = '${reward.starCost}';
    _type = kRewardTypes.contains(reward.rewardType)
        ? reward.rewardType
        : 'custom';
  }

  Future<void> _save(String familyId) async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() {
      _saving = true;
      _error = null;
    });
    final input = RewardInput(
      name: _name.text,
      description: _description.text,
      rewardType: _type,
      starCost: int.parse(_cost.text.trim()),
    );
    try {
      final repository = ref.read(rewardsRepositoryProvider);
      if (widget.rewardId == null) {
        await repository.createReward(familyId, input);
      } else {
        await repository.updateReward(widget.rewardId!, input);
      }
      ref.invalidate(familyRewardsProvider(familyId));
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.rewardsSaved)));
      await navigator.maybePop();
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _typeLabel(AppLocalizations l10n, String type) => switch (type) {
    'gift' => l10n.rewardTypeGift,
    'book' => l10n.rewardTypeBook,
    'outdoor_activity' => l10n.rewardTypeOutdoor,
    'screen_time' => l10n.rewardTypeScreenTime,
    _ => l10n.rewardTypeCustom,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final family = ref.watch(currentFamilyProvider);
    final editing = widget.rewardId != null;
    final familyId = family.value?.id;
    final existing = editing && familyId != null
        ? ref.watch(familyRewardsProvider(familyId))
        : null;
    if (existing case AsyncData(:final value)) {
      final reward = value.where((r) => r.id == widget.rewardId).firstOrNull;
      if (reward != null) _fillFrom(reward);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? l10n.rewardsEditReward : l10n.rewardsAddReward),
      ),
      body: familyId == null
          ? (family.hasError
                ? ErrorView(error: family.error!)
                : const LoadingView())
          : Form(
              key: _formKey,
              child: ScrollablePage(
                maxWidth: ContentWidth.form,
                children: [
                  AppTextField(
                    fieldKey: const Key('reward.name'),
                    label: l10n.rewardsFormName,
                    controller: _name,
                    maxLength: 180,
                    textInputAction: TextInputAction.next,
                    validator: (v) => Validators(l10n).rewardName(v),
                    enabled: !_saving,
                  ),
                  AppTextField(
                    fieldKey: const Key('reward.description'),
                    label: l10n.rewardsFormDescription,
                    trailingLabel: l10n.optional,
                    controller: _description,
                    maxLength: 3000,
                    maxLines: 3,
                    minLines: 2,
                    validator: (v) => Validators(l10n).maxLength(v, 3000),
                    enabled: !_saving,
                  ),
                  AppTextField(
                    fieldKey: const Key('reward.cost'),
                    label: l10n.rewardsFormCost,
                    controller: _cost,
                    keyboardType: TextInputType.number,
                    validator: (v) => Validators(
                      l10n,
                    ).requiredIntRange(v, min: 1, max: 100000),
                    enabled: !_saving,
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: AppSpacing.xs,
                    children: [
                      Text(
                        l10n.rewardsFormType,
                        style: context.text.titleSmall,
                      ),
                      DropdownButtonFormField<String>(
                        key: const Key('reward.type'),
                        initialValue: _type,
                        isExpanded: true,
                        items: [
                          for (final type in kRewardTypes)
                            DropdownMenuItem(
                              value: type,
                              child: Text(_typeLabel(l10n, type)),
                            ),
                        ],
                        onChanged: _saving
                            ? null
                            : (value) => setState(() => _type = value ?? _type),
                      ),
                    ],
                  ),
                  if (_error != null)
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        describeError(l10n, _error!),
                        key: const Key('reward.error'),
                        textAlign: TextAlign.center,
                        style: context.text.bodyMedium?.copyWith(
                          color: context.colors.error,
                        ),
                      ),
                    ),
                  PrimaryButton(
                    key: const Key('reward.save'),
                    label: l10n.save,
                    loading: _saving,
                    onPressed: _saving ? null : () => _save(familyId),
                  ),
                ],
              ),
            ),
    );
  }
}
