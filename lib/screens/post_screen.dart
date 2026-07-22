import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../api/dtf_api.dart';
import '../models/block.dart';
import '../services/settings_service.dart';
import '../services/restorer_service.dart';
import '../theme.dart';
import '../util/osnova_image.dart';
import '../widgets/avatar.dart';
import '../widgets/blocks/block_view.dart';
import '../widgets/comment_thread.dart';
import '../widgets/profile_navigation.dart';
import '../widgets/reactions.dart';
import '../widgets/gif_picker.dart';
import '../widgets/badges.dart';

class PostScreen extends StatefulWidget {
  final int postId;
  final String title;
  final dynamic postData;
  final int? scrollToCommentId; // optional: open straight to a comment
  final bool openToComments; // optional: open straight to the comments section

  const PostScreen({
    super.key,
    required this.postId,
    required this.title,
    this.postData,
    this.scrollToCommentId,
    this.openToComments = false,
  });

  @override
  State<PostScreen> createState() => _PostScreenState();
}

class _PostScreenState extends State<PostScreen> {
  dynamic _post;
  List<dynamic> _comments = [];
  bool _loadingPost = true;
  bool _loadingComments = true;
  String _commentSort = 'hotness'; // 'hotness' (popular) | 'date' (new)
  final _scrollController = ScrollController();
  final _commentsKey = GlobalKey(); // for scrolling to the comments section
  final _targetCommentKey = GlobalKey(); // for scrolling to a specific comment

  // Comment composer
  final _commentController = TextEditingController();
  final _commentFocus = FocusNode();
  bool _sending = false;
  int? _replyToId;
  String? _replyToName;
  final List<dynamic> _attachments = []; // DTF media objects to attach
  bool _attaching = false;

  @override
  void initState() {
    super.initState();
    if (widget.postData != null) {
      _post = widget.postData;
      _loadingPost = false;
      _fetchComments();
    } else {
      _fetchPost();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SettingsService>().markViewed(widget.postId);
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _commentController.dispose();
    _commentFocus.dispose();
    super.dispose();
  }

  bool _postFailed = false;

  Future<void> _fetchPost() async {
    final settings = context.read<SettingsService>();
    setState(() { _loadingPost = true; _postFailed = false; });
    final data = await DtfApi.getEntry(widget.postId, settings);
    if (!mounted) return;
    setState(() {
      _post = data;
      _loadingPost = false;
      _postFailed = data == null;
    });
    if (data != null) _fetchComments();
  }

  bool _didScrollToComments = false;

  Future<void> _fetchComments() async {
    final settings = context.read<SettingsService>();
    try {
      // Coming from a notification/search → load a wider window so the target
      // comment is more likely to be among the loaded set (it can't be fetched
      // by id — the API only returns pages of a post's comments).
      final list = await DtfApi.getComments(widget.postId, settings,
          sorting: _commentSort,
          count: widget.scrollToCommentId != null ? 500 : 200);
      if (!mounted) return;
      setState(() { _comments = list; _loadingComments = false; });
      // Came from a notification, or tapped "comments" in the feed → jump down once.
      if ((widget.scrollToCommentId != null || widget.openToComments) && !_didScrollToComments) {
        _didScrollToComments = true;
        // If the target is a deep reply that wasn't in the initial load, pull
        // in its branch first so scroll-to can actually reach it.
        if (widget.scrollToCommentId != null &&
            !_comments.any((c) => c['id'] == widget.scrollToCommentId)) {
          await _ensureTargetLoaded(widget.scrollToCommentId!);
        }
        if (!mounted) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToComments();
        });
      }
      _enrichWithArchive(); // restore deleted text + edit history in background
    } catch (_) {
      if (mounted) setState(() => _loadingComments = false);
    }
  }

  // Cached community-archive data, so lazily-loaded thread branches can also
  // be enriched without re-fetching.
  Map<String, dynamic> _archiveComments = const {};
  Map<String, dynamic> _archiveEdits = const {};

  // Best-effort: pull the community archive to restore deleted comments' text
  // and attach edit history. Runs after the DTF comments are already shown.
  Future<void> _enrichWithArchive() async {
    final results = await Future.wait([
      RestorerService.fetchPostComments(widget.postId),
      RestorerService.fetchPostEdits(widget.postId),
    ]);
    if (!mounted) return;
    _archiveComments = results[0];
    _archiveEdits = results[1];
    if (_archiveComments.isEmpty && _archiveEdits.isEmpty) return;
    if (_applyArchive(_comments)) setState(() {});
  }

  /// Applies cached archive data to [list]. Returns true if anything changed.
  /// A comment counts as deleted/hidden when DTF flags it, when its text is the
  /// moderator placeholder, or when it's empty — all of those get restored.
  bool _applyArchive(List<dynamic> list) {
    if (_archiveComments.isEmpty && _archiveEdits.isEmpty) return false;
    var changed = false;
    for (final c in list) {
      if (c is! Map) continue;
      final id = '${c['id']}';
      if (c['_restoredText'] == null && c['_restoredMedia'] == null) {
        final text = (c['text'] ?? '').toString().trim();
        final hasMedia = (c['media'] as List?)?.isNotEmpty ?? false;
        // Mod-deleted comments arrive with a placeholder text (not empty),
        // so detect by flags too — that was the bug that hid restored text.
        final isDeleted = c['isRemoved'] == true ||
            c['isRemovedByModerator'] == true ||
            c['isHiddenByBan'] == true ||
            (text.isEmpty && !hasMedia);
        if (isDeleted && _archiveComments[id] is Map) {
          final data = _archiveComments[id] as Map;
          final rText = (data['text'] ?? '').toString();
          final rMedia = data['media'];
          if (rText.isNotEmpty || (rMedia is List && rMedia.isNotEmpty)) {
            c['_restoredText'] = rText;
            c['_restoredMedia'] = rMedia;
            changed = true;
          }
        }
      }
      if (c['_edits'] == null && _archiveEdits[id] is Map) {
        c['_edits'] = _archiveEdits[id];
        changed = true;
      }
    }
    return changed;
  }

  /// Scrolls down to the target comment (from a notification / search) or, when
  /// there's no specific target, to the comments-section header.
  ///
  /// The post body + comments live in a lazy [CustomScrollView], so slivers
  /// below the viewport aren't built yet and their [GlobalKey] context is null.
  /// A single `ensureVisible` therefore did nothing (it stayed at the top of the
  /// post). Here we step the scroll down until the target sliver gets built and
  /// its context appears, then center it.
  Future<void> _scrollToComments() async {
    final wantTarget = widget.scrollToCommentId != null;

    for (var attempt = 0; attempt < 30; attempt++) {
      if (!mounted || !_scrollController.hasClients) return;

      // If the target comment is already built, centre it and we're done.
      final targetCtx = wantTarget ? _targetCommentKey.currentContext : null;
      if (targetCtx != null) {
        await Scrollable.ensureVisible(targetCtx,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOut,
            alignment: 0.15);
        return;
      }

      // As soon as the comments header is built, jump to it. The target
      // branch is promoted to the top of the list, so it renders right below
      // — no need to crawl through every comment (that caused the old "scroll
      // for 3s then snap back to the comments start" behaviour).
      final headerCtx = _commentsKey.currentContext;
      if (headerCtx != null) {
        await Scrollable.ensureVisible(headerCtx,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            alignment: 0.0);
        if (!wantTarget) return;
        // Give the promoted target a few frames to build, then centre it.
        for (var t = 0; t < 8; t++) {
          if (!mounted) return;
          await Future.delayed(const Duration(milliseconds: 50));
          final tc = _targetCommentKey.currentContext;
          if (tc != null) {
            await Scrollable.ensureVisible(tc,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
                alignment: 0.15);
            return;
          }
        }
        // Target isn't in the loaded set — stay at the comments start rather
        // than scrolling away to the bottom.
        return;
      }

      // Comments section not built yet — advance toward it.
      final pos = _scrollController.position;
      final next = (pos.pixels + pos.viewportDimension * 1.5)
          .clamp(0.0, pos.maxScrollExtent);
      if (next <= pos.pixels + 1) return; // nothing more to scroll
      await _scrollController.animateTo(next,
          duration: const Duration(milliseconds: 90), curve: Curves.easeOut);
      await Future.delayed(const Duration(milliseconds: 30));
    }
  }

  Future<void> _changeCommentSort(String sort) async {
    if (_commentSort == sort) return;
    setState(() { _commentSort = sort; _loadingComments = true; });
    await _fetchComments();
  }

  final Set<String> _loadingThreads = {};

  Future<void> _loadThread(String threadId) async {
    if (_loadingThreads.contains(threadId)) return;
    setState(() => _loadingThreads.add(threadId));
    final settings = context.read<SettingsService>();
    final branch = await DtfApi.getThread(widget.postId, threadId, settings);
    if (!mounted) return;
    setState(() {
      _mergeComments(branch);
      _loadingThreads.remove(threadId);
      _applyArchive(_comments); // restore any deleted comments in this branch
    });
  }

  /// Adds any comments from [incoming] we don't already have. Returns true if
  /// at least one new comment was added.
  bool _mergeComments(List<dynamic> incoming) {
    final existing = {
      for (final c in _comments)
        if (c['id'] is int) c['id'] as int
    };
    var added = false;
    for (final c in incoming) {
      final id = c['id'];
      if (id is int && !existing.contains(id)) {
        _comments.add(c);
        existing.add(id);
        added = true;
      }
    }
    return added;
  }

  // Threads already bulk-loaded while hunting for a notification's target
  // comment, so we don't fetch them twice.
  final Set<String> _autoLoadedThreads = {};

  /// The main /comments call only returns levels 0-1, so a comment linked from
  /// a notification is often a deeper reply that isn't loaded yet (it sits
  /// behind a "show N replies" button — the user sees it as "collapsed"). Here
  /// we load the branches that still have unloaded replies (each identified by
  /// its shared [threadId]) until the target comment appears, so scroll-to can
  /// reach it. Bounded, and stops as soon as the target is found.
  Future<bool> _ensureTargetLoaded(int targetId) async {
    if (_comments.any((c) => c['id'] == targetId)) return true;
    final settings = context.read<SettingsService>();

    // Loaded direct children per comment id (to tell which branches still
    // have replies we haven't fetched).
    final loadedChildren = <int, int>{};
    for (final c in _comments) {
      final rt = (c['replyTo'] ?? 0) as int;
      if (rt != 0) loadedChildren[rt] = (loadedChildren[rt] ?? 0) + 1;
    }
    // Distinct thread ids of branches with still-unloaded replies.
    final threadIds = <String>{};
    for (final c in _comments) {
      final tid = c['threadId']?.toString();
      if (tid == null || tid.isEmpty || _autoLoadedThreads.contains(tid)) {
        continue;
      }
      final rc = (c['replyCount'] ?? 0) as int;
      final loaded = loadedChildren[c['id']] ?? 0;
      if (rc > loaded) threadIds.add(tid);
    }
    if (threadIds.isEmpty) return false;

    const cap = 40; // safety bound for pathologically large threads
    const batch = 8;
    final list = threadIds.take(cap).toList();
    for (var i = 0; i < list.length; i += batch) {
      if (!mounted) return false;
      final slice = list.skip(i).take(batch).toList();
      _autoLoadedThreads.addAll(slice);
      final results = await Future.wait(
          slice.map((t) => DtfApi.getThread(widget.postId, t, settings)));
      if (!mounted) return false;
      var added = false;
      for (final branch in results) {
        if (_mergeComments(branch)) added = true;
      }
      if (added) {
        _applyArchive(_comments);
        setState(() {});
      }
      if (_comments.any((c) => c['id'] == targetId)) return true;
    }
    return _comments.any((c) => c['id'] == targetId);
  }

  void _startReply(int commentId, String name) {
    setState(() { _replyToId = commentId; _replyToName = name; });
    _commentFocus.requestFocus();
  }

  void _cancelReply() {
    setState(() { _replyToId = null; _replyToName = null; });
  }

  Future<void> _sendComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty && _attachments.isEmpty) return;
    final settings = context.read<SettingsService>();
    if (!settings.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Войди в аккаунт, чтобы комментировать'),
            backgroundColor: AppColors.bgElevated),
      );
      return;
    }
    setState(() => _sending = true);
    final result = await DtfApi.addComment(
      entryId: widget.postId,
      text: text,
      replyTo: _replyToId,
      attachments: _attachments.isEmpty ? null : List.of(_attachments),
      settings: settings,
    );
    if (!mounted) return;
    if (result['ok'] == true) {
      _commentController.clear();
      _commentFocus.unfocus();
      setState(() {
        _sending = false;
        _replyToId = null;
        _replyToName = null;
        _attachments.clear();
      });
      await _fetchComments();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Комментарий добавлен'), backgroundColor: AppColors.bgElevated),
      );
    } else {
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось: ${result['error'] ?? 'ошибка'}'),
            backgroundColor: AppColors.bgElevated),
      );
    }
  }

  Future<void> _attachGif() async {
    final settings = context.read<SettingsService>();
    final gif = await showGifPicker(context);
    if (gif == null || !mounted) return;
    setState(() => _attaching = true);
    // Save to recents, then resolve to a DTF media object via uploader.
    await settings.addRecentGif(gif.toJson());
    final media = await DtfApi.extractMediaByUrl(gif.extractUrl, settings);
    if (!mounted) return;
    setState(() {
      _attaching = false;
      if (media != null) {
        _attachments.add(media);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось прикрепить GIF'),
              backgroundColor: AppColors.bgElevated),
        );
      }
    });
  }

  Future<void> _attachFromGallery() async {
    final settings = context.read<SettingsService>();
    if (!settings.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Войди в аккаунт'), backgroundColor: AppColors.bgElevated),
      );
      return;
    }
    final picker = ImagePicker();
    final XFile? file = await picker.pickMedia();
    if (file == null || !mounted) return;
    setState(() => _attaching = true);
    final media = await DtfApi.uploadMediaFile(file.path, settings);
    if (!mounted) return;
    setState(() {
      _attaching = false;
      if (media != null) {
        _attachments.add(media);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось загрузить файл'),
              backgroundColor: AppColors.bgElevated),
        );
      }
    });
  }

  Future<void> _reactToPost(int reactionId) async {
    final settings = context.read<SettingsService>();
    if (!settings.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Войди в аккаунт'), backgroundColor: AppColors.bgElevated),
      );
      return;
    }
    // Optimistic: update counters + my reaction instantly, no page reload.
    final reactions = (_post['reactions'] as Map?) ?? {'counters': [], 'reactionId': 0};
    _post['reactions'] = reactions;
    final snapshot = jsonEncode(reactions); // for exact rollback
    final before = (reactions['reactionId'] as int?) ?? 0;
    final now = applyReactionToggle(reactions, reactionId);
    setState(() {});
    showReactionToast(context, reactionId, added: now != 0 && now != before);

    // Fire the request in the background; restore the snapshot on failure.
    final result = await DtfApi.setReaction(
      id: widget.postId, isComment: false, reactionId: reactionId, settings: settings);
    if (!mounted) return;
    if (result['ok'] != true) {
      _post['reactions'] = jsonDecode(snapshot);
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Реакция: ${result['error'] ?? 'ошибка'}'),
            backgroundColor: AppColors.bgElevated),
      );
    }
  }

  Future<void> _toggleBookmark() async {
    final settings = context.read<SettingsService>();
    if (!settings.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Войди в аккаунт'), backgroundColor: AppColors.bgElevated),
      );
      return;
    }
    final isFav = _post?['isFavorited'] == true;
    final ok = await DtfApi.toggleFavorite(widget.postId, 1, !isFav, settings);
    if (!mounted) return;
    if (ok) {
      setState(() => _post['isFavorited'] = !isFav);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(!isFav ? 'Добавлено в закладки' : 'Убрано из закладок'),
            backgroundColor: AppColors.bgElevated),
      );
    }
  }

  void _showPostMenu() {
    final settings = context.read<SettingsService>();
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.emoji_emotions_outlined, color: Colors.white),
              title: const Text('Реакции', style: TextStyle(color: Colors.white)),
              subtitle: const Text('Кто поставил реакцию на пост',
                  style: TextStyle(color: Colors.grey, fontSize: 12)),
              onTap: () {
                Navigator.pop(ctx);
                showReactionUsers(
                    context: context, id: widget.postId, isComment: false, settings: settings);
              },
            ),
            ListTile(
              leading: const Icon(Icons.add_reaction_outlined, color: Colors.white),
              title: const Text('Поставить реакцию', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                showReactionPicker(context, _reactToPost);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _post?['subsite']?['name'] ?? widget.title,
          style: const TextStyle(fontSize: 15),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: Icon(
              _post?['isFavorited'] == true
                  ? Icons.bookmark
                  : Icons.bookmark_border,
              color: _post?['isFavorited'] == true
                  ? accent
                  : AppColors.textPrimary,
            ),
            onPressed: _toggleBookmark,
          ),
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: _showPostMenu,
          ),
        ],
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 72),
        child: FloatingActionButton.small(
          onPressed: () => _scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOut,
          ),
          backgroundColor: AppColors.bgElevated,
          child: const Icon(Icons.keyboard_arrow_up,
              color: AppColors.textPrimary),
        ),
      ),
      // Composer lives in the body so resizeToAvoidBottomInset lifts it above
      // the keyboard (a bottomNavigationBar would stay hidden behind it).
      body: _loadingPost
          ? const Center(child: CircularProgressIndicator())
          : _postFailed
              ? _buildLoadError()
              : Column(
                  children: [
                    Expanded(
                      child: CustomScrollView(
                        controller: _scrollController,
                        slivers: [
                          SliverToBoxAdapter(child: _buildPostHeader()),
                          const SliverToBoxAdapter(child: Divider(height: 1)),
                          SliverToBoxAdapter(child: _buildPostBody()),
                          SliverToBoxAdapter(child: _buildReactions()),
                          SliverToBoxAdapter(child: _buildStats()),
                          const SliverToBoxAdapter(child: Divider()),
                          SliverToBoxAdapter(child: _buildCommentsHeader()),
                          ..._buildCommentSlivers(),
                          const SliverToBoxAdapter(child: SizedBox(height: 16)),
                        ],
                      ),
                    ),
                    _buildComposer(),
                  ],
                ),
    );
  }

  Widget _buildLoadError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, color: AppColors.textMuted, size: 56),
            const SizedBox(height: 16),
            const Text('Не удалось загрузить пост',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 16)),
            const SizedBox(height: 8),
            const Text('Проверь соединение или попробуй ещё раз',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _fetchPost,
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
              ),
              child: const Text('Повторить'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPostHeader() {
    if (_post == null) return const SizedBox();
    final author = _post['author'];
    final date = _post['date'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Row(children: [
        Avatar.fromData(
          author?['avatar'],
          size: 42,
          onTap: () => openUserProfile(context, author),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            GestureDetector(
              onTap: () => openUserProfile(context, author),
              child: Row(children: [
                Text(author?['name'] ?? '',
                    style: const TextStyle(
                        color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 15)),
                AuthorBadge(author: author, size: 14),
              ]),
            ),
            Text(
              _formatDate(date),
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _buildReactions() {
    if (_post == null) return const SizedBox();
    final myReaction = (_post['reactions']?['reactionId'] as int?) ?? 0;
    final reactions = (_post['reactions']?['counters'] as List? ?? [])
        .where((r) => (r['count'] ?? 0) > 0)
        .toList()
      ..sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));

    final accent = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          ...reactions.map((r) {
            final mine = r['id'] == myReaction;
            return BurstTap(
              onTap: () => _reactToPost(r['id'] as int),
              onLongPress: () => showReactionUsers(
                  context: context,
                  id: widget.postId,
                  isComment: false,
                  settings: context.read<SettingsService>()),
              burstColor: accent,
              scale: 0.90,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: mine
                      ? accent.withValues(alpha: 0.18)
                      : AppColors.bgElevated,
                  borderRadius: BorderRadius.circular(20),
                  border:
                      mine ? Border.all(color: accent, width: 1.5) : null,
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  ReactionIcon(
                    id: r['id'] as int,
                    size: 18,
                    animated: false,
                  ),
                  const SizedBox(width: 6),
                  Text('${r['count']}',
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.bold)),
                ]),
              ),
            );
          }),
          AddReactionButton(onPick: _reactToPost),
        ],
      ),
    );
  }

  Widget _buildStats() {
    if (_post == null) return const SizedBox();
    final counters = _post['counters'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(children: [
        const Icon(Icons.remove_red_eye_outlined, size: 15, color: AppColors.textMuted),
        const SizedBox(width: 4),
        Text('${counters?['hits'] ?? 0}',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
        const SizedBox(width: 16),
        const Icon(Icons.bookmark_border, size: 15, color: AppColors.textMuted),
        const SizedBox(width: 4),
        Text('${counters?['favorites'] ?? 0}',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
        const SizedBox(width: 16),
        const Icon(Icons.chat_bubble_outline, size: 15, color: AppColors.textMuted),
        const SizedBox(width: 4),
        Text('${counters?['comments'] ?? 0}',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
      ]),
    );
  }

  Widget _buildPostBody() {
    final accent = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  height: 1.3),
              children: [
                TextSpan(text: _post?['title'] ?? widget.title),
                if (_post?['isEditorial'] == true) ...[
                  const WidgetSpan(child: SizedBox(width: 6)),
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Icon(Icons.verified, size: 20, color: accent),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          ...(_post?['blocks'] as List? ?? [])
              .map((b) => BlockView(block: parseBlock(b))),
        ],
      ),
    );
  }

  Widget _buildCommentsHeader() {
    return Column(
      key: _commentsKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(children: [
            const Text('Комментарии',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            Text('(${_comments.length})',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 15)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(children: [
            _commentSortChip('Популярные', 'hotness'),
            const SizedBox(width: 8),
            _commentSortChip('Новые', 'date'),
          ]),
        ),
      ],
    );
  }

  // Returns a list of slivers — loading spinner, empty state, or lazy SliverList.
  List<Widget> _buildCommentSlivers() {
    if (_loadingComments) {
      return [
        const SliverToBoxAdapter(
          child: Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
        ),
      ];
    }
    if (_comments.isEmpty) {
      return [
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text('Комментариев нет', style: TextStyle(color: AppColors.textMuted))),
          ),
        ),
      ];
    }
    final tree = CommentThread.buildTree(_comments);
    // When arriving from a notification / search, float the target comment's
    // whole branch to the top so it renders immediately (a lazy SliverList
    // wouldn't have built a deep-down comment yet, breaking scroll-to).
    final roots = widget.scrollToCommentId != null
        ? _promoteTargetRoot(tree.roots, widget.scrollToCommentId!)
        : tree.roots;
    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (ctx, i) => CommentNode(
              comment: roots[i],
              childrenByParent: tree.childrenByParent,
              depth: 0,
              onReply: (id, name) => _startReply(id, name),
              onReactionChanged: _fetchComments,
              onLoadThread: _loadThread,
              loadingThreadIds: _loadingThreads,
              highlightCommentId: widget.scrollToCommentId,
              highlightKey: _targetCommentKey,
            ),
            childCount: roots.length,
          ),
        ),
      ),
    ];
  }

  /// Returns [roots] with the target comment's root ancestor moved to the front.
  List<dynamic> _promoteTargetRoot(List<dynamic> roots, int targetId) {
    final byId = {
      for (final c in _comments)
        if (c['id'] is int) c['id'] as int: c
    };
    dynamic cur = byId[targetId];
    if (cur == null) return roots;
    // Walk up to the root ancestor.
    var guard = 0;
    while (cur != null &&
        (cur['replyTo'] ?? 0) != 0 &&
        byId[cur['replyTo']] != null &&
        guard++ < 100) {
      cur = byId[cur['replyTo']];
    }
    final rootId = cur?['id'];
    final idx = roots.indexWhere((r) => r['id'] == rootId);
    if (idx <= 0) return roots; // already first, or not found
    final reordered = List<dynamic>.from(roots);
    reordered.insert(0, reordered.removeAt(idx));
    return reordered;
  }

  Widget _commentSortChip(String label, String value) {
    final active = _commentSort == value;
    final accent = Theme.of(context).colorScheme.primary;
    return PressableScale(
      onTap: () => _changeCommentSort(value),
      scale: 0.92,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? accent.withValues(alpha: 0.18)
              : AppColors.bgCard,
          borderRadius: BorderRadius.circular(16),
          border: active ? Border.all(color: accent, width: 1) : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? accent : AppColors.textMuted,
            fontSize: 12,
            fontWeight:
                active ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildComposer() {
    final accent = Theme.of(context).colorScheme.primary;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        border: Border(
            top: BorderSide(
                color: Colors.white.withValues(alpha: 0.07),
                width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_replyToName != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
                color: AppColors.bgDeep,
                child: Row(children: [
                  Icon(Icons.reply, size: 14, color: accent),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text('Ответ для $_replyToName',
                        style: TextStyle(color: accent, fontSize: 12),
                        overflow: TextOverflow.ellipsis),
                  ),
                  GestureDetector(
                    onTap: _cancelReply,
                    child: const Icon(Icons.close,
                        size: 16, color: AppColors.textMuted),
                  ),
                ]),
              ),
            // Attachment previews
            if (_attachments.isNotEmpty || _attaching)
              SizedBox(
                height: 72,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  children: [
                    ..._attachments.asMap().entries.map((e) {
                      final uuid = e.value['data']?['uuid'];
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: CachedNetworkImage(
                                imageUrl: OsnovaImage(uuid).preview(120),
                                width: 64, height: 64, fit: BoxFit.cover,
                                placeholder: (_, __) => Container(width: 64, height: 64, color: AppColors.bgElevated),
                                errorWidget: (_, __, ___) => Container(
                                  width: 64, height: 64, color: AppColors.bgElevated,
                                  child: const Icon(Icons.image, color: Colors.grey, size: 20),
                                ),
                              ),
                            ),
                            Positioned(
                              right: 2, top: 2,
                              child: GestureDetector(
                                onTap: () => setState(() => _attachments.removeAt(e.key)),
                                child: Container(
                                  decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                                  child: const Icon(Icons.close, color: Colors.white, size: 16),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    if (_attaching)
                      Container(
                        width: 64, height: 64,
                        decoration: BoxDecoration(
                          color: AppColors.bgElevated, borderRadius: BorderRadius.circular(8)),
                        child: const Center(
                          child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
                        ),
                      ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
              child: Row(children: [
                GestureDetector(
                  onTap: _attachGif,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.bgElevated,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('GIF',
                        style: TextStyle(color: accent, fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  icon: const Icon(Icons.image_outlined, color: AppColors.textMuted),
                  onPressed: _attachFromGallery,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: TextField(
                    controller: _commentController,
                    focusNode: _commentFocus,
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                    minLines: 1,
                    maxLines: 5,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: 'Комментарий...',
                      hintStyle: const TextStyle(color: AppColors.textMuted),
                      filled: true,
                      fillColor: AppColors.bgElevated,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                _sending
                    ? const Padding(
                        padding: EdgeInsets.all(10),
                        child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : IconButton(
                        icon: Icon(Icons.send, color: accent),
                        onPressed: _sendComment,
                      ),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(dynamic ts) {
    if (ts == null) return '';
    final date = DateTime.fromMillisecondsSinceEpoch((ts as int) * 1000);
    const months = [
      'янв', 'фев', 'мар', 'апр', 'май', 'июн',
      'июл', 'авг', 'сен', 'окт', 'ноя', 'дек'
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}, ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}

