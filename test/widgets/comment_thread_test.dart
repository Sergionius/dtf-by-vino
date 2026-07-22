import 'package:flutter_test/flutter_test.dart';
import 'package:dtf_app/widgets/comment_thread.dart';

void main() {
  group('CommentTreeIndex', () {
    final comments = <dynamic>[
      {'id': 1, 'replyTo': 0},
      {'id': 2, 'replyTo': 1},
      {'id': 3, 'replyTo': 2},
      {'id': 4, 'replyTo': 0},
      {'id': 5, 'replyTo': 999},
    ];

    test('flattens comments with depth and descendant metadata', () {
      final rows = CommentTreeIndex.fromComments(comments).flatten();

      expect(rows.map((row) => row.comment['id']), [1, 2, 3, 4, 5]);
      expect(rows.map((row) => row.depth), [0, 1, 2, 0, 0]);
      expect(rows.map((row) => row.loadedDescendantCount), [2, 1, 0, 0, 0]);
      expect(rows.map((row) => row.hasChildren), [true, true, false, false, false]);
    });

    test('does not include descendants of a collapsed comment', () {
      final rows = CommentTreeIndex.fromComments(comments).flatten(
        collapsedIds: {1},
      );

      expect(rows.map((row) => row.comment['id']), [1, 4, 5]);
      expect(rows.first.loadedDescendantCount, 2);
    });

    test('promotes the root containing a target comment', () {
      final rows = CommentTreeIndex.fromComments(<dynamic>[
        {'id': 4, 'replyTo': 0},
        {'id': 1, 'replyTo': 0},
        {'id': 2, 'replyTo': 1},
        {'id': 3, 'replyTo': 2},
      ]).flatten(promoteCommentId: 3);

      expect(rows.map((row) => row.comment['id']), [1, 2, 3, 4]);
    });

    test('handles cycles without recursively rendering forever', () {
      final rows = CommentTreeIndex.fromComments(<dynamic>[
        {'id': 1, 'replyTo': 2},
        {'id': 2, 'replyTo': 1},
      ]).flatten();

      expect(rows, isEmpty);
    });
  });
}
