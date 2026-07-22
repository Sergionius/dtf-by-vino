import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/dtf_api.dart';
import '../services/settings_service.dart';
import '../theme.dart';
import '../widgets/avatar.dart';
import '../widgets/post_card.dart';
import '../widgets/profile_navigation.dart';
import '../widgets/shimmer.dart';
import 'post_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _ctrl = TextEditingController();
  List<dynamic> _results = [];
  bool _loading = false;
  String _lastQuery = '';

  // Landing content (shown when the query is empty).
  List<dynamic> _topBlogs = [];
  List<dynamic> _topComments = [];
  bool _loadingLanding = true;
  bool _showAllBlogs = false;

  @override
  void initState() {
    super.initState();
    _loadLanding();
  }

  Future<void> _loadLanding() async {
    final settings = context.read<SettingsService>();
    final results = await Future.wait([
      DtfApi.getTopBlogs(settings),
      DtfApi.getPopularComments(settings),
    ]);
    if (!mounted) return;
    setState(() {
      _topBlogs = results[0];
      _topComments = results[1].take(3).toList();
      _loadingLanding = false;
    });
  }

  Future<void> _search(String query) async {
    query = query.trim();
    if (query.isEmpty || query == _lastQuery) return;
    _lastQuery = query;
    setState(() { _loading = true; _results = []; });
    final settings = context.read<SettingsService>();
    final results = await DtfApi.searchEntries(query, settings);
    if (!mounted) return;
    setState(() { _results = results; _loading = false; });
  }

  void _openComment(dynamic comment) {
    final postId = comment['entry']?['id'] as int?;
    if (postId == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PostScreen(
          postId: postId,
          title: comment['entry']?['title'] ?? '',
          scrollToCommentId: comment['id'] as int?,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.bgCard,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TextField(
                  controller: _ctrl,
                  style: const TextStyle(color: Colors.white),
                  textInputAction: TextInputAction.search,
                  onSubmitted: _search,
                  decoration: InputDecoration(
                    hintText: 'Поиск по DTF',
                    hintStyle: const TextStyle(color: Colors.grey),
                    prefixIcon: const Icon(Icons.search, color: Colors.grey),
                    suffixIcon: _ctrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, color: Colors.grey),
                            onPressed: () {
                              _ctrl.clear();
                              setState(() { _results = []; _lastQuery = ''; });
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onChanged: (v) => setState(() {}),
                ),
              ),
            ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const FeedSkeleton();
    // Active search query → results.
    if (_lastQuery.isNotEmpty) {
      if (_results.isEmpty) {
        return const Center(
          child: Text('Ничего не найдено',
              style: TextStyle(color: Colors.grey)),
        );
      }
      return ListView.builder(
        itemCount: _results.length,
        itemBuilder: (_, i) {
          final post = _results[i];
          return PostCard(
            key: ValueKey(post['id']),
            post: post,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PostScreen(
                  postId: post['id'] as int,
                  title: post['title'] ?? '',
                  postData: post,
                ),
              ),
            ),
          );
        },
      );
    }
    // Empty query → discovery landing.
    return _buildLanding();
  }

  Widget _buildLanding() {
    if (_loadingLanding) return const FeedSkeleton();
    final blogs = _showAllBlogs ? _topBlogs : _topBlogs.take(3).toList();
    final bottomPad = MediaQuery.of(context).padding.bottom + 86;

    return ListView(
      padding: EdgeInsets.only(bottom: bottomPad),
      children: [
        if (_topBlogs.isNotEmpty) ...[
          const _SectionHeader('Топ блогов'),
          ...blogs.map((b) => _BlogTile(blog: b)),
          if (_topBlogs.length > 3)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: _ExpandButton(
                expanded: _showAllBlogs,
                onTap: () => setState(() => _showAllBlogs = !_showAllBlogs),
              ),
            ),
        ],
        if (_topComments.isNotEmpty) ...[
          const SizedBox(height: 8),
          const _SectionHeader('Популярные комментарии'),
          ..._topComments.map((c) => _CommentPreviewTile(
                comment: c,
                onTap: () => _openComment(c),
              )),
        ],
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Text(title,
          style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w800)),
    );
  }
}

class _ExpandButton extends StatelessWidget {
  final bool expanded;
  final VoidCallback onTap;
  const _ExpandButton({required this.expanded, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(expanded ? 'Свернуть' : 'Раскрыть топ',
                style: TextStyle(
                    color: accent, fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(width: 4),
            Icon(expanded ? Icons.expand_less : Icons.expand_more,
                color: accent, size: 20),
          ],
        ),
      ),
    );
  }
}

/// Compact number: 1234 → "1.2K", 12345 → "12.3K".
String _fmtCount(dynamic n) {
  final v = (n is num) ? n.toInt() : int.tryParse('$n') ?? 0;
  if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
  if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
  return '$v';
}

class _BlogTile extends StatefulWidget {
  final dynamic blog;
  const _BlogTile({required this.blog});

  @override
  State<_BlogTile> createState() => _BlogTileState();
}

class _BlogTileState extends State<_BlogTile> {
  late bool _subscribed = widget.blog['isSubscribed'] == true;
  bool _busy = false;

  Future<void> _toggle() async {
    final settings = context.read<SettingsService>();
    if (!settings.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Войди в аккаунт')));
      return;
    }
    final id = widget.blog['id'] as int?;
    if (id == null || _busy) return;
    final target = !_subscribed;
    setState(() { _subscribed = target; _busy = true; });
    final ok = await DtfApi.toggleSubscription(id, target, settings);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (!ok) _subscribed = !target; // revert on failure
    });
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final b = widget.blog;
    final subs = b['counters']?['subscribers'] ?? 0;
    final rating = b['count_stats_7d'];

    return GestureDetector(
      onTap: () => openUserProfile(context, b),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Avatar.fromData(b['avatar'], size: 46),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    b['name'] ?? 'Без названия',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 3),
                  Row(children: [
                    const Icon(Icons.people_outline,
                        size: 13, color: AppColors.textMuted),
                    const SizedBox(width: 3),
                    Text(_fmtCount(subs),
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 12)),
                    if (rating != null) ...[
                      const SizedBox(width: 10),
                      const Icon(Icons.trending_up,
                          size: 13, color: AppColors.textMuted),
                      const SizedBox(width: 3),
                      Text(_fmtCount(rating),
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 12)),
                    ],
                  ]),
                ],
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _toggle,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: _subscribed
                      ? AppColors.bgElevated
                      : accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: _subscribed ? AppColors.divider : accent,
                    width: 1,
                  ),
                ),
                child: Text(
                  _subscribed ? 'Вы подписаны' : 'Подписаться',
                  style: TextStyle(
                    color: _subscribed ? AppColors.textSecondary : accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommentPreviewTile extends StatelessWidget {
  final dynamic comment;
  final VoidCallback onTap;
  const _CommentPreviewTile({required this.comment, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final author = comment['author'];
    final text =
        (comment['text'] ?? '').toString().replaceAll(RegExp(r'<[^>]*>'), '').trim();
    final postTitle = comment['entry']?['title'] ?? '';
    final likes = comment['likes']?['summ'] ?? comment['likes']?['count'];

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 5, 16, 5),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Avatar.fromData(author?['avatar'], size: 28),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  author?['name'] ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                ),
              ),
              if (likes != null) ...[
                const Icon(Icons.favorite,
                    size: 13, color: AppColors.textMuted),
                const SizedBox(width: 3),
                Text('$likes',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12)),
              ],
            ]),
            if (text.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                text,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    height: 1.35),
              ),
            ],
            if (postTitle.toString().isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(children: [
                const Icon(Icons.article_outlined,
                    size: 12, color: AppColors.textMuted),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    postTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: AppColors.textMuted, fontSize: 11),
                  ),
                ),
              ]),
            ],
          ],
        ),
      ),
    );
  }
}
