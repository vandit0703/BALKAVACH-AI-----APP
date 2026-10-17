import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/locale.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SharedPreferences? prefs;
  try {
    prefs = await SharedPreferences.getInstance();
  } on Object {
    // Blocked browser storage: the language then lasts for this session only.
  }
  runApp(
    ProviderScope(
      overrides: [languagePrefsProvider.overrideWithValue(prefs)],
      child: const AdminApp(),
    ),
  );
}
