import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../services/settings_service.dart';
import '../util/json_safe.dart';
import 'api_config.dart';

/// A page of timeline items with pagination cursors.
class FeedPage {
  final List<dynamic> items;
  final int? lastId;
  // Opaque pagination cursor. For the "popular" feed it's a fractional score
  // (e.g. "12668.587636617"), so it must be kept verbatim as a string — parsing
  // it to an int truncated the score and made pagination skip posts / fall back
  // to a different (stale) ordering.
  final String? lastSortingValue;
  const FeedPage(this.items, this.lastId, this.lastSortingValue);
  bool get isEmpty => items.isEmpty;
  static const empty = FeedPage([], null, null);
}

/// Result of a write operation, with a server message on failure.
class ApiResult {
  final bool ok;
  final dynamic data;
  final String? error;
  const ApiResult.success([this.data]) : ok = true, error = null;
  const ApiResult.failure(this.error) : ok = false, data = null;
}

class DtfApi {
  static Map<String, String> _headers(SettingsService settings) {
    final h = <String, String>{'User-Agent': ApiConfig.userAgent};
    // X-Device-Token only. (Sending it as a JWT Bearer breaks every request.)
    if (settings.isLoggedIn) h['X-Device-Token'] = settings.token!;
    return h;
  }

  // --- Core HTTP layer — these NEVER throw and always time out ---

  /// GET that returns `result` (decoded) or null on any failure. Never throws.
  static Future<dynamic> _get(
    String path,
    SettingsService settings, {
    String version = ApiConfig.vDefault,
    bool useDevWebProxy = false,
  }) async {
    try {
      final res = await http
          .get(
            ApiConfig.url(path, version: version, useDevWebProxy: useDevWebProxy),
            headers: _headers(settings),
          )
          .timeout(ApiConfig.timeout);
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        return body is Map ? body['result'] : null;
      }
    } catch (_) {}
    return null;
  }

  /// Multipart POST. Returns ApiResult with the server message on failure.
  static Future<ApiResult> _multipart(
    String path,
    SettingsService settings, {
    String version = ApiConfig.vDefault,
    Map<String, String> fields = const {},
    List<http.MultipartFile> files = const [],
  }) async {
    try {
      final req = http.MultipartRequest('POST', ApiConfig.url(path, version: version));
      req.headers.addAll(_headers(settings));
      req.fields.addAll(fields);
      req.files.addAll(files);
      final res = await http.Response.fromStream(await req.send().timeout(ApiConfig.timeout));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        dynamic result;
        try { result = jsonDecode(res.body)['result']; } catch (_) {}
        return ApiResult.success(result);
      }
      return ApiResult.failure(_serverMessage(res));
    } catch (_) {
      return const ApiResult.failure('Ошибка сети');
    }
  }

  /// Simple form POST returning success/failure. Never throws.
  static Future<ApiResult> _postForm(
    String path,
    SettingsService settings, {
    String version = ApiConfig.vDefault,
    Map<String, String> body = const {},
  }) async {
    try {
      final res = await http
          .post(ApiConfig.url(path, version: version), headers: _headers(settings), body: body)
          .timeout(ApiConfig.timeout);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        dynamic result;
        try { result = jsonDecode(res.body)['result']; } catch (_) {}
        return ApiResult.success(result);
      }
      return ApiResult.failure(_serverMessage(res));
    } catch (_) {
      return const ApiResult.failure('Ошибка сети');
    }
  }

  /// JSON POST (Content-Type: application/json). Some endpoints (e.g. the
  /// messenger and subscription) expect a JSON body, not form fields.
  static Future<ApiResult> _postJson(
    String path,
    SettingsService settings, {
    String version = ApiConfig.vDefault,
    Map<String, dynamic> body = const {},
  }) async {
    try {
      final headers = {..._headers(settings), 'Content-Type': 'application/json'};
      final res = await http
          .post(ApiConfig.url(path, version: version),
              headers: headers, body: jsonEncode(body))
          .timeout(ApiConfig.timeout);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        dynamic result;
        try { result = jsonDecode(res.body)['result']; } catch (_) {}
        return ApiResult.success(result);
      }
      return ApiResult.failure(_serverMessage(res));
    } catch (_) {
      return const ApiResult.failure('Ошибка сети');
    }
  }

  static String _serverMessage(http.Response res) {
    try {
      final j = jsonDecode(res.body);
      final m = j['message'] ?? dig(j, ['error', 'message']);
      if (m is String && m.isNotEmpty) return m;
    } catch (_) {}
    return 'HTTP ${res.statusCode}';
  }

  // [includeNews] false в†’ skip the "news" block (matches the site's main feed).
  static List<dynamic> _unwrapTimeline(dynamic result, {bool includeNews = true}) {
    final items = asList(dig(result, ['items']) ?? (result is Map ? result['items'] : null));
    return items.expand<dynamic>((i) {
      if (i is! Map) return const [];
      if (i['type'] == 'news') {
        return includeNews ? asList(dig(i, ['data', 'news'])) : const [];
      }
      final data = i['data'];
      return data != null ? [data] : const [];
    }).toList();
  }

  static FeedPage _toFeedPage(dynamic result, {bool includeNews = true}) {
    if (result == null) return FeedPage.empty;
    return FeedPage(
      _unwrapTimeline(result, includeNews: includeNews),
      asInt(dig(result, ['lastId'])),
      digString(result, ['lastSortingValue']),
    );
  }

  // --- Feed ---
  static Future<FeedPage> getFeed({
    required SettingsService settings,
    required String type, // 'popular' | 'new' | 'my'
    int? lastId,
    String? lastSortingValue,
  }) async {
    String path = 'feed?pageName=$type&count=${settings.batchSize}';
    if (type == 'new') path += '&sorting=all'; // 'new' requires a sorting param
    if (type == 'my') path += '&sorting=new';
    if (lastId != null) path += '&lastId=$lastId';
    if (lastSortingValue != null) path += '&lastSortingValue=$lastSortingValue';
    return _toFeedPage(await _get(path, settings), includeNews: false);
  }

  // --- Entry (single post) — /content?id= (NOT /entry/{id}) ---
  static Future<dynamic> getEntry(int id, SettingsService settings) =>
      _get('content?id=$id', settings);

  // Editorial "Новости" feed — posts by the site editorial team.
  static Future<FeedPage> getEditorialFeed({
    required SettingsService settings,
    int? lastId,
    String? lastSortingValue,
  }) async {
    String path = 'search/posts?editorial=true&sorting=date&count=${settings.batchSize}';
    if (lastId != null) path += '&lastId=$lastId';
    if (lastSortingValue != null) path += '&lastSortingValue=$lastSortingValue';
    return _toFeedPage(await _get(path, settings, useDevWebProxy: true));
  }

  // --- Comments of an entry (v2.10) ---
  static Future<List<dynamic>> getComments(
    int entryId,
    SettingsService settings, {
    int? lastId,
    String sorting = 'hotness',
    int count = 200,
  }) async {
    final lastParam = lastId != null ? '&lastId=$lastId' : '';
    final firstLoad = lastId == null ? '&firstLoad=true' : '';
    final result = await _get(
      'comments?contentId=$entryId&sorting=$sorting&count=$count$firstLoad$lastParam',
      settings, version: ApiConfig.vComments);
    return asList(dig(result, ['items']));
  }

  /// The single most-popular comment on a post (for the feed preview shown
  /// under high-reaction posts). null if there are none / on any failure.
  static Future<dynamic> getTopComment(int postId, SettingsService settings) async {
    final result = await _get(
        'comments?contentId=$postId&sorting=hotness&count=1',
        settings, version: ApiConfig.vComments);
    final items = asList(dig(result, ['items']));
    return items.isNotEmpty ? items.first : null;
  }

  // Load a full comment thread (all levels) by its threadId hash.
  static Future<List<dynamic>> getThread(int contentId, String threadId, SettingsService settings) async {
    final result = await _get(
      'comments?contentId=$contentId&threadId=$threadId',
      settings, version: ApiConfig.vComments);
    return asList(dig(result, ['items']));
  }

  // --- Add comment — /comment/add (multipart) ---
  static Future<Map<String, dynamic>> addComment({
    required int entryId,
    required String text,
    int? replyTo,
    List<dynamic>? attachments,
    required SettingsService settings,
  }) async {
    if (!settings.isLoggedIn) return {'error': 'Не авторизован'};
    final fields = <String, String>{'id': '$entryId', 'text': text};
    if (replyTo != null && replyTo > 0) fields['reply_to'] = '$replyTo';
    if (attachments != null && attachments.isNotEmpty) {
      fields['attachments'] = jsonEncode(attachments);
    }
    final r = await _multipart('comment/add', settings, fields: fields);
    return r.ok ? {'ok': true, 'comment': r.data} : {'error': r.error};
  }

  // --- Edit own comment — /comment/edit (multipart). Field names confirmed
  // from the official app: comment_id, entry_id, text, attachments. ---
  static Future<Map<String, dynamic>> editComment({
    required int commentId,
    required int entryId,
    required String text,
    List<dynamic>? attachments,
    required SettingsService settings,
  }) async {
    if (!settings.isLoggedIn) return {'error': 'Не авторизован'};
    final fields = <String, String>{
      'comment_id': '$commentId',
      'entry_id': '$entryId',
      'text': text,
    };
    // Preserve existing media on edit (don't wipe it when only text changes).
    if (attachments != null && attachments.isNotEmpty) {
      fields['attachments'] = jsonEncode(attachments);
    }
    // Same version/namespace as comment/add (v2.31), not the reactions API.
    final r = await _multipart('comment/edit', settings, fields: fields);
    return r.ok ? {'ok': true, 'comment': r.data} : {'error': r.error};
  }

  // --- Media upload ---
  static Future<dynamic> extractMediaByUrl(String url, SettingsService settings) async {
    final r = await _postForm('uploader/extract', settings, body: {'url': url});
    final result = r.data;
    if (result is List && result.isNotEmpty && (result[0] as Map?)?['type'] != 'error') {
      return result[0];
    }
    return null;
  }

  static Future<dynamic> uploadMediaFile(String filePath, SettingsService settings) async {
    if (!settings.isLoggedIn) return null;
    try {
      final r = await _multipart('uploader/upload', settings,
          files: [await http.MultipartFile.fromPath('file', filePath)]);
      final result = r.data;
      if (result is List && result.isNotEmpty) return result[0];
      if (result is Map) return result;
    } catch (_) {}
    return null;
  }

  // --- Reactions ---
  static Future<List<dynamic>> getReactionUsers({
    required int id,
    required bool isComment,
    int? reactionId,
    SettingsService? settings,
  }) async {
    if (settings == null) return [];
    final path = isComment ? 'comment' : 'content';
    final rParam = reactionId != null ? '?reaction=$reactionId' : '';
    return _parseReactionUsers(await _get('$path/$id/reactions$rParam', settings));
  }

  static List<dynamic> _parseReactionUsers(dynamic result) {
    final out = <dynamic>[];
    if (result == null) return out;
    final items = result is List ? result : asList(dig(result, ['items']) ?? dig(result, ['reactions']) ?? dig(result, ['users']));
    for (final e in items) {
      if (e is! Map) continue;
      if (e['subsites'] is List) {
        for (final s in e['subsites']) {
          out.add({'subsite': s, 'reactionId': asInt(e['id'] ?? e['reactionId'])});
        }
      } else {
        out.add({
          'subsite': e['subsite'] ?? e['author'] ?? e,
          'reactionId': asInt(e['reactionId'] ?? dig(e, ['reaction', 'id']) ?? e['id']),
        });
      }
    }
    return out;
  }

  // Toggle a reaction. DTF sends bodies as multipart/form-data (FormData), not JSON.
  static Future<Map<String, dynamic>> setReaction({
    required int id,
    required bool isComment,
    required int reactionId,
    required SettingsService settings,
  }) async {
    if (!settings.isLoggedIn) return {'error': 'Не авторизован'};
    final path = isComment ? 'comment' : 'content';
    final r = await _multipart('$path/$id/react', settings, version: ApiConfig.vComments, fields: {
      'type': '$reactionId',
      'referer': isComment ? 'comments' : 'feed',
    });
    return r.ok ? {'ok': true} : {'error': r.error};
  }

  // --- Subsite (user profile) ---
  static Future<dynamic> getSubsite(int id, SettingsService settings) async {
    final result = await _get('subsite?id=$id', settings);
    if (result == null) return null;
    return dig(result, ['subsite']) ?? result;
  }

  static Future<FeedPage> getSubsiteEntries(
    int subsiteId,
    SettingsService settings, {
    String sorting = 'new',
    int? lastId,
    String? lastSortingValue,
  }) async {
    final apiSort = sorting == 'popular' ? 'hotness' : 'new';
    String path = 'timeline?subsitesIds=$subsiteId&sorting=$apiSort&count=20';
    if (lastId != null) path += '&lastId=$lastId';
    if (lastSortingValue != null) path += '&lastSortingValue=$lastSortingValue';
    return _toFeedPage(await _get(path, settings));
  }

  static Future<List<dynamic>> getSubsiteComments(
    int subsiteId,
    SettingsService settings, {
    String sorting = 'date',
    int? lastId,
  }) async {
    String path = 'comments?subsiteId=$subsiteId&sorting=$sorting&count=30';
    if (lastId != null) path += '&lastId=$lastId';
    final result = await _get(path, settings);
    if (result is List) return result;
    return asList(dig(result, ['items']));
  }

  // --- Subscription ---
  // Confirmed from the DTF web client: POST subsite/subscription with a JSON
  // body {id, action: "subscribe"|"unsubscribe", isSubscribedToNotifications}.
  // (The old form-encoded subscribe/toggle guesses never worked.)
  static Future<bool> toggleSubscription(int subsiteId, bool subscribe, SettingsService settings) async {
    if (!settings.isLoggedIn) return false;
    final r = await _postJson('subsite/subscription', settings, body: {
      'id': subsiteId,
      'action': subscribe ? 'subscribe' : 'unsubscribe',
      'isSubscribedToNotifications': false,
    });
    return r.ok;
  }

  // --- Favorites (bookmarks) ---
  static Future<bool> setBadge(String badgeId, SettingsService settings) async {
    if (!settings.isLoggedIn) return false;
    // Field name confirmed from the official app (changeBadge → @Field("badgeId")).
    final r = await _multipart('subscription/changeBadge', settings,
        fields: {'badgeId': badgeId});
    return r.ok;
  }

  static Future<bool> toggleFavorite(int id, int type, bool add, SettingsService settings) async {
    if (!settings.isLoggedIn) return false;
    final r = await _postForm(add ? 'favorite' : 'unfavorite', settings,
        body: {'id': '$id', 'type': '$type'});
    return r.ok;
  }

  // --- Search ---
  static Future<List<dynamic>> searchEntries(String query, SettingsService settings) async {
    final result = await _get('search?query=${Uri.encodeComponent(query)}&section=entries&count=20', settings);
    return asList(dig(result, ['contents'])).map((c) => (c is Map ? c['data'] : null) ?? c).toList();
  }

  // --- Discovery (search landing) ---
  /// Top blogs (subsites). Returns up to 50, each with counters + avatar.
  static Future<List<dynamic>> getTopBlogs(SettingsService settings) async {
    final result = await _get('discovery/blogs', settings);
    if (result is List) return result;
    return asList(dig(result, ['items']));
  }

  /// Most popular comments site-wide. Each item carries `entry` (its post).
  static Future<List<dynamic>> getPopularComments(SettingsService settings) async {
    final result = await _get('comments/popular', settings);
    if (result is List) return result;
    return asList(dig(result, ['items']));
  }

  // --- User ---
  static Future<dynamic> getMe(SettingsService settings) async {
    final result = await _get('subsite/me', settings);
    if (result == null) return null;
    return dig(result, ['subsite']) ?? result;
  }

  static Future<bool> validateToken(String token) async {
    try {
      final res = await http.get(
        ApiConfig.url('subsite/me'),
        headers: {'User-Agent': ApiConfig.userAgent, 'X-Device-Token': token},
      ).timeout(ApiConfig.timeout);
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        return body is Map && body['result'] != null;
      }
    } catch (_) {}
    return false;
  }

  // Email/password login. Lives on a separate API (v3.0) with its own
  // response envelope ({message, code, data} — NOT {result, message} like
  // the rest of this file), confirmed empirically: a bad password returns
  // {"message":"Invalid login or password","code":104,"data":null}.
  //
  // Which field inside `data` holds the usable X-Device-Token on a SUCCESSFUL
  // login isn't confirmed (no test account to log in with) — so every
  // plausible string field is tried against validateToken() in turn, and the
  // first one that actually validates is used. Self-correcting without
  // needing to see a real response body.
  static Future<Map<String, dynamic>> loginWithPassword(String email, String password) async {
    try {
      final res = await http.post(
        Uri.parse('https://api.dtf.ru/v3.0/auth/email/login'),
        headers: {
          'User-Agent': ApiConfig.userAgent,
          'Content-Type': 'application/x-www-form-urlencoded;charset=UTF-8',
        },
        body: {'email': email, 'password': password},
      ).timeout(ApiConfig.timeout);
      final body = jsonDecode(res.body);
      if (body is! Map) return {'error': 'Не удалось войти'};
      final data = body['data'];
      if (res.statusCode < 200 || res.statusCode >= 300 || data == null) {
        return {'error': _friendlyLoginError(body['message']?.toString() ?? 'Не удалось войти')};
      }

      // Capped to 3 + spaced out: the API allows at most 3 req/sec and login
      // attempts specifically may be throttled tighter, so this must not
      // hammer /subsite/me trying every candidate at once.
      final candidates = _tokenCandidates(data).take(3).toList();
      for (var i = 0; i < candidates.length; i++) {
        if (i > 0) await Future.delayed(const Duration(milliseconds: 500));
        if (await validateToken(candidates[i].value)) {
          return {'ok': true, 'token': candidates[i].value};
        }
      }
      if (candidates.isEmpty) return {'error': 'Сервер не вернул токен'};
      final keys = candidates.map((e) => e.key).join(', ');
      return {'error': 'Сервер ответил успехом, но ни одно поле не подошло как токен (поля в ответе: $keys)'};
    } catch (_) {
      return {'error': 'Ошибка сети'};
    }
  }

  static String _friendlyLoginError(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('too many')) {
      return 'Слишком много попыток входа подряд. Подожди минуту-две и попробуй снова.';
    }
    if (lower.contains('invalid login or password') || lower.contains('invalid credentials')) {
      return 'Неверная почта или пароль.';
    }
    return raw;
  }

  // Every string field in the login response long enough to plausibly be a
  // token, ordered by how likely its name is to be the right one. Returns
  // key→value so a failed match can still report field NAMES for debugging
  // without ever exposing the actual secret values.
  static List<MapEntry<String, String>> _tokenCandidates(dynamic data) {
    const preferredLeafNames = [
      'accessToken', 'access_token', 'deviceToken', 'device_token',
      'xDeviceToken', 'x_device_token', 'token', 'authToken', 'sessionToken',
    ];
    final found = <String, String>{};

    void scan(dynamic node, String prefix) {
      if (node is! Map) return;
      for (final e in node.entries) {
        final key = '$prefix${e.key}';
        final v = e.value;
        if (v is String && v.length >= 16) {
          found[key] = v;
        } else if (v is Map) {
          scan(v, '$key.');
        }
      }
    }
    scan(data, '');

    int priority(String key) {
      final leaf = key.contains('.') ? key.split('.').last : key;
      final idx = preferredLeafNames.indexOf(leaf);
      return idx == -1 ? preferredLeafNames.length : idx;
    }

    return found.entries.toList()
      ..sort((a, b) => priority(a.key).compareTo(priority(b.key)));
  }

  // --- Notifications (updates) ---
  // is_read=2 is what the official app sends (GetNotificationsUseCase → "2" for
  // the full list). is_read=1 returned nothing — that was the "no notifications"
  // bug. "2" = all updates (read + unread).
  static Future<List<dynamic>> getNotifications(SettingsService settings, {int? lastId}) async {
    if (!settings.isLoggedIn) return [];
    final lastParam = lastId != null ? '&last_id=$lastId' : '';
    final result = await _get('subsite/me/updates?html=true&is_read=2$lastParam', settings);
    if (result is List) return result;
    return asList(dig(result, ['items']) ?? dig(result, ['updates']));
  }

  /// Unread-notification count for the bell badge. 0 on any failure.
  static Future<int> getNotificationsCount(SettingsService settings) async {
    if (!settings.isLoggedIn) return 0;
    final result = await _get('subsite/me/updates/count', settings);
    final n = result is Map ? asInt(result['count'] ?? result['counter'] ?? result['unread']) : asInt(result);
    return n ?? 0;
  }

  // --- Bookmarks ---
  static Future<List<dynamic>> getBookmarks(SettingsService settings, {String type = 'all', int offset = 0}) async {
    if (!settings.isLoggedIn) return [];
    final result = await _get('bookmarks?type=$type&count=30&offset=$offset', settings);
    if (result is List) return result;
    return asList(dig(result, ['items']));
  }

  // --- Drafts ---
  // MUST be new/posts/drafts (token-gated). The old timeline?pageName=drafts
  // returned 200 even WITHOUT a token — DTF ignores that pageName and serves
  // the public feed, so users saw random strangers' posts as "their drafts".
  static Future<List<dynamic>> getDrafts(SettingsService settings) async {
    if (!settings.isLoggedIn) return [];
    return _unwrapTimeline(
        await _get('new/posts/drafts?offset=0&limit=30&markdown=false', settings));
  }

  // --- Editor ---

  /// Subsites the current user can post to: own profile first, then managed blogs.
  static Future<List<dynamic>> getMySubsites(SettingsService settings) async {
    if (!settings.isLoggedIn) return [];
    final results = await Future.wait([
      getMe(settings),
      _get('subsite/me/blogs', settings),
    ]);
    final own = results[0];
    final extra = asList(results[1] is List
        ? results[1]
        : dig(results[1], ['items']));
    final out = <dynamic>[];
    if (own != null) out.add(own);
    for (final s in extra) {
      if (s is Map && s['id'] != (own as Map?)?['id']) out.add(s);
    }
    return out;
  }

  // ── Messenger (direct messages) — v2.1, base `/m/` ────────────────────────
  // Reverse-engineered from the DTF web client. Auth via the same X-Device-Token
  // as the rest of the app (the web uses JWTAuthorization instead).

  /// One page of the user's direct-message channels (dialogs), newest first.
  static Future<List<dynamic>> getChannels(SettingsService settings,
      {int page = 1}) async {
    final result = await _get('m/channels?page=$page', settings,
        version: ApiConfig.vMessenger);
    return asList(dig(result, ['channels']));
  }

  /// Messages of a channel (oldest→newest). [beforeTime] is a message's
  /// `dtCreated` — pass the oldest loaded one to page older history; '0' = latest.
  static Future<List<dynamic>> getMessages(int channelId, SettingsService settings,
      {String beforeTime = '0'}) async {
    final result = await _get(
        'm/messages?channelId=$channelId&beforeTime=$beforeTime', settings,
        version: ApiConfig.vMessenger);
    return asList(dig(result, ['messages']));
  }

  /// Sends a text message (optionally a reply to [replyToId]).
  static Future<ApiResult> sendMessage({
    required int channelId,
    required String text,
    String? replyToId,
    required SettingsService settings,
  }) async {
    final ts = (DateTime.now().millisecondsSinceEpoch / 1000.0).toStringAsFixed(3);
    final idTmp = DateTime.now().microsecondsSinceEpoch % 1000000000;
    final body = <String, String>{
      'channelId': '$channelId',
      'text': text,
      'media': '[]',
      'idTmp': '$idTmp',
      'ts': ts,
    };
    if (replyToId != null && replyToId.isNotEmpty) body['replyToId'] = replyToId;
    return _postForm('m/send', settings,
        version: ApiConfig.vMessenger, body: body);
  }

  /// Marks a channel read (clears its unread badge). Fire-and-forget.
  static Future<void> markChannelRead(int channelId, SettingsService settings) async {
    await _postForm('m/markAsRead', settings,
        version: ApiConfig.vMessenger, body: {'channelId': '$channelId'});
  }

  /// Creates a draft via `POST editor`, then (optionally) publishes it.
  ///
  /// Confirmed by live diagnostics: multipart part "entry" = the whole DTO as
  /// application/json; a MINIMAL body works (extra default fields like
  /// is_enabled_likes made the server 500), user_id=0 is fine (the server fills
  /// the real author from the token), and the new post id comes back at
  /// `result.entry.id` (NOT result.post.id).
  static Future<Map<String, dynamic>> createEntry({
    required String title,
    required List<Map<String, dynamic>> blocks,
    required int subsiteId,
    required bool isPublished,
    required bool isNsfw,
    required SettingsService settings,
  }) async {
    if (!settings.isLoggedIn) return {'error': 'Не авторизован'};

    final blocksJson =
        blocks.map((b) => {'hidden': false, 'anchor': '', ...b}).toList();
    final payload = {
      'id': 0,
      'title': title,
      'user_id': 0,
      'subsite_id': subsiteId,
      'is_adult': false,
      if (isNsfw) 'is_nsfw': true,
      'entry': {'blocks': blocksJson},
    };

    final req = http.MultipartRequest(
        'POST', ApiConfig.url('editor', version: ApiConfig.vEditor));
    req.headers.addAll(_headers(settings));
    req.files.add(http.MultipartFile.fromBytes(
        'entry', utf8.encode(jsonEncode(payload)),
        contentType: MediaType('application', 'json')));

    http.Response res;
    try {
      res = await http.Response.fromStream(
          await req.send().timeout(ApiConfig.timeout));
    } catch (_) {
      return {'error': 'Ошибка сети'};
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      return {'error': '[${ApiConfig.vEditor}/editor ${res.statusCode}] '
          '${_serverMessage(res)}'};
    }

    // {"result": {"entry": {"id": 12345, ...}}}
    int? postId;
    try {
      final r = jsonDecode(res.body)['result'];
      final raw = r?['entry']?['id'] ?? r?['post']?['id'] ?? r?['id'];
      postId = raw is int ? raw : (raw is num ? raw.toInt() : null);
    } catch (_) {}

    if (postId == null) return {'error': 'Сервер не вернул ID черновика'};
    if (!isPublished) return {'ok': true, 'data': {'id': postId}};

    final pubRes = await _postForm(
        'editor/$postId/publish', settings, version: ApiConfig.vEditor);
    return pubRes.ok
        ? {'ok': true, 'data': {'id': postId}}
        : {'error': 'Черновик создан (id $postId), но публикация не прошла: '
            '${pubRes.error ?? 'неизвестно'}'};
  }
}
