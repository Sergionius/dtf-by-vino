import 'dart:collection';

import '../util/json_safe.dart';
import 'block.dart';
import 'reaction.dart';
import 'subsite.dart';
import 'user.dart';

class PostCounters {
  const PostCounters({
    this.comments = 0,
    this.reactions = 0,
    this.hits = 0,
    this.favorites = 0,
  });

  factory PostCounters.fromJson(Map<String, dynamic> json) => PostCounters(
    comments: asIntOr(json['comments'], 0),
    reactions: asIntOr(json['reactions'], 0),
    hits: asIntOr(json['hits'], 0),
    favorites: asIntOr(json['favorites'], 0),
  );

  final int comments;
  final int reactions;
  final int hits;
  final int favorites;
}

class Post {
  Post({
    required this.id,
    required this.title,
    required List<Block> blocks,
    required this.counters,
    required this.reactions,
    required Map<String, dynamic> rawJson,
    this.text,
    this.url,
    this.date,
    this.author,
    this.subsite,
    this.isEditorial = false,
    this.isFavorited = false,
  }) : blocks = UnmodifiableListView(List<Block>.from(blocks)),
       rawJson = UnmodifiableMapView(Map<String, dynamic>.from(rawJson));

  factory Post.fromJson(Map<String, dynamic> json) {
    final id = asInt(json['id']);
    if (id == null || id <= 0) {
      throw const FormatException('Post id is missing or invalid');
    }

    final rawBlocks = asList(json['blocks']);
    return Post(
      id: id,
      title: asStringOr(json['title']),
      text: json['text']?.toString(),
      url: json['url']?.toString(),
      date: _parseDate(json['date']),
      author: _parseUser(json['author']),
      subsite: _parseSubsite(json['subsite']),
      blocks: rawBlocks.map(parseBlock).toList(),
      counters: PostCounters.fromJson(asMap(json['counters'])),
      reactions: PostReactions.fromJson(asMap(json['reactions'])),
      isEditorial: json['isEditorial'] == true,
      isFavorited: json['isFavorited'] == true,
      rawJson: json,
    );
  }

  final int id;
  final String title;
  final String? text;
  final String? url;
  final DateTime? date;
  final User? author;
  final Subsite? subsite;
  final List<Block> blocks;
  final PostCounters counters;
  final PostReactions reactions;
  final bool isEditorial;
  final bool isFavorited;
  final Map<String, dynamic> rawJson;

  Post copyWith({PostReactions? reactions, bool? isFavorited}) => Post(
    id: id,
    title: title,
    text: text,
    url: url,
    date: date,
    author: author,
    subsite: subsite,
    blocks: blocks,
    counters: counters,
    reactions: reactions ?? this.reactions,
    isEditorial: isEditorial,
    isFavorited: isFavorited ?? this.isFavorited,
    rawJson: rawJson,
  );

  static User? _parseUser(dynamic value) {
    if (value is! Map) return null;
    return User.fromJson(asMap(value));
  }

  static Subsite? _parseSubsite(dynamic value) {
    if (value is! Map) return null;
    return Subsite.fromJson(asMap(value));
  }

  static DateTime? _parseDate(dynamic value) {
    final seconds = asInt(value);
    if (seconds != null) {
      return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
    }
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
