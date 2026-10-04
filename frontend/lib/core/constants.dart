import 'package:flutter/foundation.dart';
import 'dart:io' show Platform;

class Constants {
  static String get baseUrl {
    if (kIsWeb) {
      return 'http://127.0.0.1:8001/api/v1';
    }
    if (Platform.isAndroid) {
      return 'http://10.0.2.2:8001/api/v1';
    }
    return 'http://127.0.0.1:8001/api/v1';
  }
  static const String tokenKey = 'access_token';
}
