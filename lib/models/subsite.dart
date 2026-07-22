import 'dart:collection';

import '../util/json_safe.dart';

class Subsite {
  Subsite({
    required this.id,
    required this.name,
    required Map<String, dynamic> rawJson,
    this.avatar,
  }) : rawJson = UnmodifiableMapView(Map<String, dynamic>.from(rawJson));

  factory Subsite.fromJson(Map<String, dynamic> json) => Subsite(
    id: asInt(json['id']),
    name: asStringOr(json['name']),
    avatar: json['avatar'] is Map ? asMap(json['avatar']) : null,
    rawJson: json,
  );

  final int? id;
  final String name;
  final Map<String, dynamic>? avatar;
  final Map<String, dynamic> rawJson;
}
