import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../api/dtf_api.dart';
import '../services/settings_service.dart';
import '../theme.dart';
import '../util/osnova_image.dart';
import '../widgets/avatar.dart';
import '../widgets/badges.dart';
import '../widgets/post_card.dart';
import '../widgets/comment_widget.dart';
import '../widgets/linkified_text.dart';
import 'post_screen.dart';

class UserProfileScreen extends StatefulWidget {
  final int subsiteId;
  final String? initialName;
  final String? initialAvatar;

  const UserProfileScreen({
    super.key,
    required this.subsiteId,
    this.initialName,
    this.initialAvatar,
  });

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  dynamic _subsite;
  bool _loadingProfile = true;
  bool _subscribing = false;
  bool _isSubscribed = false;

  // Posts tab
  List<dynamic> _posts = [];
  bool _loadingPosts = true;
  bool _loadingMorePosts = false;
  String _postSort = 'new'; // 'new' | 'popular'
  int? _postsLastId;
  String? _postsLastSorting;

  // Comments tab
  List<dynamic> _comments = [];
  bool _loadingComments = false;
  bool _commentsLoaded = false;

  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadProfile();
    _loadPosts(reset: true);
    _scrollController.addListener(() {
      final pos = _scrollController.position;
      if (pos.pixels > pos.maxScrollExtent - 500) {
        if (_tabController.index == 0 && !_loadingMorePosts) _loadMorePosts();
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    if (_tabController.index == 1 && !_commentsLoaded) _loadComments();
    setState(() {});
  }

  Future<void> _loadProfile() async {
    final settings = context.read<SettingsService>();
    try {
      final sub = await DtfApi.getSubsite(widget.subsiteId, settings);
      if (!mounted) return;
      setState(() {
        _subsite = sub;
        _isSubscribed = sub?['isSubscribed'] == true;
        _loadingProfile = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingProfile = false);
    }
  }

  Future<void> _loadPosts({bool reset = false}) async {
    if (reset) {
      setState(() { _loadingPosts = true; _posts = []; _postsLastId = null; _postsLastSorting = null; });
    }
    final settings = context.read<SettingsService>();
    final page = await DtfApi.getSubsiteEntries(
      widget.subsiteId, settings, sorting: _postSort,
    );
    if (!mounted) return;
    setState(() {
      _posts = page.items;
      _postsLastId = page.lastId;
      _postsLastSorting = page.lastSortingValue;
      _loadingPosts = false;
    });
  }

  Future<void> _loadMorePosts() async {
    if (_loadingMorePosts || _postsLastId == null) return;
    setState(() => _loadingMorePosts = true);
    final settings = context.read<SettingsService>();
    final page = await DtfApi.getSubsiteEntries(
      widget.subsiteId, settings,
      sorting: _postSort, lastId: _postsLastId, lastSortingValue: _postsLastSorting,
    );
    if (!mounted) return;
    setState(() {
      _posts.addAll(page.items);
      _postsLastId = page.lastId;
      _postsLastSorting = page.lastSortingValue;
      _loadingMorePosts = false;
    });
  }

  Future<void> _loadComments() async {
    setState(() { _loadingComments = true; _commentsLoaded = true; });
    final settings = context.read<SettingsService>();
    final comments = await DtfApi.getSubsiteComments(widget.subsiteId, settings);
    if (!mounted) return;
    setState(() { _comments = comments; _loadingComments = false; });
  }

  Future<void> _changePostSort(String sort) async {
    if (_postSort == sort) return;
    setState(() => _postSort = sort);
    await _loadPosts(reset: true);
  }

  Future<void> _toggleSubscribe() async {
    final settings = context.read<SettingsService>();
    if (!settings.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Войди в аккаунт, чтобы подписаться')),
      );
      return;
    }
    setState(() => _subscribing = true);
    final newState = !_isSubscribed;
    final ok = await DtfApi.toggleSubscription(widget.subsiteId, newState, settings);
    if (!mounted) return;
    setState(() {
      _subscribing = false;
      if (ok) _isSubscribed = newState;
    });
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось изменить подписку')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = _subsite?['name'] ?? widget.initialName ?? 'Профиль';
    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      body: NestedScrollView(
        controller: _scrollController,
        headerSliverBuilder: (context, _) => [
          SliverAppBar(
            backgroundColor: AppColors.bgCard,
            pinned: true,
            expandedHeight: _subsite?['cover']?['data']?['uuid'] != null ? 200 : 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(name, style: const TextStyle(color: Colors.white, fontSize: 16)),
            flexibleSpace: _subsite?['cover']?['data']?['uuid'] != null
                ? FlexibleSpaceBar(
                    background: CachedNetworkImage(
                      // Animated covers: skip scale_crop — like every other
                      // resize op on this CDN, it freezes on one frame.
                      imageUrl: _subsite['cover']['data']['type'] == 'gif'
                          ? OsnovaImage(_subsite['cover']['data']['uuid']).gif()
                          : OsnovaImage(_subsite['cover']['data']['uuid']).scaleCrop(800, 300),
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Container(color: AppColors.bgElevated),
                    ),
                  )
                : null,
          ),
          SliverToBoxAdapter(child: _buildHeader()),
          SliverPersistentHeader(
            pinned: true,
            delegate: _TabBarDelegate(
              TabBar(
                controller: _tabController,
                labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                tabs: const [
                  Tab(text: 'Посты'),
                  Tab(text: 'Комментарии'),
                  Tab(text: 'Инфо'),
                ],
              ),
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildPostsTab(),
            _buildCommentsTab(),
            _buildInfoTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    if (_loadingProfile) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final sub = _subsite;
    final accent = Theme.of(context).colorScheme.primary;
    final rating = sub?['rating'];
    return Container(
      color: AppColors.bgDeep,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Avatar(
                uuid: sub?['avatar']?['data']?['uuid'] ?? widget.initialAvatar,
                size: 88,
                animated: sub?['avatar']?['data']?['type'] == 'gif',
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Flexible(
                        child: Text(
                          sub?['name'] ?? widget.initialName ?? '',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 26,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                      AuthorBadge(author: sub, size: 18),
                      if (sub?['isVerified'] == true) ...[
                        const SizedBox(width: 4),
                        Icon(Icons.verified, color: accent, size: 18),
                      ],
                    ]),
                    if (rating != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Row(children: [
                          Icon(Icons.trending_up, color: accent, size: 18),
                          const SizedBox(width: 5),
                          Text(_fmtCount(rating),
                              style: TextStyle(
                                  color: accent,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600)),
                        ]),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildActionRow(),
          if (sub?['description'] != null &&
              (sub['description'] as String).isNotEmpty) ...[
            const SizedBox(height: 12),
            LinkifiedText(
              sub['description'] as String,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 14, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionRow() {
    final isFrozen = _subsite?['isFrozen'] == true;
    final accent = Theme.of(context).colorScheme.primary;
    return Row(children: [
      Expanded(
        child: ElevatedButton(
          onPressed: _subscribing ? null : _toggleSubscribe,
          style: ElevatedButton.styleFrom(
            backgroundColor:
                _isSubscribed ? AppColors.bgElevated : accent,
            foregroundColor: Colors.white,
            minimumSize: const Size(0, 48),
          ),
          child: _subscribing
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(
                  isFrozen
                      ? (_isSubscribed ? 'Отписаться' : 'Подписаться')
                      : (_isSubscribed ? 'Вы подписаны' : 'Подписаться'),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
        ),
      ),
      const SizedBox(width: 10),
      _circleAction(Icons.card_giftcard, 'Подарки пока недоступны'),
      const SizedBox(width: 10),
      _circleAction(Icons.currency_ruble, 'Донаты пока недоступны'),
      const SizedBox(width: 10),
      _circleAction(Icons.chat_bubble_outline, 'Чаты скоро появятся'),
    ]);
  }

  // Secondary circular buttons next to "Подписаться". The underlying features
  // (gift / donate / DM) aren't built yet, so they surface a "soon" toast.
  Widget _circleAction(IconData icon, String soonMsg) {
    return GestureDetector(
      onTap: () => ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(soonMsg))),
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: AppColors.bgElevated,
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Icon(icon, color: AppColors.textSecondary, size: 22),
      ),
    );
  }

  String _fmtCount(dynamic n) {
    final v = (n is num) ? n.toInt() : int.tryParse('$n') ?? 0;
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
    return '$v';
  }

  Widget _buildPostsTab() {
    return Column(
      children: [
        // Sort toggle
        Container(
          color: AppColors.bgDeep,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(children: [
            _sortChip('Свежее', 'new'),
            const SizedBox(width: 8),
            _sortChip('Популярное', 'popular'),
          ]),
        ),
        Expanded(
          child: _loadingPosts
              ? const Center(child: CircularProgressIndicator())
              : _posts.isEmpty
                  ? const Center(child: Text('Нет записей', style: TextStyle(color: Colors.grey)))
                  : ListView.builder(
                      padding: EdgeInsets.zero,
                      itemCount: _posts.length + (_loadingMorePosts ? 1 : 0),
                      itemBuilder: (ctx, i) {
                        if (i == _posts.length) {
                          return const Center(
                            child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()),
                          );
                        }
                        final post = _posts[i];
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
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _sortChip(String label, String value) {
    final active = _postSort == value;
    return GestureDetector(
      onTap: () => _changePostSort(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: active ? Theme.of(context).colorScheme.primary : AppColors.bgCard,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : Colors.grey,
            fontSize: 13,
            fontWeight: active ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildCommentsTab() {
    if (_loadingComments) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_comments.isEmpty) {
      return const Center(child: Text('Нет комментариев', style: TextStyle(color: Colors.grey)));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _comments.length,
      itemBuilder: (ctx, i) {
        final c = _comments[i];
        final entry = c['entry'];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (entry != null)
              GestureDetector(
                onTap: () => Navigator.push(
                  ctx,
                  MaterialPageRoute(
                    builder: (_) => PostScreen(
                      postId: entry['id'] as int,
                      title: entry['title'] ?? '',
                    ),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.only(left: 4, top: 8, bottom: 4),
                  child: Row(children: [
                    const Icon(Icons.subdirectory_arrow_right, size: 14, color: Colors.grey),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'к записи «${entry['title'] ?? 'без названия'}»',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 12),
                      ),
                    ),
                  ]),
                ),
              ),
            CommentWidget(comment: c),
          ],
        );
      },
    );
  }

  Widget _buildInfoTab() {
    if (_subsite == null) {
      return const Center(child: Text('Нет данных', style: TextStyle(color: Colors.grey)));
    }
    final sub = _subsite;
    final created = sub['created'] as int?;
    final counters = sub['counters'];
    final rows = <(String, String)>[
      ('ID', '${sub['id']}'),
      if (sub['nickname'] != null) ('Никнейм', '@${sub['nickname']}'),
      if (created != null) ('Регистрация', _formatDate(created)),
      ('Рейтинг', '${sub['rating'] ?? 0}'),
      ('Записей', '${counters?['entries'] ?? 0}'),
      ('Комментариев', '${counters?['comments'] ?? 0}'),
      ('Подписчиков', '${counters?['subscribers'] ?? 0}'),
      ('Подписок', '${counters?['subscriptions'] ?? 0}'),
      if (sub['isPlus'] == true) ('Plus', 'Да 💎'),
      if (sub['isVerified'] == true) ('Верифицирован', 'Да ✓'),
      if (sub['isFrozen'] == true) ('Статус', 'Заморожен ❄️'),
    ];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ...rows.map((r) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 130,
                    child: Text(r.$1, style: const TextStyle(color: Colors.grey, fontSize: 14)),
                  ),
                  Expanded(
                    child: Text(r.$2,
                        style: const TextStyle(color: Colors.white, fontSize: 14)),
                  ),
                ],
              ),
            )),
      ],
    );
  }

  String _formatDate(int ts) {
    final date = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
    const months = [
      'янв', 'фев', 'мар', 'апр', 'мая', 'июн',
      'июл', 'авг', 'сен', 'окт', 'ноя', 'дек'
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }
}

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  _TabBarDelegate(this.tabBar);

  @override
  double get minExtent => tabBar.preferredSize.height;
  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(color: AppColors.bgDeep, child: tabBar);
  }

  @override
  bool shouldRebuild(_TabBarDelegate oldDelegate) => false;
}
