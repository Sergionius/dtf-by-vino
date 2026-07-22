import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../api/dtf_api.dart';
import '../services/settings_service.dart';
import '../services/reactions_registry.dart';
import '../theme.dart';
import 'avatar.dart';
import 'profile_navigation.dart';

/// Negative reactions → the "за шо..." toast instead of "спасибо :)".
/// Real DTF ids: 5 = angry, 7/40 = pepe, 25 = clown, 26 = knife,
/// 28 = down-arrow/dislike, 39 = poop. (id 6 is PIKACHU — a friendly
/// reaction, so it must NOT be here.)
const negativeReactionIds = {5, 7, 25, 26, 28, 39, 40};

/// Renders a DTF reaction as its CDN image (custom reactions are images, not emoji).
/// [animated] uses the animated webp when the reaction has one.
class ReactionIcon extends StatelessWidget {
  final int id;
  final double size;
  final bool animated;
  const ReactionIcon({super.key, required this.id, this.size = 18, this.animated = true});

  @override
  Widget build(BuildContext context) {
    if (animated) {
      final asset = ReactionsRegistry.localAnimatedAsset(id);
      if (asset != null) {
        return Image.asset(asset, width: size, height: size, fit: BoxFit.contain);
      }
    }
    final px = (size * 2).round();
    final url = animated
        ? ReactionsRegistry.animatedUrl(id, size: px)
        : ReactionsRegistry.imageUrl(id, size: px);
    if (url.isEmpty) {
      return SizedBox(
        width: size, height: size,
        child: const Icon(Icons.emoji_emotions_outlined, size: 14, color: Colors.grey),
      );
    }
    return CachedNetworkImage(
      imageUrl: url,
      width: size,
      height: size,
      fit: BoxFit.contain,
      placeholder: (_, _) => SizedBox(width: size, height: size),
      errorWidget: (_, _, _) => SizedBox(
        width: size, height: size,
        child: const Icon(Icons.emoji_emotions_outlined, size: 14, color: Colors.grey),
      ),
    );
  }
}

/// Optimistically applies a reaction toggle to a post/comment `reactions` map
/// (mutates `counters` and `reactionId`), mirroring DTF's own client logic.
/// Returns the reaction id now set (0 if cleared).
int applyReactionToggle(Map reactions, int tappedId) {
  final counters = (reactions['counters'] as List?) ?? [];
  final current = (reactions['reactionId'] as int?) ?? 0;

  void bump(int id, int delta) {
    final idx = counters.indexWhere((c) => c['id'] == id);
    if (idx >= 0) {
      counters[idx]['count'] = ((counters[idx]['count'] as int?) ?? 0) + delta;
      if ((counters[idx]['count'] as int) <= 0) counters.removeAt(idx);
    } else if (delta > 0) {
      counters.add({'id': id, 'count': 1});
    }
  }

  int result;
  if (current == tappedId) {
    bump(tappedId, -1); // un-react
    result = 0;
  } else {
    if (current != 0) bump(current, -1); // switch away from old
    bump(tappedId, 1);
    result = tappedId;
  }
  reactions['reactionId'] = result;
  reactions['counters'] = counters;
  return result;
}

/// Shows the easter-egg "за шо..." toast — only for negative reactions.
void showReactionToast(BuildContext context, int reactionId, {required bool added}) {
  if (!added) return;
  if (!negativeReactionIds.contains(reactionId)) return;
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
    content: Text('за шо...', textAlign: TextAlign.center,
        style: TextStyle(fontSize: 15)),
    duration: Duration(milliseconds: 1400),
    behavior: SnackBarBehavior.floating,
    margin: EdgeInsets.fromLTRB(80, 0, 80, 16),
  ));
}

/// Shows the full reaction palette (all reactions, scrollable — they don't
/// all fit on one screen). Calls [onPick] with the chosen reaction id.
///
/// Order adapts to the user: reactions they use most come first. Ties (and the
/// initial all-zero state) fall back to the curated [pickerOrder], then by id —
/// so before any usage data the layout matches the classic order.
void showReactionPicker(BuildContext context, void Function(int reactionId) onPick) {
  final usage = context.read<SettingsService>().reactionUsage;
  final pickerOrder = ReactionsRegistry.pickerOrder;
  final ids = [...ReactionsRegistry.allIds]
    ..sort((a, b) {
      final ua = usage[a] ?? 0;
      final ub = usage[b] ?? 0;
      if (ua != ub) return ub.compareTo(ua); // more used first
      final ra = pickerOrder.indexOf(a);
      final rb = pickerOrder.indexOf(b);
      final pa = ra == -1 ? 1 << 30 : ra;
      final pb = rb == -1 ? 1 << 30 : rb;
      if (pa != pb) return pa.compareTo(pb); // then curated order
      return a.compareTo(b); // then by id
    });

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      maxChildSize: 0.85,
      minChildSize: 0.35,
      builder: (ctx, scrollController) => SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: AppColors.textMuted,
                  borderRadius: BorderRadius.circular(2)),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Выбери реакцию',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.bold)),
            ),
            Expanded(
              child: GridView.builder(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 5,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                ),
                itemCount: ids.length,
                itemBuilder: (_, i) {
                  final id = ids[i];
                  return PressableScale(
                    onTap: () {
                      Navigator.pop(ctx);
                      onPick(id);
                    },
                    scale: 0.88,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.bgElevated,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      padding: const EdgeInsets.all(8),
                      child: ReactionIcon(id: id, size: 32),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// The round "+" affordance shown at the end of a reaction-chip row, opening
/// the full picker.
class AddReactionButton extends StatelessWidget {
  final void Function(int reactionId) onPick;
  final double size;
  const AddReactionButton(
      {super.key, required this.onPick, this.size = 32});

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: () => showReactionPicker(context, onPick),
      scale: 0.88,
      child: Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          color: AppColors.bgElevated,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child:
            Icon(Icons.add, color: AppColors.textMuted, size: size * 0.55),
      ),
    );
  }
}

/// Shows a bottom sheet listing users who reacted to a post/comment, with search.
void showReactionUsers({
  required BuildContext context,
  required int id,
  required bool isComment,
  required SettingsService settings,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ReactionUsersSheet(
        id: id, isComment: isComment, settings: settings),
  );
}

class _ReactionUsersSheet extends StatefulWidget {
  final int id;
  final bool isComment;
  final SettingsService settings;
  const _ReactionUsersSheet({required this.id, required this.isComment, required this.settings});

  @override
  State<_ReactionUsersSheet> createState() => _ReactionUsersSheetState();
}

/// Press-scale + burst-ray animation for reaction chips.
/// Replaces [PressableScale] for reaction buttons.
class BurstTap extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Color burstColor;
  final double scale;

  const BurstTap({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    required this.burstColor,
    this.scale = 0.90,
  });

  @override
  State<BurstTap> createState() => _BurstTapState();
}

class _BurstTapState extends State<BurstTap>
    with SingleTickerProviderStateMixin {
  late final AnimationController _burst;

  @override
  void initState() {
    super.initState();
    _burst = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );
  }

  @override
  void dispose() {
    _burst.dispose();
    super.dispose();
  }

  void _handleTap() {
    _burst.forward(from: 0);
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: _handleTap,
      onLongPress: widget.onLongPress,
      scale: widget.scale,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          widget.child,
          Positioned.fill(
            child: OverflowBox(
              maxWidth: double.infinity,
              maxHeight: double.infinity,
              child: IgnorePointer(
                child: SizedBox(
                  width: 72,
                  height: 72,
                  child: AnimatedBuilder(
                    animation: _burst,
                    builder: (_, _) {
                      if (_burst.value == 0) return const SizedBox.shrink();
                      return CustomPaint(
                        painter: _BurstPainter(
                          progress: _burst.value,
                          color: widget.burstColor,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BurstPainter extends CustomPainter {
  final double progress;
  final Color color;

  const _BurstPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final center = Offset(size.width / 2, size.height / 2);

    // Rays extend during the first 45% of animation
    final extendT = Curves.easeOut.transform((progress / 0.45).clamp(0.0, 1.0));
    // Rays fade during the last 60%
    final fadeT = Curves.easeIn.transform(((progress - 0.40) / 0.60).clamp(0.0, 1.0));
    final opacity = (1.0 - fadeT).clamp(0.0, 1.0);
    if (opacity <= 0) return;

    // Rays gradually drift outward through the whole animation
    final innerRadius = 15.0 + 8.0 * progress;
    final outerRadius = innerRadius + 11.0 * extendT;
    if (outerRadius <= innerRadius) return;

    final paint = Paint()
      ..color = color.withValues(alpha: opacity)
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < 8; i++) {
      final angle = i * (2 * pi / 8);
      canvas.drawLine(
        Offset(center.dx + cos(angle) * innerRadius,
               center.dy + sin(angle) * innerRadius),
        Offset(center.dx + cos(angle) * outerRadius,
               center.dy + sin(angle) * outerRadius),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_BurstPainter old) =>
      old.progress != progress || old.color != color;
}

class _ReactionUsersSheetState extends State<_ReactionUsersSheet> {
  List<dynamic> _users = [];
  bool _loading = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    DtfApi.getReactionUsers(
      id: widget.id,
      isComment: widget.isComment,
      settings: widget.settings,
    ).then((u) {
      if (mounted) setState(() { _users = u; _loading = false; });
    });
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _query.isEmpty
        ? _users
        : _users.where((u) {
            final name = (u['subsite']?['name'] ?? '').toString().toLowerCase();
            return name.contains(_query.toLowerCase());
          }).toList();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      minChildSize: 0.4,
      builder: (ctx, scrollController) => Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
                color: AppColors.textMuted,
                borderRadius: BorderRadius.circular(2)),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('Реакции',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 16)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              style: const TextStyle(
                  color: AppColors.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Поиск по имени',
                prefixIcon: const Icon(Icons.search,
                    color: AppColors.textMuted, size: 20),
                filled: true,
                fillColor: AppColors.bgElevated,
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : filtered.isEmpty
                    ? Center(
                        child: Text(
                          _users.isEmpty
                              ? 'Список реакций недоступен'
                              : 'Никого не найдено',
                          style: const TextStyle(
                              color: AppColors.textSecondary),
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        itemCount: filtered.length,
                        itemBuilder: (_, i) {
                          final u = filtered[i];
                          final subsite = u['subsite'];
                          final rid = u['reactionId'] as int?;
                          return ListTile(
                            leading: Avatar.fromData(
                                subsite?['avatar'],
                                size: 38),
                            title: Text(
                                subsite?['name'] ?? 'Аноним',
                                style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 14)),
                            trailing: rid != null
                                ? ReactionIcon(id: rid, size: 22)
                                : null,
                            onTap: () {
                              Navigator.pop(context);
                              openUserProfile(context, subsite);
                            },
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
