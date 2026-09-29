import 'package:dio/dio.dart';
import 'package:frontend/features/auth/models/user.dart';

class AuthService {
  final Dio dio;

  AuthService(this.dio);

  Future<Map<String, dynamic>> login(String email, String password) async {
    final response = await dio.post('/auth/login', data: {
      'email': email,
      'password': password,
    });
    return response.data['data'];
  }

  Future<Map<String, dynamic>> register(
    String name,
    String email,
    String password, {
    String role = 'user',
    String? organizerCode,
  }) async {
    final response = await dio.post('/auth/register', data: {
      'name': name,
      'email': email,
      'password': password,
      'role': role,
      if (organizerCode != null && organizerCode.isNotEmpty) 'organizerCode': organizerCode,
    });
    return response.data['data'];
  }

  Future<User> getMe() async {
    final response = await dio.get('/auth/me');
    return User.fromJson(response.data['data']);
  }

  Future<User> updateProfile(String? name, String? currentPassword, String? newPassword) async {
    final data = <String, dynamic>{};
    if (name != null) data['name'] = name;
    if (currentPassword != null) data['currentPassword'] = currentPassword;
    if (newPassword != null) data['newPassword'] = newPassword;

    final response = await dio.put('/auth/me', data: data);
    return User.fromJson(response.data['data']);
  }
}
