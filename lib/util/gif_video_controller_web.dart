import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

Future<VideoPlayerController> createHostedVideoController(String url) async {
  if (kDebugMode) debugPrint('[HostedVideoSource][web] streaming $url');
  return VideoPlayerController.networkUrl(Uri.parse(url));
}
