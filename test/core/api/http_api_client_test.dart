import 'dart:io';

import 'package:dtf_app/core/api/app_failure.dart';
import 'package:dtf_app/core/api/http_api_client.dart';
import 'package:dtf_app/core/api/result.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  HttpApiClient createClient(
    Future<http.Response> Function(http.Request request) handler, {
    String? token,
    Duration timeout = const Duration(seconds: 1),
  }) => HttpApiClient(MockClient(handler), () => token, timeout);

  test('returns decoded result and sends authentication headers', () async {
    late http.Request captured;
    final client = createClient((request) async {
      captured = request;
      return http.Response('{"result":{"id":42}}', 200);
    }, token: 'secret-token');

    final result = await client.get('feed?count=10');

    expect(result, isA<Success<Object?>>());
    expect(result.valueOrNull, {'id': 42});
    expect(captured.headers['X-Device-Token'], 'secret-token');
    expect(captured.headers['User-Agent'], isNotEmpty);
    expect(captured.url.path, '/v2.31/feed');
    client.close();
  });

  test('does not send an empty token', () async {
    late http.Request captured;
    final client = createClient((request) async {
      captured = request;
      return http.Response('{"result":null}', 200);
    }, token: '');

    await client.get('feed');

    expect(captured.headers, isNot(contains('X-Device-Token')));
    client.close();
  });

  test('classifies unauthorized responses', () async {
    final client = createClient(
      (_) async => http.Response('{"message":"invalid token"}', 401),
    );

    final result = await client.get('feed');

    expect(result, isA<Failure<Object?>>());
    expect((result as Failure<Object?>).failure, isA<UnauthorizedFailure>());
    client.close();
  });

  test('keeps server status and message', () async {
    final client = createClient(
      (_) async =>
          http.Response('{"error":{"message":"Service unavailable"}}', 503),
    );

    final result = await client.get('feed') as Failure<Object?>;
    final failure = result.failure as ServerFailure;

    expect(failure.statusCode, 503);
    expect(failure.message, 'Service unavailable');
    client.close();
  });

  test(
    'classifies malformed successful responses as parsing failures',
    () async {
      final client = createClient((_) async => http.Response('not json', 200));

      final result = await client.get('feed') as Failure<Object?>;

      expect(result.failure, isA<ParsingFailure>());
      client.close();
    },
  );

  test('classifies request timeouts', () async {
    final client = createClient((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return http.Response('{"result":null}', 200);
    }, timeout: const Duration(milliseconds: 1));

    final result = await client.get('feed') as Failure<Object?>;

    expect(result.failure, isA<TimeoutFailure>());
    client.close();
  });

  test('classifies socket errors as network failures', () async {
    final client = createClient((_) => throw const SocketException('offline'));

    final result = await client.get('feed') as Failure<Object?>;

    expect(result.failure, isA<NetworkFailure>());
    client.close();
  });
}
