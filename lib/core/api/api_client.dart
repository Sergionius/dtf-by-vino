import 'result.dart';

abstract interface class ApiClient {
  Future<Result<Object?>> get(String path, {String? apiVersion});

  void close();
}
