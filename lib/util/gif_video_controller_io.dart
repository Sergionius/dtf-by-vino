import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

final _downloads = <String, Future<File>>{};

/// AVPlayer on iOS can fail DNS resolution for leonardo.osnova.io even though
/// the same URL loads through the app's HTTP/image stack. Download through
/// `http` first and let AVPlayer read a local file. Other native platforms can
/// stream the original URL normally.
Future<VideoPlayerController> createHostedVideoController(String url) async {
  if (!Platform.isIOS) {
    if (kDebugMode) debugPrint('[HostedVideoSource][native] streaming $url');
    return VideoPlayerController.networkUrl(Uri.parse(url));
  }
  final file = await _downloads.putIfAbsent(url, () => _download(url));
  return VideoPlayerController.file(file);
}

Future<File> _download(String url) async {
  final uri = Uri.parse(url);
  final id = uri.pathSegments.isEmpty
      ? url.hashCode.toUnsigned(32).toRadixString(16)
      : uri.pathSegments.first;
  final directory = await getTemporaryDirectory();
  final file = File('${directory.path}/dtf_gif_$id.mp4');
  if (await file.exists() && await file.length() > 0) {
    if (kDebugMode) {
      debugPrint('[HostedVideoSource][$id] using cached ${file.path}');
    }
    return file;
  }

  if (kDebugMode) debugPrint('[HostedVideoSource][$id] downloading $url');
  final client = http.Client();
  final temporary = File('${file.path}.download');
  IOSink? sink;
  try {
    if (await temporary.exists()) await temporary.delete();
    final request = http.Request('GET', uri);
    final response =
        await client.send(request).timeout(const Duration(seconds: 30));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'HTTP ${response.statusCode} while downloading video',
        uri: uri,
      );
    }

    final total = response.contentLength ?? 0;
    var received = 0;
    var nextProgress = 0.25;
    sink = temporary.openWrite();
    await for (final chunk
        in response.stream.timeout(const Duration(seconds: 30))) {
      sink.add(chunk);
      received += chunk.length;
      if (kDebugMode && total > 0 && received / total >= nextProgress) {
        debugPrint(
          '[HostedVideoSource][$id] progress '
          '${(received * 100 / total).round()}% ($received/$total)',
        );
        nextProgress += 0.25;
      }
    }
    await sink.flush();
    await sink.close();
    sink = null;
    await temporary.rename(file.path);
    if (kDebugMode) {
      debugPrint('[HostedVideoSource][$id] downloaded $received bytes');
    }
    return file;
  } catch (_) {
    _downloads.remove(url);
    if (sink != null) await sink.close();
    if (await temporary.exists()) await temporary.delete();
    rethrow;
  } finally {
    client.close();
  }
}
