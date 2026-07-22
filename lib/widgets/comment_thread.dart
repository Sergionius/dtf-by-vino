import 'package:flutter/material.dart';
import 'comment_widget.dart';

/// A comment prepared for rendering as one lazy sliver child.
class VisibleComment {
  final dynamic comment;
  final int depth;
  final int loadedDescendantCount;
  final bool hasChildren;

  const VisibleComment({
    required this.comment,
    required this.depth,
    required this.loadedDescendantCount,
    required this.hasChildren,
  });
}

/// Precomputed tree metadata for a flat API comment list.
///
/// Building descendant counts once avoids the old recursive count from every
/// rendered node, while [flatten] makes every visible comment its own sliver
/// child instead of eagerly rendering a whole root branch in one Column.
class CommentTreeIndex {
  final List<dynamic> roots;
  final Map<int, dynamic> byId;
  final Map<int, List<dynamic>> childrenByParent;
  final Map<int, int> descendantCounts;

  const CommentTreeIndex._({
    required this.roots,
    required this.byId,
    required this.childrenByParent,
    required this.descendantCounts,
  });

  factory CommentTreeIndex.fromComments(List<dynamic> comments) {
    final byId = <int, dynamic>{};
    for (final comment in comments) {
      final id = comment['id'] as int?;
      if (id != null) byId[id] = comment;
    }

    final roots = <dynamic>[];
    final childrenByParent = <int, List<dynamic>>{};
    for (final comment in comments) {
      final replyTo = (comment['replyTo'] ?? 0) as int;
      if (replyTo == 0 || !byId.containsKey(replyTo)) {
        roots.add(comment);
      } else {
        (childrenByParent[replyTo] ??= []).add(comment);
      }
    }

    final descendantCounts = <int, int>{};
    final visiting = <int>{};

    int countDescendants(int id) {
      final cached = descendantCounts[id];
      if (cached != null) return cached;
      if (!visiting.add(id)) return 0;

      var count = 0;
      for (final child in childrenByParent[id] ?? const []) {
        count++;
        final childId = child['id'] as int?;
        if (childId != null) count += countDescendants(childId);
      }

      visiting.remove(id);
      descendantCounts[id] = count;
      return count;
    }

    for (final id in byId.keys) {
      countDescendants(id);
    }

    return CommentTreeIndex._(
      roots: roots,
      byId: byId,
      childrenByParent: childrenByParent,
      descendantCounts: descendantCounts,
    );
  }

  List<VisibleComment> flatten({
    Set<int> collapsedIds = const {},
    int? promoteCommentId,
  }) {
    final orderedRoots = List<dynamic>.from(roots);
    if (promoteCommentId != null) {
      final rootId = _rootIdFor(promoteCommentId);
      final index = orderedRoots.indexWhere((root) => root['id'] == rootId);
      if (index > 0) orderedRoots.insert(0, orderedRoots.removeAt(index));
    }

    final visible = <VisibleComment>[];
    final visited = <int>{};

    void append(dynamic comment, int depth) {
      final id = comment['id'] as int?;
      if (id == null || !visited.add(id)) return;
      final children = childrenByParent[id] ?? const [];
      visible.add(
        VisibleComment(
          comment: comment,
          depth: depth,
          loadedDescendantCount: descendantCounts[id] ?? 0,
          hasChildren: children.isNotEmpty,
        ),
      );
      if (collapsedIds.contains(id)) return;
      for (final child in children) {
        append(child, depth + 1);
      }
    }

    for (final root in orderedRoots) {
      append(root, 0);
    }
    return visible;
  }

  int? _rootIdFor(int commentId) {
    dynamic current = byId[commentId];
    if (current == null) return null;

    var guard = 0;
    while ((current['replyTo'] ?? 0) != 0 && guard++ < 100) {
      final parent = byId[current['replyTo']];
      if (parent == null) break;
      current = parent;
    }
    return current['id'] as int?;
  }
}

/// One comment row in the lazy sliver, including its optional "show replies"
/// action and target highlight.
class CommentRow extends StatefulWidget {
  final VisibleComment row;
  final void Function(int commentId, String authorName)? onReply;
  final VoidCallback? onReactionChanged;
  final VoidCallback? onToggleCollapse;
  final bool branchCollapsed;
  final Future<void> Function(String threadId)? onLoadThread;
  final Set<String> loadingThreadIds;
  final int? highlightCommentId;
  final GlobalKey? highlightKey;

  const CommentRow({
    super.key,
    required this.row,
    this.onReply,
    this.onReactionChanged,
    this.onToggleCollapse,
    this.branchCollapsed = false,
    this.onLoadThread,
    required this.loadingThreadIds,
    this.highlightCommentId,
    this.highlightKey,
  });

  @override
  State<CommentRow> createState() => _CommentRowState();
}

class _CommentRowState extends State<CommentRow> {
  bool _highlight = false;

  int get _id => widget.row.comment['id'] as int? ?? -1;

  @override
  void initState() {
    super.initState();
    if (_id == widget.highlightCommentId) {
      _highlight = true;
      Future.delayed(const Duration(milliseconds: 2600), () {
        if (mounted) setState(() => _highlight = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final comment = widget.row.comment;
    final threadId = comment['threadId']?.toString();
    final replyCount = (comment['replyCount'] ?? 0) as int;
    final missing = replyCount - widget.row.loadedDescendantCount;
    final isLoading =
        threadId != null && widget.loadingThreadIds.contains(threadId);
    final isTarget = _id == widget.highlightCommentId;
    final accent = Theme.of(context).colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedContainer(
          key: isTarget ? widget.highlightKey : null,
          duration: const Duration(milliseconds: 500),
          decoration: BoxDecoration(
            color: _highlight
                ? accent.withValues(alpha: 0.14)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: CommentWidget(
            key: ValueKey(_id),
            comment: comment,
            depth: widget.row.depth,
            onReactionChanged: widget.onReactionChanged,
            onReply: widget.onReply == null
                ? null
                : () => widget.onReply!(_id, comment['author']?['name'] ?? ''),
            onToggleCollapse: widget.row.hasChildren
                ? widget.onToggleCollapse
                : null,
            branchCollapsed: widget.row.hasChildren
                ? widget.branchCollapsed
                : null,
          ),
        ),
        if (!widget.branchCollapsed &&
            missing > 0 &&
            threadId != null &&
            widget.onLoadThread != null)
          Padding(
            padding: EdgeInsets.only(
              left: (widget.row.depth + 1) * 12.0 + 4,
              top: 2,
              bottom: 8,
            ),
            child: GestureDetector(
              onTap: isLoading ? null : () => widget.onLoadThread!(threadId),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isLoading)
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: accent,
                      ),
                    )
                  else
                    Icon(
                      Icons.subdirectory_arrow_right,
                      size: 15,
                      color: accent,
                    ),
                  const SizedBox(width: 5),
                  Text(
                    isLoading ? 'Загрузка...' : _repliesLabel(missing),
                    style: TextStyle(
                      color: accent,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

String _repliesLabel(int count) {
  final mod10 = count % 10;
  final mod100 = count % 100;
  String word;
  if (mod10 == 1 && mod100 != 11) {
    word = 'ответ';
  } else if (mod10 >= 2 && mod10 <= 4 && (mod100 < 10 || mod100 >= 20)) {
    word = 'ответа';
  } else {
    word = 'ответов';
  }
  return '$count $word';
}
