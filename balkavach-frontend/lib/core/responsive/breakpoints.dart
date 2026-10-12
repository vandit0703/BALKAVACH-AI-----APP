import 'package:flutter/widgets.dart';

import '../theme/app_spacing.dart';

enum WindowSize {
  compact,
  medium,
  expanded;

  static WindowSize ofWidth(double width) {
    if (width >= 840) return WindowSize.expanded;
    if (width >= 600) return WindowSize.medium;
    return WindowSize.compact;
  }

  static WindowSize of(BuildContext context) =>
      ofWidth(MediaQuery.sizeOf(context).width);

  bool get isCompact => this == WindowSize.compact;

  double get pageMargin =>
      isCompact ? AppSpacing.marginCompact : AppSpacing.marginWide;
}

/// Maximum readable widths for content inside wide windows.
abstract final class ContentWidth {
  static const form = 560.0;
  static const list = 720.0;
  static const wide = 960.0;
}

/// Centres [child], caps its width, and applies page margins.
class ResponsiveContent extends StatelessWidget {
  const ResponsiveContent({
    required this.child,
    this.maxWidth = ContentWidth.list,
    this.padVertical = true,
    super.key,
  });

  final Widget child;
  final double maxWidth;
  final bool padVertical;

  @override
  Widget build(BuildContext context) {
    final margin = WindowSize.of(context).pageMargin;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth + margin * 2),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: margin,
            vertical: padVertical ? AppSpacing.md : 0,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Scrollable page body: safe area, width cap, and bottom breathing room.
class ScrollablePage extends StatelessWidget {
  const ScrollablePage({
    required this.children,
    this.maxWidth = ContentWidth.list,
    this.spacing = AppSpacing.md,
    super.key,
  });

  final List<Widget> children;
  final double maxWidth;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: ResponsiveContent(
          maxWidth: maxWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: spacing,
            children: [
              ...children,
              const SizedBox(height: AppSpacing.md),
            ],
          ),
        ),
      ),
    );
  }
}
