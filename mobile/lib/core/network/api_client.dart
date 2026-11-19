/// Network layer — Dio API client with interceptors.
library aph_mobile.core.network;

import 'package:dio/dio.dart';
import 'package:aph_mobile/core/config/app_config.dart';

/// Configured Dio client pointing at the APH backend API.
class ApiClient {
  ApiClient._();

  static final Dio _dio = Dio(
    BaseOptions(
      baseUrl: AppConfig.apiBaseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
    ),
  );

  static Dio get instance => _dio;

  /// Adds an auth interceptor that injects the Supabase access token.
  static void addAuthInterceptor(String Function() getToken) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final token = getToken();
          if (token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          return handler.next(options);
        },
      ),
    );
  }
}
