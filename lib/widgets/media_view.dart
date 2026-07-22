import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
import '../theme.dart';
import '../util/external_link.dart';
import '../util/gif_video_controller.dart';
import '../util/json_safe.dart';
import '../util/osnova_image.dart';

/// Renders a single Osnova media object: `{type, data: {uuid, width, height,
/// type, isVideo, has_audio}}`. Videos use a static poster and open on tap;
/// real GIF files animate inline through the network image codec.
class MediaView extends StatelessWidget {
  final dynamic media;
  final double maxHeight;

  const MediaView({super.key, required this.media, this.maxHeight = 640});

  @override
  Widget build(BuildContext context) {
    final outerType = media is Map ? media['type']?.toString() : null;
    final data = media is Map ? media['data'] : null;

    if (outerType == 'video' && data is Map && data['uuid'] == null) {
      return _ExternalVideoCard(data: data, maxHeight: maxHeight);
    }

    final uuid = data?['uuid'] as String?;
    if (uuid == null || uuid.isEmpty) return const SizedBox();

    final fileType = (data['type'] ?? '').toString().toLowerCase();
    final hasAudio = data['has_audio'] == true;
    final isMovieFile = outerType == 'movie' || fileType == 'mp4';
    final isGifFile = fileType == 'gif';
    // DTF stores many user-visible GIFs as silent MP4 files. Asking the CDN
    // for `format/gif` returns only one static frame for these objects.
    final isVideoBackedGif = isGifFile &&
        data['isVideo'] == true &&
        !hasAudio &&
        outerType != 'movie';
    final width = (data['width'] as num?)?.toDouble() ?? 1;
    final height = (data['height'] as num?)?.toDouble() ?? 1;
    final aspect = (width > 0 && height > 0) ? width / height : 16 / 9;
    final cdn = OsnovaImage(uuid);

    if (isVideoBackedGif) {
      return _ConstrainedMedia(
        aspect: aspect,
        maxHeight: maxHeight,
        child: GestureDetector(
          onTap: () => _openFullscreenVideo(context, cdn.mp4()),
          child: Stack(
            alignment: Alignment.topLeft,
            children: [
              _InlineGifVideo(
                url: cdn.mp4(),
                previewUrl: cdn.preview(640),
              ),
              _badge('GIF'),
            ],
          ),
        ),
      );
    }

    if (hasAudio || isMovieFile) {
      return _ConstrainedMedia(
        aspect: aspect,
        maxHeight: maxHeight,
        child: GestureDetector(
          onTap: () => _openFullscreenVideo(context, cdn.videoUrl()),
          child: _VideoPoster(previewUrl: cdn.preview(640)),
        ),
      );
    }

    if (isGifFile) {
      return _ConstrainedMedia(
        aspect: aspect,
        maxHeight: maxHeight,
        child: GestureDetector(
          onTap: () => _openFullscreenGif(context, cdn.gif()),
          child: Stack(
            alignment: Alignment.topLeft,
            children: [
              // Decode directly from network bytes. The cache-manager path can
              // collapse animated GIFs to a static frame on some platforms.
              Image.network(
                cdn.gif(),
                fit: BoxFit.cover,
                width: double.infinity,
                gaplessPlayback: true,
                loadingBuilder: (_, child, progress) => progress == null
                    ? child
                    : Container(color: AppColors.bgElevated),
                errorBuilder: (_, _, _) => Container(
                  color: AppColors.bgElevated,
                  child: const Center(
                    child: Icon(Icons.gif_box_outlined, color: Colors.grey),
                  ),
                ),
              ),
              _badge('GIF'),
            ],
          ),
        ),
      );
    }

    return _ConstrainedMedia(
      aspect: aspect,
      maxHeight: maxHeight,
      child: GestureDetector(
        onTap: () => _openFullscreenImage(context, cdn.original()),
        child: CachedNetworkImage(
          imageUrl: cdn.preview(640),
          fit: BoxFit.cover,
          width: double.infinity,
          memCacheWidth: 700,
          placeholder: (_, __) => Container(color: AppColors.bgElevated),
          errorWidget: (_, __, ___) => Container(
            color: AppColors.bgElevated,
            child: const Center(
              child: Icon(Icons.broken_image, color: Colors.grey),
            ),
          ),
        ),
      ),
    );
  }

  void _openFullscreenImage(BuildContext context, String url) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => _FullscreenImage(url: url)));
  }

  void _openFullscreenGif(BuildContext context, String url) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => _FullscreenGif(url: url)));
  }

  void _openFullscreenVideo(BuildContext context, String url) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => _FullscreenVideo(url: url)));
  }
}

Widget _badge(String text) => Container(
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
    );

class _ConstrainedMedia extends StatelessWidget {
  final double aspect;
  final double maxHeight; // generous cap so 8:21 media doesn't span several screens
  final Widget child;
  const _ConstrainedMedia({required this.aspect, required this.maxHeight, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          // Natural height for full-width media in its real aspect ratio.
          double height = width / aspect;
          if (height > maxHeight) height = maxHeight;
          return ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: width,
              height: height,
              child: FittedBox(
                fit: BoxFit.cover,
                clipBehavior: Clip.hardEdge,
                child: SizedBox(
                  width: width,
                  height: width / aspect,
                  child: child,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// DTF's uploader stores many GIFs as silent MP4 files (`isVideo: true`).
/// They still behave as GIFs in the UI: muted, looping and autoplaying.
class _InlineGifVideo extends StatefulWidget {
  final String url;
  final String previewUrl;

  const _InlineGifVideo({required this.url, required this.previewUrl});

  @override
  State<_InlineGifVideo> createState() => _InlineGifVideoState();
}

class _InlineGifVideoState extends State<_InlineGifVideo> {
  VideoPlayerController? _controller;
  bool _ready = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    VideoPlayerController? controller;
    try {
      controller = await createHostedVideoController(widget.url);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      _controller = controller;
      await controller.initialize();
      if (!mounted || controller != _controller) {
        await controller.dispose();
        return;
      }
      await controller.setLooping(true);
      await controller.setVolume(0);
      await controller.play();
      if (mounted) setState(() => _ready = true);
    } catch (_) {      if (mounted && (controller == null || controller == _controller)) {
        setState(() => _failed = true);
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed || !_ready || _controller == null) {
      return _VideoPoster(
        previewUrl: widget.previewUrl,
        showPlayIcon: false,
      );
    }
    return VideoPlayer(_controller!);
  }
}

/// Static poster frame for a video that has sound — no controller spun up
/// inline (would mean playing N videos at once in a feed); tapping opens the
/// fullscreen player where it actually plays, with sound.
class _VideoPoster extends StatelessWidget {
  final String previewUrl;
  final bool showPlayIcon;

  const _VideoPoster({required this.previewUrl, this.showPlayIcon = true});

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        CachedNetworkImage(
          imageUrl: previewUrl,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          memCacheWidth: 700,
          placeholder: (_, __) => Container(color: AppColors.bgElevated),
          errorWidget: (_, __, ___) => Container(color: AppColors.bgElevated),
        ),
        if (showPlayIcon)
          Container(
            decoration: const BoxDecoration(
                color: Colors.black26, shape: BoxShape.circle),
            padding: const EdgeInsets.all(4),
            child: const Icon(Icons.play_arrow, color: Colors.white, size: 40),
          ),
      ],
    );
  }
}

class _FullscreenImage extends StatelessWidget {
  final String url;
  const _FullscreenImage({required this.url});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4,
          child: CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.contain,
            placeholder: (_, __) => const CircularProgressIndicator(),
            errorWidget: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.grey, size: 48),
          ),
        ),
      ),
    );
  }
}

class _FullscreenGif extends StatelessWidget {
  final String url;
  const _FullscreenGif({required this.url});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: Image.network(
          url,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          loadingBuilder: (_, child, progress) => progress == null
              ? child
              : const CircularProgressIndicator(),
          errorBuilder: (_, _, _) => const Icon(
            Icons.broken_image,
            color: Colors.grey,
            size: 48,
          ),
        ),
      ),
    );
  }
}

/// Fullscreen video player. Stays portrait regardless of the video's own
/// aspect ratio (the app is locked to portrait — see main.dart) — a 16:9
/// video is letterboxed via BoxFit.contain, never rotated to landscape.
class _FullscreenVideo extends StatefulWidget {
  final String url;
  const _FullscreenVideo({required this.url});

  @override
  State<_FullscreenVideo> createState() => _FullscreenVideoState();
}

class _FullscreenVideoState extends State<_FullscreenVideo> {
  VideoPlayerController? _controller;
  bool _ready = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    VideoPlayerController? controller;
    try {
      controller = await createHostedVideoController(widget.url);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      _controller = controller;
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(1);
      await controller.play();
      if (mounted) setState(() => _ready = true);
    } catch (_) {      if (mounted && (controller == null || controller == _controller)) {
        setState(() => _failed = true);
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _failed
          ? const Center(child: Icon(Icons.videocam_off, color: Colors.grey, size: 48))
          : !_ready || _controller == null
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    GestureDetector(
                      onTap: () => setState(() =>
                          _controller!.value.isPlaying
                              ? _controller!.pause()
                              : _controller!.play()),
                      child: AspectRatio(
                        aspectRatio: _controller!.value.aspectRatio,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            VideoPlayer(_controller!),
                            if (!_controller!.value.isPlaying)
                              const Icon(Icons.play_circle_fill,
                                  color: Colors.white70, size: 64),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: VideoProgressIndicator(
                        _controller!,
                        allowScrubbing: true,
                        colors: VideoProgressColors(
                          playedColor: Theme.of(context).colorScheme.primary,
                          backgroundColor: const Color(0xFF333333),
                          bufferedColor: const Color(0xFF555555),
                        ),
                      ),
                    ),
                    ValueListenableBuilder<VideoPlayerValue>(
                      valueListenable: _controller!,
                      builder: (_, v, __) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(_fmt(v.position),
                                style: const TextStyle(color: Colors.white54, fontSize: 12)),
                            GestureDetector(
                              onTap: () => setState(() =>
                                  _controller!.value.isPlaying
                                      ? _controller!.pause()
                                      : _controller!.play()),
                              child: Icon(
                                v.isPlaying ? Icons.pause : Icons.play_arrow,
                                color: Colors.white,
                                size: 28,
                              ),
                            ),
                            Text(_fmt(v.duration),
                                style: const TextStyle(color: Colors.white54, fontSize: 12)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}

/// External video embed (e.g. YouTube) attached to a comment — DTF gives us
/// only a thumbnail + service id, no hosted file. Shows the thumbnail with a
/// play affordance; tapping opens the real video externally.
class _ExternalVideoCard extends StatelessWidget {
  final Map data;
  final double maxHeight;
  const _ExternalVideoCard({required this.data, required this.maxHeight});

  String? get _thumbUuid => digString(data, ['thumbnail', 'data', 'uuid']);

  String? get _url {
    final service = digString(data, ['external_service', 'name']);
    final id = digString(data, ['external_service', 'id']);
    if (service == 'youtube' && id != null && id.isNotEmpty) {
      return 'https://www.youtube.com/watch?v=$id';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final thumb = _thumbUuid;
    if (thumb == null) return const SizedBox();
    final width = (data['width'] as num?)?.toDouble() ?? 1;
    final height = (data['height'] as num?)?.toDouble() ?? 1;
    final aspect = (width > 0 && height > 0) ? width / height : 16 / 9;
    final url = _url;

    return _ConstrainedMedia(
      aspect: aspect,
      maxHeight: maxHeight,
      child: GestureDetector(
        onTap: url != null ? () => openExternalUrl(url) : null,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CachedNetworkImage(
              imageUrl: OsnovaImage(thumb).preview(640),
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              memCacheWidth: 700,
              placeholder: (_, __) => Container(color: AppColors.bgElevated),
              errorWidget: (_, __, ___) => Container(color: AppColors.bgElevated),
            ),
            Container(
              decoration: const BoxDecoration(color: Colors.black26, shape: BoxShape.circle),
              padding: const EdgeInsets.all(4),
              child: const Icon(Icons.play_arrow, color: Colors.white, size: 40),
            ),
          ],
        ),
      ),
    );
  }
}
