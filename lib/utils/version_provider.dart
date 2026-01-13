import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

class VersionProvider {
  static const platform = MethodChannel('com.aicon.hireiq/version');

  static Future<String> getAppVersion() async {
    try {
      final String version = await platform.invokeMethod('getAppVersion');
      return version;
    } on PlatformException catch (e) {
      debugPrint('Failed to get app version: ${e.message}');
      return 'Unknown';
    }
  }
}
