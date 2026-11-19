import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records every `SystemChrome.setPreferredOrientations` call a screen makes.
/// Each entry is the list of requested orientations, e.g. `['portraitUp']`;
/// an empty list means "no restriction" (the phone's normal rotation).
class OrientationRecorder {
  OrientationRecorder(WidgetTester tester) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'SystemChrome.setPreferredOrientations') {
          calls.add([
            for (final item in call.arguments as List)
              (item as String).replaceFirst('DeviceOrientation.', ''),
          ]);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
  }

  final calls = <List<String>>[];

  List<String>? get last => calls.isEmpty ? null : calls.last;
}
