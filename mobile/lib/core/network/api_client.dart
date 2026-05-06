import 'package:dio/dio.dart';

class ApiClient {
  ApiClient({required String baseUrl})
      : _dio = Dio(
          BaseOptions(
            baseUrl: baseUrl,
            connectTimeout: const Duration(seconds: 30),
            receiveTimeout: const Duration(seconds: 30),
            sendTimeout: const Duration(seconds: 30),
            headers: const {'Content-Type': 'application/json'},
          ),
        );

  final Dio _dio;

  Future<Response<dynamic>> get(String path,
      {Map<String, dynamic>? queryParameters, Options? options}) {
    return _dio.get(path, queryParameters: queryParameters, options: options);
  }

  Future<Response<dynamic>> post(String path,
      {Object? data, Options? options}) {
    return _dio.post(path, data: data, options: options);
  }

  Future<Response<dynamic>> put(String path, {Object? data, Options? options}) {
    return _dio.put(path, data: data, options: options);
  }
}
