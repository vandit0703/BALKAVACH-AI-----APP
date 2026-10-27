import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app.dart';
import '../core/locale.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../l10n/app_localizations.dart';

/// Where the sidebar switches from a drawer to a persistent column, and from
/// a full column to an icon-only one.
const kSidebarBreakpoint = 900.0;
const kSidebarExtendedBreakpoint = 1200.0;

enum NavGroup { overview, people, missions, learning, system }

/// A section of the panel.
class Section {
  const Section(this.id, this.icon, this.path, this.permission, this.group);

  final String id;
  final IconData icon;
  final String path;
  final String permission;
  final NavGroup group;

  String label(AppLocalizations l10n) => switch (id) {
    'dashboard' => l10n.navDashboard,
    'users' => l10n.navUsers,
    'families' => l10n.navFamilies,
    'missions' => l10n.navMissions,
    'categories' => l10n.navCategories,
    'presets' => l10n.navPresets,
    'rewards' => l10n.navRewards,
    'redemptions' => l10n.navRedemptions,
    'content' => l10n.navContent,
    'youtubeReviews' => l10n.navYoutubeReviews,
    'badges' => l10n.navBadges,
    'settings' => l10n.navSettings,
    _ => l10n.navAudit,
  };
}

String _groupLabel(AppLocalizations l10n, NavGroup group) => switch (group) {
  NavGroup.overview => l10n.navGroupOverview,
  NavGroup.people => l10n.navGroupPeople,
  NavGroup.missions => l10n.navGroupMissions,
  NavGroup.learning => l10n.navGroupLearning,
  NavGroup.system => l10n.navGroupSystem,
};

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
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.lock_outline_rounded,
            size: 40,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 8),
          Text(l10n.noAccess, key: const Key('no-access')),
        ],
      ),
    );
  }
}

/// The product mark: a shield on the brand blue, as in the mobile app.
class BrandMark extends StatelessWidget {
  const BrandMark({this.size = 36, super.key});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Palette.primary, Palette.primaryContainer],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(size * 0.3),
        ),
        child: Icon(
          Icons.shield_rounded,
          color: Colors.white,
          size: size * 0.6,
        ),
      ),
    );
  }
}

/// A language chooser: each language is named in its own script.
class LanguageMenu extends ConsumerWidget {
  const LanguageMenu({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final current = ref.watch(localeProvider).languageCode;
    return PopupMenuButton<String>(
      key: const Key('language.menu'),
      tooltip: l10n.languageTooltip,
      icon: const Icon(Icons.translate_rounded),
      onSelected: (code) => ref.read(localeProvider.notifier).choose(code),
      itemBuilder: (context) => [
        for (final entry in kLanguageNames.entries)
          CheckedPopupMenuItem(
            key: Key('language.${entry.key}'),
            value: entry.key,
            checked: entry.key == current,
            child: Text(entry.value),
          ),
      ],
    );
  }
}

/// Navigation frame: a sidebar on wide screens, an icon column on medium
/// ones, and a drawer on narrow ones.
class AdminShell extends ConsumerWidget {
  const AdminShell({required this.location, required this.child, super.key});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final session = ref.watch(sessionProvider);
    final sections = [
      for (final s in kSections)
        if (session?.can(s.permission) ?? false) s,
    ];
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= kSidebarBreakpoint;
    final extended = width >= kSidebarExtendedBreakpoint;
    final current = sections.where((s) => s.path == location).firstOrNull;

    final account = PopupMenuButton<String>(
      key: const Key('account.menu'),
      tooltip: l10n.accountTooltip,
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
          child: Text(
            l10n.accountRoles((session?.roles ?? const []).join(', ')),
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(value: 'signout', child: Text(l10n.actionSignOut)),
      ],
    );

    final body = SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1280),
          child: Padding(
            padding: EdgeInsets.all(width < 600 ? 16 : 24),
            child: child,
          ),
        ),
      ),
    );

    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            _Sidebar(
              sections: sections,
              location: location,
              extended: extended,
            ),
            Expanded(
              child: Column(
                children: [
                  _TopBar(
                    crumb: current?.label(l10n),
                    actions: [const LanguageMenu(), account],
                  ),
                  Expanded(child: body),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const BrandMark(size: 28),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                current?.label(l10n) ?? l10n.appName,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [const LanguageMenu(), account],
      ),
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                child: Row(
                  children: [
                    const BrandMark(),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        l10n.appName,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    for (final s in sections)
                      _NavTile(
                        section: s,
                        selected: s.path == location,
                        extended: true,
                        onTap: () {
                          Navigator.pop(context);
                          context.go(s.path);
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      body: body,
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.crumb, required this.actions});

  final String? crumb;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Material(
      color: scheme.surfaceContainerLowest,
      child: Container(
        height: 60,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
        ),
        child: Row(
          children: [
            Semantics(
              label: l10n.breadcrumbLabel,
              child: Row(
                children: [
                  Text(
                    l10n.appName,
                    style: text.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  if (crumb != null) ...[
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                    Text(crumb!, style: text.titleSmall),
                  ],
                ],
              ),
            ),
            const Spacer(),
            ...actions,
          ],
        ),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.sections,
    required this.location,
    required this.extended,
  });

  final List<Section> sections;
  final String location;
  final bool extended;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    NavGroup? last;
    final items = <Widget>[];
    for (final s in sections) {
      if (extended && s.group != last) {
        items.add(
          Padding(
            padding: EdgeInsets.fromLTRB(12, last == null ? 0 : 16, 12, 4),
            child: Text(
              _groupLabel(l10n, s.group).toUpperCase(),
              style: text.labelSmall?.copyWith(color: scheme.outline),
            ),
          ),
        );
      } else if (!extended && last != null && s.group != last) {
        items.add(const Divider(height: 16));
      }
      last = s.group;
      items.add(
        _NavTile(
          section: s,
          selected: s.path == location,
          extended: extended,
          onTap: () => context.go(s.path),
        ),
      );
    }
    return Container(
      width: extended ? 260 : 76,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        border: Border(right: BorderSide(color: scheme.outlineVariant)),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: extended ? 20 : 0,
                vertical: 16,
              ),
              child: Row(
                mainAxisAlignment: extended
                    ? MainAxisAlignment.start
                    : MainAxisAlignment.center,
                children: [
                  const BrandMark(),
                  if (extended) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(l10n.appName, style: text.titleMedium),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: items,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.section,
    required this.selected,
    required this.extended,
    required this.onTap,
  });

  final Section section;
  final bool selected;
  final bool extended;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final label = section.label(l10n);
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;
    final tile = Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: selected ? scheme.primaryFixed : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          key: Key('nav.${section.path}'),
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: extended ? 12 : 0,
              vertical: 11,
            ),
            child: Row(
              mainAxisAlignment: extended
                  ? MainAxisAlignment.start
                  : MainAxisAlignment.center,
              children: [
                Icon(section.icon, color: color, size: 22),
                if (extended) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: color,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    return Semantics(
      selected: selected,
      label: label,
      child: extended ? tile : Tooltip(message: label, child: tile),
    );
  }
}
