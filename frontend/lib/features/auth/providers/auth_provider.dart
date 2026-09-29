import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/core/secure_storage.dart';
import 'package:frontend/features/auth/models/user.dart';
import 'package:frontend/features/auth/services/auth_service.dart';
import 'package:frontend/core/websocket_service.dart';

class AuthProvider extends ChangeNotifier {
  final AuthService _authService;
  
  User? _user;
  bool _isInitializing = true;
  bool _isLoading = false;
  String? _error;

  AuthProvider(this._authService) {
    checkAuthStatus();
  }

  User? get user => _user;
  bool get isAuthenticated => _user != null;
  bool get isAdmin => _user?.role == 'admin';
  bool get isInitializing => _isInitializing;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> checkAuthStatus() async {
    final token = await SecureStorage.getToken();
    if (token != null) {
      try {
        _user = await _authService.getMe();
        WebSocketService().connect();
      } catch (e) {
        await SecureStorage.clearToken();
        _user = null;
      }
    }
    _isInitializing = false;
    notifyListeners();
  }

  Future<bool> login(String email, String password) async {
    _setLoading(true);
    try {
      final data = await _authService.login(email, password);
      final token = data['accessToken'];
      await SecureStorage.setToken(token);
      _user = await _authService.getMe();
      WebSocketService().connect();
      _setLoading(false);
      return true;
    } catch (e) {
      if (e is DioException && e.error is ApiException) {
        _error = (e.error as ApiException).message;
      } else if (e is DioException && e.response?.data != null) {
        final data = e.response?.data;
        if (data is Map && data['error'] is Map) {
          _error = data['error']['message'];
        } else {
          _error = e.message;
        }
      } else {
        _error = e.toString();
      }
      _setLoading(false);
      return false;
    }
  }

  Future<bool> register(String name, String email, String password, bool isAdmin, {String? organizerCode}) async {
    _setLoading(true);
    try {
      await _authService.register(
        name,
        email,
        password,
        role: isAdmin ? 'admin' : 'user',
        organizerCode: organizerCode,
      );
      _setLoading(false);
      return true;
    } catch (e) {
      if (e is DioException && e.error is ApiException) {
        _error = (e.error as ApiException).message;
      } else if (e is DioException && e.response?.data != null) {
        final data = e.response?.data;
        if (data is Map && data['error'] is Map) {
          _error = data['error']['message'];
        } else {
          _error = e.message;
        }
      } else {
        _error = e.toString();
      }
      _setLoading(false);
      return false;
    }
  }

  Future<void> logout() async {
    await SecureStorage.clearToken();
    await SecureStorage.clearOfflineTickets();
    _user = null;
    WebSocketService().disconnect();
    notifyListeners();
  }

  Future<void> handleUnauthorized() async {
    if (_user == null) return;
    await SecureStorage.clearToken();
    _user = null;
    WebSocketService().disconnect();
    notifyListeners();
  }

  Future<bool> updateProfile(String? name, String? currentPassword, String? newPassword) async {
    _setLoading(true);
    try {
      _user = await _authService.updateProfile(name, currentPassword, newPassword);
      _setLoading(false);
      return true;
    } catch (e) {
      if (e is DioException && e.error is ApiException) {
        _error = (e.error as ApiException).message;
      } else if (e is DioException && e.response?.data != null) {
        final data = e.response?.data;
        if (data is Map && data['error'] is Map) {
          _error = data['error']['message'];
        } else {
          _error = e.message;
        }
      } else {
        _error = e.toString();
      }
      _setLoading(false);
      return false;
    }
  }

  void _setLoading(bool value) {
    _isLoading = value;
    if (value) _error = null;
    notifyListeners();
  }
}
