import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../api/api_config.dart';
import 'api_client.dart';
import 'app_failure.dart';
import 'result.dart';

class HttpApiClient implements ApiClient {
  HttpApiClient(
    this._client,
    this._tokenProvider, [
    this._timeout = ApiConfig.timeout,
  ]);

  final http.Client _client;
  final String? Function() _tokenProvider;
  final Duration _timeout;

  @override
  Future<Result<Object?>> get(String path, {String? apiVersion}) async {
    try {
      final headers = <String, String>{'User-Agent': ApiConfig.userAgent};
      final token = _tokenProvider();
      if (token != null && token.isNotEmpty) {
        headers['X-Device-Token'] = token;
      }

      final response = await _client
          .get(
            ApiConfig.url(path, version: apiVersion ?? ApiConfig.vDefault),
            headers: headers,
          )
          .timeout(_timeout);

      if (response.statusCode == 401 || response.statusCode == 403) {
        return const Failure(UnauthorizedFailure());
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return Failure(
          ServerFailure(
            statusCode: response.statusCode,
            message: _serverMessage(response),
          ),
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map || !decoded.containsKey('result')) {
        return const Failure(ParsingFailure());
      }
      return Success(decoded['result']);
    } on TimeoutException {
      return const Failure(TimeoutFailure());
    } on SocketException {
      return const Failure(NetworkFailure());
    } on http.ClientException {
      return const Failure(NetworkFailure());
    } on FormatException {
      return const Failure(ParsingFailure());
    } catch (_) {
      return const Failure(UnknownFailure());
    }
  }

  String _serverMessage(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) {
        final message = decoded['message'];
        if (message is String && message.isNotEmpty) return message;
        final error = decoded['error'];
        if (error is Map) {
          final nestedMessage = error['message'];
          if (nestedMessage is String && nestedMessage.isNotEmpty) {
            return nestedMessage;
          }
        }
      }
    } catch (_) {
      // Fall back to the status code when the error body is not JSON.
    }
    return 'HTTP ${response.statusCode}';
  }

  @override
  void close() => _client.close();
}
