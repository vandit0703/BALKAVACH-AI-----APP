import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/models/app_assets.dart';
import '../../../shared/platform/link_opener.dart';
import '../../../shared/platform/text_sharer.dart';
import '../../../shared/widgets/buttons.dart';
import '../data/card_sharer.dart';

/// The message that goes with a share: localized text, plus the link only when
/// one was configured. Contains nothing about any child.
String inviteMessage(AppLocalizations l10n, {String url = kShareUrl}) =>
    url.isEmpty ? l10n.inviteMessage : '${l10n.inviteMessage}\n$url';

/// "Invite other parents": a promo card plus WhatsApp and share-sheet actions.
/// Lives behind parent mode; nothing a child can reach.
class InviteScreen extends ConsumerStatefulWidget {
  const InviteScreen({this.url = kShareUrl, super.key});

  final String url;

  @override
  ConsumerState<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends ConsumerState<InviteScreen> {
  final _cardKey = GlobalKey();
  bool _busy = false;

  void _failed() {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.inviteShareFailed)));
  }

  Future<void> _whatsApp(String message) async {
    // WhatsApp's own share link; if nothing opens it, fall back to the system sheet.
    final uri = Uri.https('wa.me', '/', {'text': message});
    if (await ref.read(linkOpenerProvider).open(uri)) return;
    if (!await ref.read(textSharerProvider).share(message)) _failed();
  }

  Future<void> _shareText(String message) async {
    if (!await ref.read(textSharerProvider).share(message)) _failed();
  }

  Future<void> _shareImage(String message) async {
    setState(() => _busy = true);
    try {
      final boundary =
          _cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return _failed();
      final image = await boundary.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return _failed();
      final shared = await ref
          .read(cardSharerProvider)
          .shareImage(data.buffer.asUint8List(), text: message);
      if (!shared) _failed();
    } on Object {
      _failed();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final message = inviteMessage(l10n, url: widget.url);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.inviteTitle)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                RepaintBoundary(key: _cardKey, child: const PromoCard()),
                const SizedBox(height: AppSpacing.md),
                PrimaryButton(
                  key: const Key('invite.whatsapp'),
                  label: l10n.inviteWhatsApp,
                  icon: Icons.chat_rounded,
                  onPressed: () => unawaited(_whatsApp(message)),
                ),
                const SizedBox(height: AppSpacing.sm),
                SecondaryButton(
                  key: const Key('invite.share'),
                  label: l10n.inviteShare,
                  icon: Icons.ios_share_rounded,
                  onPressed: () => unawaited(_shareText(message)),
                ),
                const SizedBox(height: AppSpacing.sm),
                SecondaryButton(
                  key: const Key('invite.shareImage'),
                  label: l10n.inviteShareImage,
                  icon: Icons.image_outlined,
                  onPressed: _busy
                      ? null
                      : () => unawaited(_shareImage(message)),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  l10n.invitePrivacyNote,
                  key: const Key('invite.privacy'),
                  textAlign: TextAlign.center,
                  style: context.text.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The picture that gets shared. Original Panda artwork, app name and a short
/// line; no child name, age, photo or progress.
class PromoCard extends StatelessWidget {
  const PromoCard({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      key: const Key('invite.card'),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.primaryContainer, colors.surface],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: AspectRatio(
                aspectRatio: 4 / 3,
                child: Image.asset(
                  AppImages.pandaWelcome,
                  fit: BoxFit.cover,
                  semanticLabel: l10n.inviteCardPanda,
                  errorBuilder: (_, _, _) =>
                      const Icon(Icons.pets_rounded, size: 72),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              l10n.brandName,
              textAlign: TextAlign.center,
              style: context.text.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              l10n.inviteCardHeadline,
              textAlign: TextAlign.center,
              style: context.text.titleMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              l10n.inviteCardBody,
              textAlign: TextAlign.center,
              style: context.text.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
