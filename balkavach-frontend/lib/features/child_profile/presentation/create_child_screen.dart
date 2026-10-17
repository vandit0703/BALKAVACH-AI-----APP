import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/api_exception.dart';
import '../../../core/responsive/breakpoints.dart';
import '../../../core/storage/app_preferences.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/models/app_assets.dart';
import '../../../shared/validation/validators.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/buttons.dart';
import '../../../shared/widgets/illustration.dart';
import '../../../shared/widgets/state_views.dart';
import '../../onboarding/presentation/onboarding_controller.dart';
import '../data/family_repository.dart';
import '../domain/family_models.dart';
import 'family_providers.dart';

const _languageNames = {
  'en': 'English',
  'gu': 'ગુજરાતી',
  'hi': 'हिन्दी',
};

/// Add Your Child's Profile. Sends only fields the backend stores
/// (`display_name`, `date_of_birth`, `preferred_language`). Age bracket and
/// interests from the Stitch design are not stored by the API (B8) and are
/// left out; the avatar is kept on this device (B7).
class CreateChildScreen extends ConsumerStatefulWidget {
  const CreateChildScreen({super.key});

  @override
  ConsumerState<CreateChildScreen> createState() => _CreateChildScreenState();
}

class _CreateChildScreenState extends ConsumerState<CreateChildScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  DateTime? _dob;
  ChildAvatarOption _avatar = ChildAvatarOption.explorer;
  late String _language =
      ref.read(onboardingControllerProvider).languageCode ?? 'en';
  bool _busy = false;
  Map<String, String> _fieldErrors = const {};

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(now.year - 7, now.month, now.day),
      // Backend: strictly in the past and younger than 18.
      firstDate: DateTime(now.year - 18, now.month, now.day + 1),
      lastDate: DateTime(now.year, now.month, now.day - 1),
    );
    if (picked != null) setState(() => _dob = picked);
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() => _fieldErrors = const {});
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    try {
      // Await rather than read `.value`: the family may still be loading.
      final family = await ref.read(currentFamilyProvider.future);
      if (family == null) {
        throw const NotFoundException(message: 'Family not found');
      }
      final child = await ref
          .read(familyRepositoryProvider)
          .createChild(
            family.id,
            NewChildProfile(
              displayName: _name.text,
              username: _username.text,
              password: _password.text,
              preferredLanguage: _language,
              dateOfBirth: _dob,
            ),
          );
      await ref
          .read(appPreferencesProvider)
          .setChildAvatarKey(child.id, _avatar.name);
      ref.invalidate(familyChildrenProvider(family.id));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).createChildSuccess),
        ),
      );
      await Navigator.maybePop(context);
    } on ValidationException catch (error) {
      if (!mounted) return;
      setState(() {
        final l10n = AppLocalizations.of(context);
        _fieldErrors = {
          for (final e in error.fieldErrors)
            e.field: l10n.validationFieldInvalid,
        };
      });
      if (_fieldErrors.isEmpty) showErrorSnackBar(context, error);
    } on ConflictException {
      if (mounted) {
        setState(
          () => _fieldErrors = {
            'username': AppLocalizations.of(context).errorUsernameTaken,
          },
        );
      }
    } on ApiException catch (error) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        if (error.code == 'credential_encryption_unavailable') {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.createChildCredentialsConfigMissing)),
          );
        } else {
          showErrorSnackBar(context, error);
        }
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final name = _name.text.trim();
    final locale = Localizations.localeOf(context).toLanguageTag();
    final dobError = _fieldErrors['date_of_birth'] ?? _fieldErrors['body'];

    return Scaffold(
      appBar: AppBar(),
      body: Form(
        key: _formKey,
        child: ScrollablePage(
          maxWidth: ContentWidth.form,
          spacing: AppSpacing.lg,
          children: [
            _Header(
              eyebrow: l10n.createChildEyebrow,
              title: l10n.createChildTitle,
              subtitle: l10n.createChildSubtitle,
            ),
            AppTextField(
              fieldKey: const Key('child.name'),
              label: l10n.createChildName,
              trailingLabel: l10n.createChildNameHint,
              controller: _name,
              validator: Validators(l10n).childName,
              maxLength: 100,
              textInputAction: TextInputAction.done,
              errorText: _fieldErrors['display_name'],
            ),
            AppTextField(
              fieldKey: const Key('child.username'),
              label: l10n.createChildUsername,
              controller: _username,
              validator: Validators(l10n).childUsername,
              maxLength: 32,
              textInputAction: TextInputAction.next,
              errorText: _fieldErrors['username'],
            ),
            AppTextField(
              fieldKey: const Key('child.password'),
              label: l10n.createChildPassword,
              controller: _password,
              validator: Validators(l10n).newPassword,
              obscure: true,
              showObscureToggle: true,
              showPasswordLabel: l10n.authShowPassword,
              hidePasswordLabel: l10n.authHidePassword,
              maxLength: 128,
              textInputAction: TextInputAction.next,
              errorText: _fieldErrors['password'],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: AppSpacing.sm,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.createChildDob,
                        style: context.text.titleSmall,
                      ),
                    ),
                    Text(
                      l10n.optional,
                      style: context.text.labelMedium?.copyWith(
                        color: context.colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SecondaryButton(
                      key: const Key('child.dob'),
                      icon: Icons.cake_outlined,
                      label: _dob == null
                          ? l10n.createChildDobPick
                          : DateFormat.yMMMd(locale).format(_dob!),
                      onPressed: _pickDob,
                    ),
                    if (_dob != null)
                      TextButton(
                        onPressed: () => setState(() => _dob = null),
                        child: Text(l10n.createChildDobClear),
                      ),
                  ],
                ),
                if (dobError != null)
                  Text(
                    dobError,
                    style: context.text.bodySmall?.copyWith(
                      color: context.colors.error,
                    ),
                  ),
              ],
            ),
            AvatarPicker(
              selected: _avatar,
              onSelected: (option) => setState(() => _avatar = option),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: AppSpacing.sm,
              children: [
                Text(l10n.createChildLanguage, style: context.text.titleSmall),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (final MapEntry(key: code, value: label)
                        in _languageNames.entries)
                      ChoiceChip(
                        label: Text(label),
                        selected: _language == code,
                        onSelected: (_) => setState(() => _language = code),
                        labelStyle: context.text.labelLarge?.copyWith(
                          color: _language == code
                              ? context.colors.onPrimary
                              : context.colors.onSurface,
                        ),
                      ),
                  ],
                ),
              ],
            ),
            PrimaryButton(
              key: const Key('child.submit'),
              label: name.isEmpty
                  ? l10n.createChildSubmitGeneric
                  : l10n.createChildSubmit(name),
              icon: Icons.rocket_launch_rounded,
              loading: _busy,
              childSized: true,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
  });

  final String eyebrow;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      radius: AppRadius.hero,
      gradient: LinearGradient(
        colors: [
          context.colors.surfaceContainerLow,
          context.colors.surfaceContainerHigh,
        ],
      ),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: AppSpacing.sm,
        children: [
          EyebrowPill(
            label: eyebrow,
            icon: Icons.auto_awesome_rounded,
            background: context.colors.tertiaryFixed,
            foreground: context.colors.onTertiaryFixed,
          ),
          Text(title, style: context.text.headlineMedium),
          Text(
            subtitle,
            style: context.text.bodyMedium?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class AvatarPicker extends StatelessWidget {
  const AvatarPicker({
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final ChildAvatarOption selected;
  final ValueChanged<ChildAvatarOption> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.sm,
      children: [
        Text(l10n.createChildAvatar, style: context.text.titleSmall),
        AppCard(
          color: context.colors.surfaceContainerLow,
          elevated: false,
          padding: const EdgeInsets.all(AppSpacing.md),
          child: LayoutBuilder(
            builder: (context, constraints) {
              const columns = 3;
              final size =
                  ((constraints.maxWidth - AppSpacing.md * (columns - 1)) /
                          columns)
                      .clamp(56.0, 96.0);
              return Wrap(
                alignment: WrapAlignment.center,
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.md,
                children: [
                  for (final option in ChildAvatarOption.values)
                    Semantics(
                      selected: option == selected,
                      button: true,
                      label: option.name,
                      child: InkResponse(
                        key: Key('avatar.${option.name}'),
                        onTap: () => onSelected(option),
                        radius: size / 2,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              width: 3,
                              color: option == selected
                                  ? context.colors.tertiaryFixedDim
                                  : Colors.transparent,
                            ),
                          ),
                          child: ChildAvatar(
                            name: option.name,
                            option: option,
                            size: size - 14,
                            ring: false,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        Text(
          l10n.createChildAvatarLocal,
          style: context.text.bodySmall?.copyWith(
            color: context.colors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
