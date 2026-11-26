import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/platform/link_opener.dart';
import '../../../../shared/platform/text_sharer.dart';
import '../../../authentication/presentation/session_controller.dart';
import '../../data/playable_video.dart';
import '../youtube_player_screen.dart' show showVideoReportDialog;

void _notify(BuildContext context, String message) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

bool _leaveGateOpen = false;

/// A child is signed in. Children never leave BALKAVACH for YouTube: once in
/// the YouTube app, its autoplay, suggestions and floating player are outside
/// the approved catalogue and outside anything BALKAVACH can control.
///
/// Waits for the session if it is still loading. If it cannot be read, the
/// answer is "child" (fail closed): a link that should have opened is the
/// safer mistake.
Future<bool> isChildSession(WidgetRef ref) async {
  try {
    final session = await ref.read(sessionControllerProvider.future);
    return session?.isChild ?? false;
  } on Object {
    return true;
  }
}

/// A link inside the YouTube player wants to leave the app. In a child
/// session it never opens (a short message explains why). Otherwise a
/// grown-up must confirm before it opens in the YouTube app or browser.
/// Several navigation events can arrive for one tap, so only one dialog is
/// ever shown.
Future<void> askGrownUpThenOpen(
  BuildContext context,
  WidgetRef ref,
  Uri uri,
) async {
  if (_leaveGateOpen || !context.mounted) return;
  _leaveGateOpen = true; // one answer per tap, even while the session loads
  final child = await isChildSession(ref);
  if (child || !context.mounted) {
    _leaveGateOpen = false;
    if (child && context.mounted) {
      _notify(context, AppLocalizations.of(context).youtubeLeaveBlocked);
    }
    return;
  }
  final l10n = AppLocalizations.of(context);
  bool? confirmed;
  try {
    confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('youtube.leaveGate'),
        title: Text(l10n.youtubeLeaveTitle),
        content: Text(l10n.youtubeLeaveBody),
        actions: [
          TextButton(
            key: const Key('youtube.leaveStay'),
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.youtubeLeaveStay),
          ),
          FilledButton(
            key: const Key('youtube.leaveOpen'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.youtubeLeaveOpen),
          ),
        ],
      ),
    );
  } finally {
    _leaveGateOpen = false;
  }
  if (confirmed ?? false) await ref.read(linkOpenerProvider).open(uri);
}

/// Sharing opens another app, so a grown-up confirms first. Hosted media is
/// never shared (there is no link to share).
Future<void> confirmAndShareVideo(
  BuildContext context,
  WidgetRef ref,
  PlayableVideo video,
) async {
  final uri = video.shareUri;
  if (uri == null) return;
  final l10n = AppLocalizations.of(context);
  // A shared watch link opens straight in the YouTube app, so children
  // cannot share videos.
  if (await isChildSession(ref)) {
    if (context.mounted) _notify(context, l10n.videoShareBlocked);
    return;
  }
  if (!context.mounted) return;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      key: const Key('video.shareGate'),
      icon: const Icon(Icons.lock_outline_rounded),
      title: Text(l10n.videoShareTitle),
      content: Text(l10n.videoShareBody),
      actions: [
        TextButton(
          key: const Key('video.shareCancel'),
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.videoShareCancel),
        ),
        FilledButton(
          key: const Key('video.shareConfirm'),
          onPressed: () => Navigator.pop(context, true),
          child: Text(l10n.videoShare),
        ),
      ],
    ),
  );
  if (!(confirmed ?? false) || !context.mounted) return;
  final shared = await ref
      .read(textSharerProvider)
      .share('${video.title}\n$uri', subject: video.title);
  if (!shared && context.mounted) _notify(context, l10n.videoShareFailed);
}

/// Grown-up report form for a server video row, with the outcome announced.
/// Returns whether the server accepted the report.
Future<bool> reportVideo(BuildContext context, String videoId) async {
  final sent = await showVideoReportDialog(context, videoId);
  if (sent == null || !context.mounted) return false;
  final l10n = AppLocalizations.of(context);
  _notify(context, sent ? l10n.videoReportSent : l10n.videoReportFailed);
  return sent;
}

/// A server thumbnail (https only), or a calm placeholder.
class VideoThumbnail extends StatelessWidget {
  const VideoThumbnail({
    required this.url,
    this.fit = BoxFit.cover,
    this.placeholderColor,
    this.iconColor,
    super.key,
  });

  final String? url;
  final BoxFit fit;
  final Color? placeholderColor;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final placeholder = ColoredBox(
      color: placeholderColor ?? colors.primaryFixed,
      child: Center(
        child: Icon(
          Icons.play_circle_rounded,
          size: 40,
          color: iconColor ?? colors.primary,
        ),
      ),
    );
    final source = url;
    if (source == null) return placeholder;
    return Image.network(
      source,
      fit: fit,
      excludeFromSemantics: true,
      errorBuilder: (_, _, _) => placeholder,
      frameBuilder: (context, child, frame, synchronous) =>
          synchronous || frame != null ? child : placeholder,
    );
  }
}
