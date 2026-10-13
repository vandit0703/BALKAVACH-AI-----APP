import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';

/// Seam over the platform so the phone's IANA time zone can be faked.
abstract interface class DeviceTimeZone {
  /// An IANA name such as `Asia/Kolkata`, or `null` when unknown.
  Future<String?> current();
}

class PlatformDeviceTimeZone implements DeviceTimeZone {
  const PlatformDeviceTimeZone();

  @override
  Future<String?> current() async {
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      return looksLikeIanaZone(info.identifier) ? info.identifier : null;
    } on Object {
      return null;
    }
  }
}

/// `Area/Location` (or `UTC`): the shape the server accepts.
bool looksLikeIanaZone(String value) =>
    value == 'UTC' ||
    RegExp(r'^[A-Za-z_]+(/[A-Za-z0-9_+\-]+){1,2}$').hasMatch(value);

final deviceTimeZoneProvider = Provider<DeviceTimeZone>(
  (ref) => const PlatformDeviceTimeZone(),
);
