import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

Future<VideoPlayerController> createGifVideoController(String url) async {
  if (kDebugMode) debugPrint('[GifVideoSource][web] streaming $url');
  return VideoPlayerController.networkUrl(Uri.parse(url));
}
