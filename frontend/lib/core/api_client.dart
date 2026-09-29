import 'package:dio/dio.dart';
import 'package:frontend/core/constants.dart';
import 'package:frontend/core/secure_storage.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final String? code;

  ApiException({required this.message, this.statusCode, this.code});

  @override
  String toString() => message;
}

class ApiClient {
  late final Dio _dio;
  Future<void> Function()? onUnauthorized;

  ApiClient() {
    _dio = Dio(BaseOptions(
      baseUrl: Constants.baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {
        'Content-Type': 'application/json',
      },
    ));

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await SecureStorage.getToken();
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        return handler.next(options);
      },
      onError: (DioException e, handler) async {
        if (e.response?.statusCode == 401) {
          await SecureStorage.clearToken();
          await onUnauthorized?.call();
        }
        
        String errorMessage = 'An unexpected error occurred';
        String? errorCode;
        
        if (e.response?.data != null) {
          if (e.response!.data is Map) {
            final data = e.response!.data as Map;
            if (data.containsKey('error') && data['error'] is Map) {
              final errorMap = data['error'] as Map;
              errorMessage = errorMap['message'] ?? errorMessage;
              errorCode = errorMap['code'];
              
              if (errorMap.containsKey('details') && errorMap['details'] is List) {
                final details = errorMap['details'] as List;
                if (details.isNotEmpty) {
                  final firstError = details[0];
                  final loc = (firstError['loc'] as List?)?.last ?? 'field';
                  final msg = firstError['msg'] ?? 'Validation error';
                  errorMessage = '$loc: $msg';
                }
              }
            } else if (e.response?.statusCode == 422 && data.containsKey('detail')) {
              // Standard FastAPI Validation Error fallback
              final detail = data['detail'];
              if (detail is List && detail.isNotEmpty) {
                final firstError = detail[0];
                final loc = (firstError['loc'] as List?)?.last ?? 'field';
                final msg = firstError['msg'] ?? 'Validation error';
                errorMessage = '$loc: $msg';
              }
            } else if (data.containsKey('message')) {
               errorMessage = data['message'];
            }
          }
        } else if (e.type == DioExceptionType.connectionTimeout || e.type == DioExceptionType.receiveTimeout) {
          errorMessage = 'Connection timed out';
        }

        return handler.next(DioException(
          requestOptions: e.requestOptions,
          response: e.response,
          type: e.type,
          error: ApiException(
            message: errorMessage,
            statusCode: e.response?.statusCode,
            code: errorCode,
          ),
        ));
      },
    ));
  }

  Dio get dio => _dio;
}
