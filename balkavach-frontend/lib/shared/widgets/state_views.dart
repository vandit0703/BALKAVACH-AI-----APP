import 'package:flutter/material.dart';

import '../../core/errors/api_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../l10n/app_localizations.dart';
import '../models/app_assets.dart';
import 'buttons.dart';

/// User-facing text for any error thrown by a repository.
String describeError(AppLocalizations l10n, Object error) {
  if (error is ApiException) {
    final byCode = _messageForCode(l10n, error.code);
    if (byCode != null) return byCode;
  }
  return switch (error) {
    NetworkException() => l10n.errorNetwork,
    RequestTimeoutException() => l10n.errorTimeout,
    UnauthorizedException() => l10n.errorSessionExpired,
    ForbiddenException() => l10n.errorForbidden,
    NotFoundException() => l10n.errorNotFound,
    ServerException() => l10n.errorServer,
    _ => l10n.errorGeneric,
  };
}

/// Specific messages for backend error codes a screen can act on.
String? _messageForCode(AppLocalizations l10n, String? code) => switch (code) {
  'submission_pending' => l10n.errorAlreadyPending,
  'task_already_completed' => l10n.errorAlreadyCompleted,
  'upload_too_large' => l10n.errorPhotoTooLarge,
  'unsupported_image' => l10n.errorPhotoUnsupported,
  'too_many_uploads' => l10n.errorPhotoQuota,
  'storage_unavailable' => l10n.errorPhotoStorage,
  'insufficient_stars' => l10n.errorNotEnoughStars,
  'redemption_pending' => l10n.errorRewardPending,
  'reward_unavailable' => l10n.errorRewardUnavailable,
  _ => null,
};

class LoadingView extends StatelessWidget {
  const LoadingView({this.label, super.key});

  final String? label;

  @override
  Widget build(BuildContext context) {
    final text = label ?? AppLocalizations.of(context).loading;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Semantics(
          liveRegion: true,
          label: text,
          child: const CircularProgressIndicator(),
        ),
      ),
    );
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView({required this.error, this.onRetry, super.key});

  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final offline = error is NetworkException;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              offline ? Icons.wifi_off_rounded : Icons.cloud_off_rounded,
              size: 48,
              color: context.colors.primary,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              describeError(l10n, error),
              textAlign: TextAlign.center,
              style: context.text.bodyLarge,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.lg),
              SecondaryButton(
                label: l10n.retry,
                icon: Icons.refresh_rounded,
                onPressed: onRetry,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class EmptyView extends StatelessWidget {
  const EmptyView({required this.message, this.image, this.action, super.key});

  final String message;
  final String? image;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipOval(
            child: Image.asset(
              image ?? AppImages.pandaMissions,
              width: 96,
              height: 96,
              fit: BoxFit.cover,
              cacheWidth: (96 * dpr).round(),
              excludeFromSemantics: true,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            message,
            textAlign: TextAlign.center,
            style: context.text.bodyLarge?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
          if (action != null) ...[
            const SizedBox(height: AppSpacing.md),
            action!,
          ],
        ],
      ),
    );
  }
}

/// Inline, non-blocking warning (e.g. "couldn't check reviews").
class InlineNotice extends StatelessWidget {
  const InlineNotice({
    required this.message,
    this.icon = Icons.info_outline_rounded,
    super.key,
  });

  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(icon, color: context.colors.primary, size: 20),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(message, style: context.text.bodyMedium)),
          ],
        ),
      ),
    );
  }
}

void showErrorSnackBar(BuildContext context, Object error) {
  final l10n = AppLocalizations.of(context);
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(describeError(l10n, error))));
}
