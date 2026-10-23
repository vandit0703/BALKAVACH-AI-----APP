/// What the app does when the official YouTube player tries to navigate.
///
/// The player's own links (title, logo, related videos, end screens, ads) stay
/// visible and working as YouTube requires, but none of them may take a child
/// to unapproved content inside Balkavach: they open outside the app, and only
/// after a grown-up confirms.
enum PlayerNavigation {
  /// The player's own page or frames loading.
  allow,

  /// A real link: ask a grown-up, then open it in the YouTube app or browser.
  openOutsideAfterGate,

  /// Anything else (non-https schemes, malformed URLs).
  block,
}

/// Decides a navigation request from the embed's web view.
///
/// [baseUrl] is the page the player loads into (the package uses
/// `params.origin ?? params.host`).
PlayerNavigation decidePlayerNavigation(
  String url, {
  required bool isMainFrame,
  required String baseUrl,
}) {
  final uri = Uri.tryParse(url);
  if (uri == null) return PlayerNavigation.block;
  if (!isMainFrame) return PlayerNavigation.allow;
  if (uri.scheme == 'about' && uri.path == 'blank') {
    return PlayerNavigation.allow;
  }
  final base = Uri.tryParse(baseUrl);
  if (base != null &&
      uri.scheme == base.scheme &&
      uri.host == base.host &&
      (uri.path.isEmpty || uri.path == '/') &&
      !uri.hasQuery) {
    return PlayerNavigation.allow;
  }
  if (uri.scheme == 'https' && uri.host.isNotEmpty) {
    return PlayerNavigation.openOutsideAfterGate;
  }
  return PlayerNavigation.block;
}
