import 'package:balkavach_app/features/onboarding/presentation/splash_screen.dart';
import 'package:balkavach_app/shared/widgets/brand_logo.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/harness.dart';

void main() {
  test('the BALKAVACH logo asset is bundled', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final data = await rootBundle.load(brandLogoAsset);
    expect(data.lengthInBytes, greaterThan(0));
  });

  test('the brand label is exactly BALKAVACH', () {
    expect(brandLogoLabel, 'BALKAVACH');
  });

  for (final size in const [
    Size(320, 568),
    Size(393, 852),
    Size(800, 1280),
    Size(568, 320),
  ]) {
    testWidgets('splash shows the logo inside a '
        '${size.width.toInt()}x${size.height.toInt()} window', (tester) async {
      final h = await Harness.create();
      await pumpScreen(
        tester,
        const SplashScreen(),
        overrides: h.overrides,
        size: size,
        settle: false,
      );

      final logo = find.byWidgetPredicate(
        (w) => w is Image && w.semanticLabel == brandLogoLabel,
      );
      expect(logo, findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      // No tagline or "AI" suffix anywhere on the splash.
      expect(find.textContaining('AI'), findsNothing);

      final rect = tester.getRect(logo);
      expect(rect.width, inInclusiveRange(140, 300));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(size.width));
      expect(tester.takeException(), isNull);
    });
  }
}
