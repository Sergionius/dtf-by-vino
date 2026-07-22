import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
import '../util/osnova_image.dart';

class Avatar extends StatelessWidget {
  final String? uuid;
  final double size;
  final VoidCallback? onTap;
  final bool animated;

  const Avatar({super.key, this.uuid, required this.size, this.onTap, this.animated = false});

  /// Reads straight from a raw `{type, data: {uuid, type, ...}}` avatar
  /// object (as found on `author`/`subsite`), so call sites don't repeat
  /// the `?['data']?['type'] == 'gif'` check to decide animation.
  factory Avatar.fromData(dynamic avatar, {Key? key, required double size, VoidCallback? onTap}) {
    final data = avatar is Map ? avatar['data'] : null;
    return Avatar(
      key: key,
      uuid: data?['uuid'] as String?,
      size: size,
      onTap: onTap,
      animated: data?['type'] == 'gif',
    );
  }

  @override
  Widget build(BuildContext context) {
    final Widget image;
    if (uuid == null || uuid!.isEmpty) {
      image = _placeholder();
    } else if (animated) {
      // Animated ("gif"-typed) avatars are really short muted videos — the CDN
      // only preserves the motion in the mp4 output.
      image = ClipOval(child: _VideoAvatar(uuid: uuid!, size: size));
    } else {
      image = ClipOval(
        child: CachedNetworkImage(
          imageUrl: OsnovaImage(uuid).avatar(size.round()),
          width: size,
          height: size,
          fit: BoxFit.cover,
          placeholder: (_, _) => _placeholder(),
          errorWidget: (_, _, _) => _placeholder(),
        ),
      );
    }
    if (onTap == null) return image;
    return GestureDetector(onTap: onTap, child: image);
  }

  Widget _placeholder() {
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: const Color(0xFF222222),
      child: Icon(Icons.person, color: Colors.grey, size: size * 0.5),
    );
  }
}

/// Plays a DTF animated avatar (mp4) muted + looping, cropped into a circle.
/// Shows a static first frame (via the gif transform) until the video is ready,
/// so there's never an empty gap.
class _VideoAvatar extends StatefulWidget {
  final String uuid;
  final double size;
  const _VideoAvatar({required this.uuid, required this.size});

  @override
  State<_VideoAvatar> createState() => _VideoAvatarState();
}

class _VideoAvatarState extends State<_VideoAvatar> {
  VideoPlayerController? _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final controller = VideoPlayerController.networkUrl(
        Uri.parse(OsnovaImage(widget.uuid).mp4()));
    _controller = controller;
    try {
      await controller.initialize();
      await controller.setVolume(0);
      await controller.setLooping(true);
      await controller.play();
      if (mounted) setState(() => _ready = true);
    } catch (_) {
      // Fall back to the static frame on any playback error.
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (!_ready || controller == null) {
      // Static first frame while the video loads (or if it fails).
      return Image.network(
        OsnovaImage(widget.uuid).gif(),
        width: widget.size,
        height: widget.size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => _fallback(),
      );
    }
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: controller.value.size.width,
          height: controller.value.size.height,
          child: VideoPlayer(controller),
        ),
      ),
    );
  }

  Widget _fallback() => CircleAvatar(
        radius: widget.size / 2,
        backgroundColor: const Color(0xFF222222),
        child: Icon(Icons.person, color: Colors.grey, size: widget.size * 0.5),
      );
}
