import 'dart:collection';

import '../util/json_safe.dart';

class ReactionCounter {
  const ReactionCounter({required this.id, required this.count});

  factory ReactionCounter.fromJson(Map<String, dynamic> json) =>
      ReactionCounter(
        id: asIntOr(json['id'], 0),
        count: asIntOr(json['count'], 0),
      );

  final int id;
  final int count;

  ReactionCounter copyWith({int? count}) =>
      ReactionCounter(id: id, count: count ?? this.count);
}

class PostReactions {
  PostReactions({
    required this.selectedId,
    required List<ReactionCounter> counters,
  }) : counters = UnmodifiableListView(List<ReactionCounter>.from(counters));

  factory PostReactions.fromJson(Map<String, dynamic> json) => PostReactions(
    selectedId: asIntOr(json['reactionId'], 0),
    counters: asList(json['counters'])
        .whereType<Map>()
        .map((item) => ReactionCounter.fromJson(asMap(item)))
        .where((item) => item.id > 0 && item.count > 0)
        .toList(),
  );

  static final empty = PostReactions(selectedId: 0, counters: const []);

  final int selectedId;
  final List<ReactionCounter> counters;

  PostReactions toggle(int tappedId) {
    final updated = <int, int>{
      for (final counter in counters) counter.id: counter.count,
    };

    void bump(int id, int delta) {
      final count = (updated[id] ?? 0) + delta;
      if (count > 0) {
        updated[id] = count;
      } else {
        updated.remove(id);
      }
    }

    final nextSelectedId = selectedId == tappedId ? 0 : tappedId;
    if (selectedId != 0) bump(selectedId, -1);
    if (nextSelectedId != 0) bump(nextSelectedId, 1);

    return PostReactions(
      selectedId: nextSelectedId,
      counters: updated.entries
          .map((entry) => ReactionCounter(id: entry.key, count: entry.value))
          .toList(),
    );
  }
}
