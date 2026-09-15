import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/app_strings.dart';
import '../../core/auth/auth_service.dart';
import '../../core/community_models.dart';
import '../../core/network/app_image_cache.dart';
import '../../data/bangumi_repository.dart';
import '../../widgets/common.dart';
import '../auth/login_page.dart';
import '../user/user_profile_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({
    super.key,
    required this.authService,
    required this.repository,
    required this.themeMode,
    required this.onToggleTheme,
  });

  final AuthService? authService;
  final BangumiRepository repository;
  final ThemeMode themeMode;
  final VoidCallback onToggleTheme;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool _notifications = true;
  bool _autoPlay = false;
  bool _reduceMotion = false;
  String _profileUsername = '';
  Future<UserProfileData>? _profile;

  Future<UserProfileData>? _ensureProfile(String username) {
    if (username.isEmpty) return null;
    if (_profile == null || _profileUsername != username) {
      _profileUsername = username;
      _profile = widget.repository.fetchUserProfile(username);
    }
    return _profile;
  }

  Future<void> _clearImageCache() async {
    await AppImageCache.clear();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('图片缓存已清除')));
  }

  Future<void> _testNetwork() async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('正在连接 Bangumi…')));
    try {
      await widget.repository.fetchTrending(limit: 1);
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        const SnackBar(content: Text('连接正常，可以访问 Bangumi')),
      );
    } on Object catch (error) {
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text('连接失败：$error')));
    }
  }

  Future<void> _openLogin() async {
    final authService = widget.authService;
    if (authService == null) return;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => LoginPage(authService: authService)),
    );
  }

  Future<void> _logout() async {
    final authService = widget.authService;
    if (authService == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('退出登录'),
            content: const Text('将清除本机保存的登录会话。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('退出'),
              ),
            ],
          ),
    );
    if (confirmed == true) await authService.logout();
  }

  void _openMyProfile(int initialIndex) {
    final username = widget.authService?.user?.username ?? '';
    if (username.isEmpty) {
      _openLogin();
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder:
            (_) => UserProfilePage(
              username: username,
              repository: widget.repository,
              initialIndex: initialIndex,
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authService = widget.authService;
    if (authService != null) {
      return AnimatedBuilder(
        animation: authService,
        builder: (_, __) => _buildPage(context),
      );
    }
    return _buildPage(context);
  }

  Widget _buildPage(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final user = widget.authService?.user;
    return SafeArea(
      child: ContentFrame(
        maxWidth: 960,
        child: ListView(
          key: const PageStorageKey('profile-scroll'),
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 30),
          children: [
            const PageHeader(
              title: AppStrings.profile,
              subtitle: '收藏、进度与客户端设置',
            ),
            const SizedBox(height: 22),
            SurfaceBlock(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 580;
                  final identity = Row(
                    children: [
                      CircleAvatar(
                        radius: 31,
                        backgroundColor: scheme.primaryContainer,
                        foregroundColor: scheme.primary,
                        backgroundImage:
                            user?.avatarUrl.isNotEmpty == true
                                ? CachedNetworkImageProvider(
                                  user!.avatarUrl,
                                  cacheManager: AppImageCache.manager,
                                )
                                : null,
                        child:
                            user?.avatarUrl.isNotEmpty == true
                                ? null
                                : const Icon(Icons.person_outline_rounded),
                      ),
                      const SizedBox(width: 15),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user?.displayName ?? '访客模式',
                              style: const TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              user == null
                                  ? '登录后同步收藏与观看进度'
                                  : '@${user.username}',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      if (widget.authService != null)
                        user == null
                            ? FilledButton.icon(
                              onPressed: _openLogin,
                              icon: const Icon(Icons.login_rounded),
                              label: const Text('登录'),
                            )
                            : IconButton(
                              tooltip: '退出登录',
                              onPressed: _logout,
                              icon: const Icon(Icons.logout_rounded),
                            ),
                    ],
                  );
                  final stats = FutureBuilder<UserProfileData>(
                    future: _ensureProfile(user?.username ?? ''),
                    builder: (context, snapshot) {
                      final values = snapshot.data?.user.stats;
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _Stat(
                            value: values == null ? '--' : '${values.subjects}',
                            label: '收藏',
                          ),
                          _Stat(
                            value:
                                values == null
                                    ? '--'
                                    : '${values.characters + values.persons}',
                            label: '人物',
                          ),
                          _Stat(
                            value: values == null ? '--' : '${values.friends}',
                            label: '好友',
                          ),
                        ],
                      );
                    },
                  );
                  if (compact) {
                    return Column(
                      children: [identity, const SizedBox(height: 22), stats],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: identity),
                      const SizedBox(width: 24),
                      SizedBox(width: 280, child: stats),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 24),
            Text('快捷入口', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _Shortcut(
                  icon: Icons.bookmarks_outlined,
                  label: '我的收藏',
                  onTap: () => _openMyProfile(1),
                ),
                _Shortcut(
                  icon: Icons.theater_comedy_outlined,
                  label: '人物收藏',
                  onTap: () => _openMyProfile(2),
                ),
                _Shortcut(
                  icon: Icons.article_outlined,
                  label: '我的日志',
                  onTap: () => _openMyProfile(3),
                ),
                _Shortcut(
                  icon: Icons.list_alt_outlined,
                  label: '我的目录',
                  onTap: () => _openMyProfile(4),
                ),
                _Shortcut(
                  icon: Icons.people_outline_rounded,
                  label: '我的好友',
                  onTap: () => _openMyProfile(5),
                ),
                _Shortcut(
                  icon: Icons.timeline_rounded,
                  label: '我的时间线',
                  onTap: () => _openMyProfile(6),
                ),
                _Shortcut(
                  icon: Icons.bar_chart_rounded,
                  label: '我的统计',
                  onTap: () => _openMyProfile(7),
                ),
              ],
            ),
            const SizedBox(height: 26),
            Text('账户', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            SurfaceBlock(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.manage_accounts_outlined),
                    title: const Text('账户资料'),
                    subtitle: Text(
                      user == null ? '登录后管理账户' : '@${user.username}',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: user == null ? _openLogin : () => _openMyProfile(0),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.privacy_tip_outlined),
                    title: const Text('隐私与可见性'),
                    subtitle: const Text('收藏隐私可在编辑收藏时单独设置'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap:
                        () => ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('当前支持逐条收藏设置公开范围')),
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            Text('显示与性能', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            SurfaceBlock(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.palette_outlined),
                    title: const Text('外观'),
                    subtitle: Text(
                      Theme.of(context).brightness == Brightness.dark
                          ? '深色主题'
                          : '浅色主题',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: widget.onToggleTheme,
                  ),
                  const Divider(height: 1),
                  const ListTile(
                    leading: Icon(Icons.speed_rounded),
                    title: Text('屏幕刷新率'),
                    subtitle: Text('跟随系统，支持最高 120Hz'),
                    trailing: Icon(Icons.check_circle_outline_rounded),
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    secondary: const Icon(Icons.play_circle_outline_rounded),
                    title: const Text('自动播放预览'),
                    value: _autoPlay,
                    onChanged: (value) => setState(() => _autoPlay = value),
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    secondary: const Icon(Icons.animation_outlined),
                    title: const Text('减少界面动效'),
                    subtitle: const Text('适合省电模式或低性能设备'),
                    value: _reduceMotion,
                    onChanged: (value) => setState(() => _reduceMotion = value),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            Text('通知', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            SurfaceBlock(
              padding: EdgeInsets.zero,
              child: SwitchListTile(
                secondary: const Icon(Icons.notifications_outlined),
                title: const Text('更新提醒'),
                subtitle: const Text('保留本机提醒偏好'),
                value: _notifications,
                onChanged: (value) => setState(() => _notifications = value),
              ),
            ),
            const SizedBox(height: 22),
            Text('数据与网络', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            SurfaceBlock(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.cleaning_services_outlined),
                    title: const Text('清除图片缓存'),
                    subtitle: const Text('释放封面、头像与预览图片占用'),
                    trailing: const Icon(Icons.delete_sweep_outlined),
                    onTap: _clearImageCache,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.network_check_rounded),
                    title: const Text('网络诊断'),
                    subtitle: const Text('测试 next.bgm.tv API 连接'),
                    trailing: const Icon(Icons.play_arrow_rounded),
                    onTap: _testNetwork,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            Text('关于', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            const SurfaceBlock(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  ListTile(
                    leading: Icon(Icons.info_outline_rounded),
                    title: Text('Bangumi Flutter'),
                    subtitle: Text('版本 1.0.0 · Android 10+ / Windows'),
                  ),
                  Divider(height: 1),
                  ListTile(
                    leading: Icon(Icons.api_outlined),
                    title: Text('数据来源'),
                    subtitle: Text('Bangumi Next API · next.bgm.tv'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 3),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _Shortcut extends StatelessWidget {
  const _Shortcut({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      child: SurfaceBlock(
        padding: EdgeInsets.zero,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 16),
            child: Row(
              children: [
                Icon(icon),
                const SizedBox(width: 9),
                Flexible(child: Text(label)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
