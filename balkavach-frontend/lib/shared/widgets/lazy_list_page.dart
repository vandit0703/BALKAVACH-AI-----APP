import 'package:flutter/material.dart';

import '../../core/responsive/breakpoints.dart';
import '../../core/theme/app_spacing.dart';

/// Scrollable page with a fixed [header], a lazily built list of items and a
/// [footer]. Long collections only build the rows that are on screen.
///
/// Content is centred and capped at [maxWidth] like `ResponsiveContent`, but
/// expressed as sliver padding so the list stays lazy.
class LazyListPage extends StatelessWidget {
  const LazyListPage({
    required this.header,
    required this.itemCount,
    required this.itemBuilder,
    this.footer = const [],
    this.maxWidth = ContentWidth.list,
    this.spacing = AppSpacing.md,
    super.key,
  });

  final List<Widget> header;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final List<Widget> footer;
  final double maxWidth;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final margin = WindowSize.ofWidth(width).pageMargin;
    final side = ((width - maxWidth) / 2).clamp(margin, double.infinity);
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(side, AppSpacing.md, side, 0),
          sliver: SliverMainAxisGroup(
            slivers: [
              SliverList.list(
                children: [
                  for (final widget in header)
                    Padding(
                      padding: EdgeInsets.only(bottom: spacing),
                      child: widget,
                    ),
                ],
              ),
              SliverList.builder(
                itemCount: itemCount,
                itemBuilder: (context, index) => Padding(
                  padding: EdgeInsets.only(bottom: spacing),
                  child: itemBuilder(context, index),
                ),
              ),
              SliverList.list(
                children: [
                  for (final widget in footer)
                    Padding(
                      padding: EdgeInsets.only(bottom: spacing),
                      child: widget,
                    ),
                ],
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: AppSpacing.md + MediaQuery.paddingOf(context).bottom,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
