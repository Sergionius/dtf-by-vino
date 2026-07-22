import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/dtf_api.dart';
import '../services/settings_service.dart';
import '../theme.dart';
import '../widgets/avatar.dart';
import '../widgets/badges.dart';
import '../widgets/profile_navigation.dart';
import 'login_screen.dart';
import 'settings_screen.dart';
import 'bookmarks_screen.dart';
import 'drafts_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  dynamic _user;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    setState(() => _loading = true);
    final settings = context.read<SettingsService>();
    if (!settings.isLoggedIn) {
      setState(() => _loading = false);
      return;
    }
    try {
      final user = await DtfApi.getMe(settings);
      if (mounted) {
        setState(() {
          _user = user;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _logout() async {
    try {
      await context.read<SettingsService>().clearToken();
      if (mounted) setState(() => _user = null);
    } on AuthStorageException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message)),
        );
      }
    }
  }

  void _changeBadge() {
    final settings = context.read<SettingsService>();
    showBadgePicker(context, (badgeId) async {
      setState(() => _user['badgeId'] = badgeId);
      final ok = await DtfApi.setBadge(badgeId, settings);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось сменить бейджик')),
        );
      }
    });
  }

  Future<void> _goLogin() async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
    if (ok == true) await _checkAuth();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final settings = context.watch<SettingsService>();
    final accent = Theme.of(context).colorScheme.primary;

    if (!settings.isLoggedIn) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.account_circle_outlined,
                            color: AppColors.textMuted, size: 72),
                        const SizedBox(height: 16),
                        const Text('Ты не вошёл в аккаунт',
                            style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 18)),
                        const SizedBox(height: 8),
                        const Text(
                          'Войди, чтобы видеть свою ленту, уведомления и профиль',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 14),
                        ),
                        const SizedBox(height: 28),
                        ElevatedButton(
                          onPressed: _goLogin,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accent,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(200, 48),
                          ),
                          child: const Text('Войти',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.settings_outlined,
                    color: AppColors.textMuted),
                title: const Text('Настройки приложения',
                    style: TextStyle(color: AppColors.textPrimary)),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const SettingsScreen()),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
    }

    final menuItems = <List<dynamic>>[
      [
        Icons.bookmark_border,
        'Закладки',
        () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const BookmarksScreen()))
      ],
      [
        Icons.edit_outlined,
        'Черновики',
        () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const DraftsScreen()))
      ],
      [Icons.currency_ruble, 'Донаты', null],
      [Icons.emoji_events_outlined, 'Ачивки', null],
      [Icons.diamond_outlined, 'Подписка Plus', null],
    ];

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).padding.bottom + 86),
          children: [
            GestureDetector(
              onTap: () => openUserProfile(context, _user),
              child: Container(
                margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                decoration: glassCardDecoration(),
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  Avatar(
                    uuid: _user?['avatar']?['data']?['uuid'],
                    size: 60,
                    animated:
                        _user?['avatar']?['data']?['type'] == 'gif',
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Flexible(
                              child: Text(
                                _user?['name'] ?? '',
                                style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (_user?['isPlus'] == true) ...[
                              const SizedBox(width: 6),
                              GestureDetector(
                                onTap: _changeBadge,
                                child: _user?['badgeId'] != null
                                    ? BadgeIcon(
                                        badgeId: _user['badgeId']
                                            as String?,
                                        size: 20)
                                    : const Text('💎',
                                        style:
                                            TextStyle(fontSize: 14)),
                              ),
                            ],
                            const Spacer(),
                            const Icon(Icons.chevron_right,
                                color: AppColors.textMuted, size: 20),
                          ]),
                          if (_user?['nickname'] != null)
                            Text('@${_user['nickname']}',
                                style: const TextStyle(
                                    color: AppColors.textMuted,
                                    fontSize: 13)),
                          const SizedBox(height: 6),
                          Row(children: [
                            _statChip(
                                '${_user?['counters']?['entries'] ?? 0}',
                                'постов'),
                            const SizedBox(width: 16),
                            _statChip(
                                '${_user?['counters']?['karma'] ?? 0}',
                                'карма'),
                          ]),
                        ]),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 12),
              decoration: glassCardDecoration(),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.card),
                child: Material(
                  type: MaterialType.transparency,
                  child: Column(
                children: [
                  ...menuItems.map((item) => ListTile(
                        leading: Icon(item[0] as IconData,
                            color: AppColors.textSecondary, size: 22),
                        title: Text(item[1] as String,
                            style: const TextStyle(
                                color: AppColors.textPrimary)),
                        trailing: const Icon(Icons.chevron_right,
                            color: AppColors.textMuted, size: 20),
                        onTap: item[2] as VoidCallback?,
                      )),
                ],
                ),  // Column
                ),  // Material
              ),    // ClipRRect
            ),
            const SizedBox(height: 8),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 12),
              decoration: glassCardDecoration(),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.card),
                child: Material(
                  type: MaterialType.transparency,
                  child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.settings_outlined,
                        color: AppColors.textSecondary, size: 22),
                    title: const Text('Настройки приложения',
                        style: TextStyle(color: AppColors.textPrimary)),
                    trailing: const Icon(Icons.chevron_right,
                        color: AppColors.textMuted, size: 20),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const SettingsScreen()),
                    ),
                  ),
                  const Divider(height: 1, indent: 56),
                  ListTile(
                    leading: const Icon(Icons.logout,
                        color: Colors.red, size: 22),
                    title: const Text('Выйти',
                        style: TextStyle(color: Colors.red)),
                    onTap: () => showDialog(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('Выйти из аккаунта?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Отмена'),
                          ),
                          TextButton(
                            onPressed: () {
                              Navigator.pop(context);
                              _logout();
                            },
                            child: const Text('Выйти',
                                style: TextStyle(color: Colors.red)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                ),  // Column
                ),  // Material
              ),    // ClipRRect
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(
                'DTF by Vino',
                style: TextStyle(
                    color: AppColors.textMuted.withValues(alpha: 0.5),
                    fontSize: 12),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _statChip(String value, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value,
            style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.bold)),
        Text(label,
            style: const TextStyle(
                color: AppColors.textMuted, fontSize: 12)),
      ],
    );
  }
}
