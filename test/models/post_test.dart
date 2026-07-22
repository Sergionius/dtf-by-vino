import 'package:dtf_app/models/block.dart';
import 'package:dtf_app/models/post.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> fullPost() => {
    'id': '42',
    'title': 'Типизированный пост',
    'text': 'Описание',
    'url': 'https://dtf.ru/42',
    'date': 1_700_000_000,
    'author': {
      'id': 7,
      'name': 'Автор',
      'avatar': {
        'data': {'uuid': 'author-avatar'},
      },
    },
    'subsite': {'id': 8, 'name': 'Разработка'},
    'blocks': [
      {
        'type': 'text',
        'data': {'text': '<p>Текст</p>'},
      },
      {
        'type': 'unknown-new-block',
        'data': {'value': true},
      },
    ],
    'counters': {'comments': '3', 'reactions': 5, 'hits': 100, 'favorites': 2},
    'reactions': {
      'reactionId': 1,
      'counters': [
        {'id': 1, 'count': 4},
        {'id': 2, 'count': 1},
      ],
    },
    'isEditorial': true,
    'isFavorited': true,
  };

  test('parses a complete post and coerces safe scalar values', () {
    final post = Post.fromJson(fullPost());

    expect(post.id, 42);
    expect(post.title, 'Типизированный пост');
    expect(post.author?.id, 7);
    expect(post.author?.name, 'Автор');
    expect(post.subsite?.name, 'Разработка');
    expect(post.date, DateTime.fromMillisecondsSinceEpoch(1_700_000_000_000));
    expect(post.counters.comments, 3);
    expect(post.reactions.selectedId, 1);
    expect(post.reactions.counters, hasLength(2));
    expect(post.blocks.first, isA<TextBlock>());
    expect(post.blocks.last, isA<UnsupportedBlock>());
    expect(post.isEditorial, isTrue);
    expect(post.isFavorited, isTrue);
  });

  test('uses safe defaults for a minimal post', () {
    final post = Post.fromJson({'id': 1});

    expect(post.title, isEmpty);
    expect(post.blocks, isEmpty);
    expect(post.author, isNull);
    expect(post.subsite, isNull);
    expect(post.counters.comments, 0);
    expect(post.reactions.counters, isEmpty);
  });

  test('rejects posts without a valid id', () {
    expect(() => Post.fromJson({'title': 'Нет ID'}), throwsFormatException);
    expect(() => Post.fromJson({'id': 0}), throwsFormatException);
  });

  test('exposes immutable collections and an outer raw JSON snapshot', () {
    final json = fullPost();
    final post = Post.fromJson(json);
    json['title'] = 'Изменено снаружи';

    expect(post.rawJson['title'], 'Типизированный пост');
    expect(() => post.blocks.add(const DividerBlock()), throwsUnsupportedError);
    expect(() => post.rawJson['new'] = true, throwsUnsupportedError);
  });

  test('toggles reactions without mutating the previous value', () {
    final post = Post.fromJson(fullPost());

    final switched = post.reactions.toggle(2);
    final removed = switched.toggle(2);

    expect(post.reactions.selectedId, 1);
    expect(post.reactions.counters.first.count, 4);
    expect(switched.selectedId, 2);
    expect(switched.counters.firstWhere((counter) => counter.id == 1).count, 3);
    expect(switched.counters.firstWhere((counter) => counter.id == 2).count, 2);
    expect(removed.selectedId, 0);
    expect(removed.counters.firstWhere((counter) => counter.id == 2).count, 1);
  });

  test('copyWith preserves identity data and replaces optimistic state', () {
    final post = Post.fromJson(fullPost());
    final updated = post.copyWith(
      reactions: post.reactions.toggle(2),
      isFavorited: false,
    );

    expect(updated.id, post.id);
    expect(updated.title, post.title);
    expect(updated.isFavorited, isFalse);
    expect(updated.reactions.selectedId, 2);
    expect(post.isFavorited, isTrue);
    expect(post.reactions.selectedId, 1);
  });
}
