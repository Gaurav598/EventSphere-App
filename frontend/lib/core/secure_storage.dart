import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:frontend/core/constants.dart';
import 'dart:convert';

class SecureStorage {
  static const _storage = FlutterSecureStorage();

  static Future<void> setToken(String token) async {
    await _storage.write(key: Constants.tokenKey, value: token);
  }

  static Future<String?> getToken() async {
    return await _storage.read(key: Constants.tokenKey);
  }

  static Future<void> clearToken() async {
    await _storage.delete(key: Constants.tokenKey);
  }

  static Future<void> cacheTicket(String registrationId, Map<String, dynamic> data) async {
    await _storage.write(key: 'offline_ticket_$registrationId', value: jsonEncode(data));
  }

  static Future<Map<String, dynamic>?> getCachedTicket(String registrationId) async {
    final value = await _storage.read(key: 'offline_ticket_$registrationId');
    if (value == null) return null;
    final decoded = jsonDecode(value);
    return decoded is Map<String, dynamic> ? decoded : null;
  }

  static Future<void> removeCachedTicket(String registrationId) async {
    await _storage.delete(key: 'offline_ticket_$registrationId');
  }
}
