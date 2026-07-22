import 'package:video_player/video_player.dart';

Future<VideoPlayerController> createHostedVideoController(String url) async =>
    VideoPlayerController.networkUrl(Uri.parse(url));
