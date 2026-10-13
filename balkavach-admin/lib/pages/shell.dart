import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app.dart';
import '../core/session.dart';

/// A section of the panel.
class Section {
  const Section(this.label, this.icon, this.path, this.permission);

  final String label;
  final IconData icon;
  final String path;
  final String permission;
}

/// Shows [child] only to administrators holding [permission]; everyone else
/// sees a clear "no access" page rather than an empty or broken screen.
class Guarded extends ConsumerWidget {
  const Guarded({required this.permission, required this.child, super.key});

  final String permission;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    if (session != null && session.can(permission)) return child;
    return const Center(
      child: Text(
        'Your role does not include access to this section.',
        key: Key('no-access'),
      ),
    );
  }
}

/// Navigation frame: a rail on wide screens, a drawer on narrow ones.
class AdminShell extends ConsumerWidget {
  const AdminShell({required this.location, required this.child, super.key});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final sections = [
      for (final s in kSections)
        if (session?.can(s.permission) ?? false) s,
    ];
    final selected = sections.indexWhere((s) => s.path == location);
    final wide = MediaQuery.sizeOf(context).width >= 900;

    final account = PopupMenuButton<String>(
      key: const Key('account.menu'),
      tooltip: 'Account',
      icon: const Icon(Icons.account_circle_outlined),
      onSelected: (value) {
        if (value == 'signout') ref.read(sessionProvider.notifier).signOut();
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          enabled: false,
          child: Text('${session?.name ?? ''}\n${session?.email ?? ''}'),
        ),
        PopupMenuItem(
          enabled: false,
          child: Text('Roles: ${(session?.roles ?? const []).join(', ')}'),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'signout', child: Text('Sign out')),
      ],
    );

    final body = SafeArea(
      child: Padding(padding: const EdgeInsets.all(20), child: child),
    );

    if (wide) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Bal Kavach Admin'),
          actions: [account],
        ),
        body: Row(
          children: [
            NavigationRail(
              extended: MediaQuery.sizeOf(context).width >= 1200,
              selectedIndex: selected < 0 ? null : selected,
              labelType: MediaQuery.sizeOf(context).width >= 1200
                  ? NavigationRailLabelType.none
                  : NavigationRailLabelType.all,
              onDestinationSelected: (i) => context.go(sections[i].path),
              destinations: [
                for (final s in sections)
                  NavigationRailDestination(
                    icon: Icon(s.icon),
                    label: Text(s.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: body),
          ],
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Bal Kavach Admin'), actions: [account]),
      drawer: Drawer(
        child: SafeArea(
          child: ListView(
            children: [
              for (final s in sections)
                ListTile(
                  key: Key('nav.${s.path}'),
                  leading: Icon(s.icon),
                  title: Text(s.label),
                  selected: s.path == location,
                  onTap: () {
                    Navigator.pop(context);
                    context.go(s.path);
                  },
                ),
            ],
          ),
        ),
      ),
      body: body,
    );
  }
}
