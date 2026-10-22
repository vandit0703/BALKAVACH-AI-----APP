import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/responsive/breakpoints.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/brand_header.dart';
import '../../../shared/widgets/buttons.dart';
import '../../authentication/presentation/session_controller.dart';

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
        ParentGateButton(),
        SizedBox(width: AppSpacing.sm),
      ],
    );

    if (expanded) {
      return Scaffold(
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
      );
    }

    return Scaffold(
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
    );
  }
}

/// Leaves child mode. The backend has no parent PIN (B10), so leaving signs
/// the child out and a parent must sign in again.
class ParentGateButton extends ConsumerWidget {
  const ParentGateButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    // Labelled pill (Stitch) when the app bar has room; icon-only on small
    // phones or with large text so the title is not crushed.
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final compact = MediaQuery.sizeOf(context).width / textScale < 380;
    Future<void> open() async {
      final leave = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.lock_rounded),
          title: Text(l10n.parentGateTitle),
          content: Text(l10n.parentGateBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.parentGateStay),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l10n.parentGateLeave),
            ),
          ],
        ),
      );
      if (leave == true) {
        await ref.read(sessionControllerProvider.notifier).signOut();
      }
    }

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
