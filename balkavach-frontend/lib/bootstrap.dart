import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/push/notification_open_source.dart';
import 'core/push/push_token_source.dart';
import 'core/storage/app_preferences.dart';

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  // Push is optional: without a Firebase configuration this is a no-op source.
  final pushSource = await createPushTokenSource();
  runApp(
    ProviderScope(
      overrides: [
        appPreferencesProvider.overrideWithValue(AppPreferences(prefs)),
        pushTokenSourceProvider.overrideWithValue(pushSource),
        if (pushSource.isAvailable)
          notificationOpenSourceProvider.overrideWithValue(
            FirebaseNotificationOpenSource(
              local: pushSource is FirebasePushTokenSource
                  ? pushSource.local
                  : null,
            ),
          ),
      ],
      // Screens offer explicit retry; silent automatic retries would hide
      // auth failures and hammer a sleeping server.
      retry: (_, _) => null,
      child: const BalKavachApp(),
    ),
  );
}
