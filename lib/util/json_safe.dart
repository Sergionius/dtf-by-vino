/// Defensive JSON helpers. The API can change field types or nesting; these
/// never throw — they coerce or return a safe default so the UI degrades
/// gracefully instead of crashing.
library;

int? asInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

int asIntOr(dynamic v, int fallback) => asInt(v) ?? fallback;

String asStringOr(dynamic v, [String fallback = '']) {
  if (v == null) return fallback;
  if (v is String) return v;
  return v.toString();
}

List<dynamic> asList(dynamic v) => v is List ? v : const [];

Map<String, dynamic> asMap(dynamic v) =>
    v is Map ? v.map((k, val) => MapEntry(k.toString(), val)) : const {};

/// Walks a nested map/list path without throwing. Works on `dynamic` (unlike
/// an extension method, which won't resolve on a dynamic receiver).
/// `dig(post, ['author','avatar','data','uuid'])` → value or null.
dynamic dig(dynamic obj, List<Object> path) {
  dynamic cur = obj;
  for (final key in path) {
    if (cur is Map) {
      cur = cur[key];
    } else if (cur is List && key is int && key >= 0 && key < cur.length) {
      cur = cur[key];
    } else {
      return null;
    }
    if (cur == null) return null;
  }
  return cur;
}

String? digString(dynamic obj, List<Object> path) {
  final v = dig(obj, path);
  return v?.toString();
}
