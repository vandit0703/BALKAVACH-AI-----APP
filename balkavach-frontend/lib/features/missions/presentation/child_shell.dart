import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/responsive/breakpoints.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/brand_header.dart';
import '../../../shared/widgets/buttons.dart';
import '../../companion/presentation/panda_talk_sheet.dart';
import '../../notifications/domain/notification_category.dart';
import '../../notifications/presentation/notification_center_screen.dart';
import 'mission_approval_celebrator.dart';

/// Child-mode frame: brand header with Parent Gate, plus bottom navigation on
/// phones and a navigation rail on wide windows.
class ChildShell extends StatelessWidget {
  const ChildShell({required this.location, required this.child, super.key});

  final String location;
  final Widget child;

  static const _tabs = [
    AppRoutes.childHome,
    AppRoutes.childMissions,
    AppRoutes.childRewards,
    AppRoutes.childGarden,
    AppRoutes.childProfile,
  ];

  int get _index {
    for (var i = _tabs.length - 1; i > 0; i--) {
      if (location.startsWith(_tabs[i])) return i;
    }
    return 0;
  }

  void _go(BuildContext context, int index) => context.go(_tabs[index]);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final expanded = WindowSize.of(context) == WindowSize.expanded;
    final title = [
      l10n.watchTitle,
      l10n.missionsTitle,
      l10n.rewardsTitle,
      l10n.gardenTitle,
      l10n.profileTitle,
    ][_index];
    final destinations = [
      (Icons.home_outlined, Icons.home_rounded, l10n.navHome),
      (
        Icons.rocket_launch_outlined,
        Icons.rocket_launch_rounded,
        l10n.navMissions,
      ),
      (Icons.stars_outlined, Icons.stars_rounded, l10n.navRewards),
      (
        Icons.local_florist_outlined,
        Icons.local_florist_rounded,
        l10n.navGarden,
      ),
      (Icons.person_outline_rounded, Icons.person_rounded, l10n.navProfile),
    ];

    final appBar = AppBar(
      toolbarHeight: 68,
      title: BrandTitle(title: title),
      actions: const [
        PandaTalkButton(),
        NotificationBell(audience: NotificationAudience.child),
        ParentGateButton(),
        SizedBox(width: AppSpacing.sm),
      ],
    );

    if (expanded) {
      return MissionApprovalCelebrator(
        child: Scaffold(
          appBar: appBar,
          body: SafeArea(
            top: false,
            child: Row(
              children: [
                NavigationRail(
                  selectedIndex: _index,
                  onDestinationSelected: (i) => _go(context, i),
                  labelType: NavigationRailLabelType.all,
                  destinations: [
                    for (final (icon, selected, label) in destinations)
                      NavigationRailDestination(
                        icon: Icon(icon),
                        selectedIcon: Icon(selected),
                        label: Text(label),
                      ),
                  ],
                ),
                Expanded(child: child),
              ],
            ),
          ),
        ),
      );
    }

    return MissionApprovalCelebrator(
      child: Scaffold(
        appBar: appBar,
        body: child,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => _go(context, i),
          destinations: [
            for (final (icon, selected, label) in destinations)
              NavigationDestination(
                icon: Icon(icon),
                selectedIcon: Icon(selected),
                label: label,
              ),
          ],
        ),
      ),
    );
  }
}

/// Leaves child mode through the parent sign-in screen (email + password,
/// verified by the server against this child's family). The button itself
/// grants nothing.
class ParentGateButton extends StatelessWidget {
  const ParentGateButton({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Labelled pill (Stitch) when the app bar has room; icon-only on small
    // phones, curved-edge screens or with large text so the title is not crushed.
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final padding = MediaQuery.paddingOf(context);
    final usableWidth = MediaQuery.sizeOf(context).width - padding.horizontal;
    final compact = usableWidth / textScale < 420;
    void open() => context.push(AppRoutes.childParentGate);

    if (compact) {
      return IconButton.filledTonal(
        key: const Key('parentGate'),
        tooltip: l10n.parentGate,
        onPressed: open,
        icon: const Icon(Icons.lock_outline_rounded),
      );
    }
    return SecondaryButton(
      key: const Key('parentGate'),
      dense: true,
      label: l10n.parentGate,
      icon: Icons.lock_outline_rounded,
      onPressed: open,
    );
  }
}
