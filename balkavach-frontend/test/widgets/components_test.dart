import 'package:balkavach_app/core/errors/api_exception.dart';
import 'package:balkavach_app/core/theme/app_colors.dart';
import 'package:balkavach_app/core/theme/app_theme.dart';
import 'package:balkavach_app/l10n/app_localizations.dart';
import 'package:balkavach_app/shared/widgets/buttons.dart';
import 'package:balkavach_app/shared/widgets/gamification.dart';
import 'package:balkavach_app/shared/widgets/shield_logo.dart';
import 'package:balkavach_app/shared/widgets/state_views.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
  MaterialApp(
    theme: buildAppTheme(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: Center(child: child)),
  ),
);

void main() {
  test('theme uses the Stitch palette and brand extension', () {
    final theme = buildAppTheme();
    expect(theme.colorScheme.primary, AppPalette.primary);
    expect(theme.colorScheme.primaryContainer, const Color(0xFF1769E0));
    expect(theme.colorScheme.surface, const Color(0xFFF9F9FF));
    expect(theme.textTheme.headlineMedium?.fontFamily, 'Rubik');
    expect(theme.textTheme.bodyLarge?.fontFamily, 'NunitoSans');
    expect(theme.extension<BalKavachColors>(), isNotNull);
  });

  testWidgets(
    'PrimaryButton calls back, and is inert while loading or disabled',
    (tester) async {
      var taps = 0;
      await _pump(tester, PrimaryButton(label: 'Go', onPressed: () => taps++));
      await tester.tap(find.text('Go'));
      expect(taps, 1);

      await _pump(
        tester,
        PrimaryButton(label: 'Go', loading: true, onPressed: () => taps++),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Go'), findsNothing);
      await tester.tap(find.byType(PrimaryButton));
      expect(taps, 1);

      await _pump(tester, const PrimaryButton(label: 'Go', onPressed: null));
      await tester.tap(find.text('Go'));
      expect(taps, 1);
    },
  );

  testWidgets('child-sized PrimaryButton meets the 56 px child touch target', (
    tester,
  ) async {
    await _pump(
      tester,
      PrimaryButton(label: 'Go', childSized: true, onPressed: () {}),
    );
    expect(
      tester.getSize(find.byType(PrimaryButton)).height,
      greaterThanOrEqualTo(56),
    );
  });

  testWidgets('ShieldLogo paints and is labelled only when asked', (
    tester,
  ) async {
    await _pump(
      tester,
      const ShieldLogo(size: 80, semanticLabel: 'Bal Kavach AI'),
    );
    expect(find.bySemanticsLabel('Bal Kavach AI'), findsOneWidget);
    expect(tester.getSize(find.byType(ShieldLogo)), const Size(80, 80));
  });

  testWidgets('StarPill and StatusChip render their labels', (tester) async {
    await _pump(
      tester,
      const Column(
        children: [
          StarPill(count: 15, prefix: '+'),
          StatusChip(
            label: 'Approved',
            icon: Icons.check,
            background: Colors.green,
            foreground: Colors.white,
          ),
        ],
      ),
    );
    expect(find.text('+15'), findsOneWidget);
    expect(find.text('Approved'), findsOneWidget);
  });

  testWidgets('ErrorView explains the failure and retries', (tester) async {
    var retried = false;
    await _pump(
      tester,
      ErrorView(error: const NetworkException(), onRetry: () => retried = true),
    );
    expect(
      find.text("Can't reach Bal Kavach. Check your internet connection."),
      findsOneWidget,
    );
    await tester.tap(find.text('Try again'));
    expect(retried, isTrue);
  });

  testWidgets('describeError covers timeouts and server errors', (
    tester,
  ) async {
    await _pump(tester, const SizedBox());
    final l10n = AppLocalizations.of(tester.element(find.byType(SizedBox)));
    expect(
      describeError(l10n, const RequestTimeoutException()),
      l10n.errorTimeout,
    );
    expect(
      describeError(l10n, const ServerException(message: 'x', statusCode: 500)),
      l10n.errorServer,
    );
    expect(describeError(l10n, StateError('?')), l10n.errorGeneric);
  });
}
