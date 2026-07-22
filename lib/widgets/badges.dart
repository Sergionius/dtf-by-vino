import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/reactions_registry.dart';
import '../theme.dart';

/// Renders a Plus badge by its id (a UUID). Empty if unknown/none.
class BadgeIcon extends StatelessWidget {
  final String? badgeId;
  final double size;
  const BadgeIcon({super.key, this.badgeId, this.size = 16});

  @override
  Widget build(BuildContext context) {
    if (badgeId == null || badgeId!.isEmpty) return const SizedBox.shrink();
    final staticUuid = ReactionsRegistry.badges[badgeId];
    if (staticUuid == null) return const SizedBox.shrink();
    return CachedNetworkImage(
      imageUrl: ReactionsRegistry.badgeImageUrl(staticUuid, size: (size * 2).round()),
      width: size,
      height: size,
      fit: BoxFit.contain,
      placeholder: (_, _) => SizedBox(width: size, height: size),
      errorWidget: (_, _, _) => const SizedBox.shrink(),
    );
  }
}

/// Shows a Plus user's badge next to their name: the chosen badge image if set,
/// otherwise a 💎 for any Plus user, otherwise nothing. Pass the author/subsite map.
class AuthorBadge extends StatelessWidget {
  final dynamic author;
  final double size;
  const AuthorBadge({super.key, required this.author, this.size = 14});

  @override
  Widget build(BuildContext context) {
    if (author is! Map) return const SizedBox.shrink();
    final badgeId = author['badgeId'];
    if (badgeId is String && badgeId.isNotEmpty && ReactionsRegistry.badges.containsKey(badgeId)) {
      return Padding(
        padding: const EdgeInsets.only(left: 4),
        child: BadgeIcon(badgeId: badgeId, size: size + 2),
      );
    }
    if (author['isPlus'] == true) {
      return Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Text('💎', style: TextStyle(fontSize: size - 2)),
      );
    }
    return const SizedBox.shrink();
  }
}

/// Bottom sheet to pick a Plus badge. Calls [onPick] with the chosen badge id.
void showBadgePicker(BuildContext context, void Function(String badgeId) onPick) {
  final ids = ReactionsRegistry.badgeIds;
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      minChildSize: 0.4,
      builder: (ctx, scrollController) => Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.grey[700], borderRadius: BorderRadius.circular(2)),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('Выбери бейджик',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          Expanded(
            child: ids.isEmpty
                ? const Center(child: Text('Бейджики недоступны', style: TextStyle(color: Colors.grey)))
                : GridView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.all(16),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 5,
                      mainAxisSpacing: 14,
                      crossAxisSpacing: 14,
                    ),
                    itemCount: ids.length,
                    itemBuilder: (_, i) {
                      final id = ids[i];
                      return GestureDetector(
                        onTap: () { Navigator.pop(ctx); onPick(id); },
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppColors.bgElevated,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.all(8),
                          child: BadgeIcon(badgeId: id, size: 40),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    ),
  );
}
