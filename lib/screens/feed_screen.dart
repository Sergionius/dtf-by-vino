import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../api/dtf_api.dart';
import '../services/settings_service.dart';
import '../theme.dart';
import '../util/osnova_image.dart';
import '../widgets/post_card.dart';
import '../widgets/shimmer.dart';
import 'post_screen.dart';

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => FeedScreenState();
}

class FeedScreenState extends State<FeedScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // (feedType, fullLabel, shortLabel) — order matches the Figma redesign.
  final _tabs = [
    ('popular',   'Популярное', 'Топ'),
    ('new',       'Свежее',     'Св.'),
    ('my',        'Моя лента',  'Моя'),
    ('editorial', 'Новости',    'Нов.'),
  ];

  // One key per tab so the active feed list can be scrolled to top (e.g. when
  // the "Главная" nav tab is tapped while already on the feed).
  late final List<GlobalKey<FeedListState>> _listKeys =
      List.generate(_tabs.length, (_) => GlobalKey<FeedListState>());

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    // Rebuild when active tab changes so labels update.
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });
  }

  /// Scrolls the currently-visible feed tab back to the top.
  void scrollActiveToTop() {
    _listKeys[_tabController.index].currentState?.scrollToTop();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeIndex = _tabController.index;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: TabBar(
                controller: _tabController,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                padding: EdgeInsets.zero,
                labelPadding: const EdgeInsets.symmetric(horizontal: 6),
                tabs: _tabs.asMap().entries.map((e) {
                  final selected = e.key == activeIndex;
                  // Selected tab shows full name; others show short abbreviation.
                  return Tab(text: selected ? e.value.$2 : e.value.$3);
                }).toList(),
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: _tabs
                    .asMap()
                    .entries
                    .map((e) => FeedList(
                        key: _listKeys[e.key], feedType: e.value.$1))
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact news digest shown at the top of "Популярное".
/// Shows up to 4 editorial posts as title + subsite name + thumbnail cards.
class _NewsDigestBlock extends StatelessWidget {
  final List<dynamic> posts;
  final void Function(dynamic post) onTap;

  const _NewsDigestBlock({required this.posts, required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (posts.isEmpty) return const SizedBox();
    return GlassCard(
      margin: const EdgeInsets.fromLTRB(12, 5, 12, 5),
      child: Column(
        children: [
          for (int i = 0; i < posts.length; i++) ...[
            if (i > 0)
              const Divider(height: 1, thickness: 1,
                  indent: 16, endIndent: 16),
            _NewsItem(post: posts[i], onTap: () => onTap(posts[i])),
          ],
        ],
      ),
    );
  }
}

class _NewsItem extends StatelessWidget {
  final dynamic post;
  final VoidCallback onTap;

  const _NewsItem({required this.post, required this.onTap});

  String? get _imageUuid {
    for (final block in post['blocks'] ?? []) {
      if (block['type'] == 'media') {
        final items = block['data']?['items'];
        if (items is List && items.isNotEmpty) {
          return items[0]?['image']?['data']?['uuid'] as String?;
        }
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final uuid = _imageUuid;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    post['title'] ?? '',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    post['subsite']?['name'] ?? '',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (uuid != null) ...[
              const SizedBox(width: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: CachedNetworkImage(
                  imageUrl: OsnovaImage(uuid).preview(160),
                  width: 72,
                  height: 72,
                  fit: BoxFit.cover,
                  memCacheWidth: 200,
                  placeholder: (_, __) =>
                      Container(width: 72, height: 72, color: AppColors.bgElevated),
                  errorWidget: (_, __, ___) =>
                      Container(width: 72, height: 72, color: AppColors.bgElevated),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A single self-loading, paginated feed list. Kept alive across tab swipes.
class FeedList extends StatefulWidget {
  final String feedType; // 'popular' | 'new' | 'editorial' | 'my'
  const FeedList({super.key, required this.feedType});

  @override
  State<FeedList> createState() => FeedListState();
}

class FeedListState extends State<FeedList> with AutomaticKeepAliveClientMixin {
  List<dynamic> _posts = [];
  List<dynamic> _editorialPosts = []; // top-4 editorial, shown only in 'popular'
  bool _loading = true;
  bool _loadingMore = false;
  int? _lastId;
  String? _lastSortingValue;
  final _scrollController = ScrollController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      final pos = _scrollController.position;
      if (pos.pixels > pos.maxScrollExtent - 500 && !_loadingMore) _fetchMore();
    });
    _fetchPosts();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<FeedPage> _loadPage({int? lastId, String? lastSortingValue}) {
    final settings = context.read<SettingsService>();
    if (widget.feedType == 'editorial') {
      return DtfApi.getEditorialFeed(
          settings: settings, lastId: lastId, lastSortingValue: lastSortingValue);
    }
    return DtfApi.getFeed(
        settings: settings, type: widget.feedType,
        lastId: lastId, lastSortingValue: lastSortingValue);
  }

  Future<void> _fetchPosts() async {
    setState(() { _loading = true; _posts = []; _lastId = null; _lastSortingValue = null; });
    final settings = context.read<SettingsService>();
    if (widget.feedType == 'my' && !settings.isLoggedIn) {
      setState(() => _loading = false);
      return;
    }
    try {
      // For popular: load editorial digest in parallel with the main feed.
      final futures = <Future>[_loadPage()];
      if (widget.feedType == 'popular') {
        futures.add(DtfApi.getEditorialFeed(settings: settings));
      }
      final results = await Future.wait(futures);
      if (!mounted) return;
      final page = results[0] as FeedPage;
      setState(() {
        _posts = page.items.where((p) => !settings.isFiltered(p)).toList();
        _lastId = page.lastId;
        _lastSortingValue = page.lastSortingValue;
        if (widget.feedType == 'popular') {
          _editorialPosts = (results[1] as FeedPage).items.take(4).toList();
        }
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _fetchMore() async {
    if (_loadingMore || _lastId == null) return;
    setState(() => _loadingMore = true);
    final settings = context.read<SettingsService>();
    try {
      final page = await _loadPage(lastId: _lastId, lastSortingValue: _lastSortingValue);
      if (!mounted) return;
      setState(() {
        _posts.addAll(page.items.where((p) => !settings.isFiltered(p)));
        _lastId = page.lastId;
        _lastSortingValue = page.lastSortingValue;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  /// Scrolls this feed list back to the top (invoked from the "Главная" nav
  /// tab). Safe to call before the list has been laid out.
  void scrollToTop() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(0,
        duration: const Duration(milliseconds: 400), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isLoggedIn = context.select<SettingsService, bool>((s) => s.isLoggedIn);

    if (widget.feedType == 'my' && !isLoggedIn) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Войди в аккаунт, чтобы видеть свою ленту',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 15),
          ),
        ),
      );
    }

    if (_loading) return const FeedSkeleton();

    final bottomPad = MediaQuery.of(context).padding.bottom + 86;

    return RefreshIndicator(
          onRefresh: _fetchPosts,
          child: _posts.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.only(bottom: bottomPad),
                  children: const [
                    SizedBox(height: 200),
                    Center(
                        child: Text('Нет постов',
                            style: TextStyle(color: AppColors.textSecondary))),
                  ],
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: EdgeInsets.only(top: 8, bottom: bottomPad),
                  itemCount: _posts.length +
                      (_editorialPosts.isNotEmpty && widget.feedType == 'popular' ? 1 : 0) +
                      (_loadingMore ? 1 : 0),
                  itemBuilder: (ctx, i) {
                    // Slot 0 in 'popular': the editorial digest block.
                    final hasDigest = widget.feedType == 'popular' && _editorialPosts.isNotEmpty;
                    if (i == 0 && hasDigest) {
                      return _NewsDigestBlock(
                        posts: _editorialPosts,
                        onTap: (post) => Navigator.push(
                          ctx,
                          MaterialPageRoute(
                            builder: (_) => PostScreen(
                              postId: post['id'] as int,
                              title: post['title'] ?? '',
                              postData: post,
                            ),
                          ),
                        ),
                      );
                    }
                    final postIdx = hasDigest ? i - 1 : i;
                    if (postIdx == _posts.length) {
                      return const Center(
                        child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()),
                      );
                    }
                    final post = _posts[postIdx];
                    return PostCard(
                      key: ValueKey(post['id']),
                      post: post,
                      onTap: () => Navigator.push(
                        ctx,
                        MaterialPageRoute(
                          builder: (_) => PostScreen(
                            postId: post['id'] as int,
                            title: post['title'] ?? '',
                            postData: post,
                          ),
                        ),
                      ),
                      onTapComments: () => Navigator.push(
                        ctx,
                        MaterialPageRoute(
                          builder: (_) => PostScreen(
                            postId: post['id'] as int,
                            title: post['title'] ?? '',
                            postData: post,
                            openToComments: true,
                          ),
                        ),
                      ),
                    );
                  },
                ),
        );
  }
}
