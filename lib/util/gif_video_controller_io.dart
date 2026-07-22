import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

final _downloads = <String, Future<File>>{};

/// AVPlayer can fail DNS resolution for leonardo.osnova.io even though the
/// same URL loads through the app's HTTP/image stack. Download the tiny silent
/// MP4 through `http` first and let the native player read a local file.
Future<VideoPlayerController> createGifVideoController(String url) async {
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
      debugPrint('[GifVideoSource][$id] using cached ${file.path}');
    }
    return file;
  }

  if (kDebugMode) debugPrint('[GifVideoSource][$id] downloading $url');
  try {
    final response = await http.get(uri).timeout(const Duration(seconds: 30));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'HTTP ${response.statusCode} while downloading GIF video',
        uri: uri,
      );
    }
    final temporary = File('${file.path}.download');
    await temporary.writeAsBytes(response.bodyBytes, flush: true);
    await temporary.rename(file.path);
    if (kDebugMode) {
      debugPrint(
        '[GifVideoSource][$id] downloaded ${response.bodyBytes.length} bytes',
      );
    }
    return file;
  } catch (_) {
    _downloads.remove(url);
    rethrow;
  }
}
