import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/runtime_config.dart';
import 'core/routing/app_router.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'features/notifications/presentation/push_registration.dart';
import 'features/onboarding/presentation/onboarding_controller.dart';
import 'l10n/app_localizations.dart';

class BalKavachApp extends ConsumerWidget {
  const BalKavachApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(runtimeConfigProvider).value;
    // Keeps this phone's push token registered for whoever is signed in.
    ref.watch(pushRegistrationProvider);
    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      locale: ref.watch(appLocaleProvider),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      routerConfig: ref.watch(appRouterProvider),
      builder: (context, child) => Column(
        children: [
          if (config != null && config.maintenanceEnabled)
            _MaintenanceBanner(message: config.maintenanceMessage),
          Expanded(child: child ?? const SizedBox.shrink()),
        ],
      ),
    );
  }
}

/// Shown on every screen while an administrator has switched maintenance on.
class _MaintenanceBanner extends StatelessWidget {
  const _MaintenanceBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = message.isEmpty
        ? AppLocalizations.of(context).maintenanceDefault
        : message;
    return Material(
      key: const Key('app.maintenance'),
      color: colors.tertiaryFixed,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.build_circle_outlined, color: colors.onTertiaryFixed),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(color: colors.onTertiaryFixed),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
