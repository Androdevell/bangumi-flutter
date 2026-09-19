import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/auth/auth_service.dart';
import '../../core/community_models.dart';
import '../../core/localization/app_localizations.dart';
import '../../core/network/app_image_cache.dart';
import '../../core/settings/app_preferences.dart';
import '../../core/update/app_update_service.dart';
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
    required this.locale,
    required this.onLocaleChanged,
    required this.appIconStyle,
    required this.onAppIconStyleChanged,
  });

  final AuthService? authService;
  final BangumiRepository repository;
  final ThemeMode themeMode;
  final VoidCallback onToggleTheme;
  final Locale locale;
  final ValueChanged<Locale> onLocaleChanged;
  final AppIconStyle appIconStyle;
  final ValueChanged<AppIconStyle> onAppIconStyleChanged;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool _notifications = true;
  bool _autoPlay = false;
  bool _reduceMotion = false;
  String _profileUsername = '';
  Future<UserProfileData>? _profile;
  late final AppUpdateService _updateService = AppUpdateService();
  late final Future<String> _appVersion = _updateService.currentVersion();
  bool _checkingUpdate = false;

  AppLocalizations get _strings => AppLocalizations.of(context);

  @override
  void initState() {
    super.initState();
    widget.repository.collectionChanges.addListener(_refreshProfile);
  }

  @override
  void didUpdateWidget(covariant ProfilePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) {
      oldWidget.repository.collectionChanges.removeListener(_refreshProfile);
      widget.repository.collectionChanges.addListener(_refreshProfile);
      _refreshProfile();
    }
  }

  void _refreshProfile() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.repository.collectionChanges.removeListener(_refreshProfile);
    _updateService.close();
    super.dispose();
  }

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
    ).showSnackBar(SnackBar(content: Text(_strings.t('cacheCleared'))));
  }

  Future<void> _testNetwork() async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(SnackBar(content: Text(_strings.t('connecting'))));
    try {
      await widget.repository.fetchTrending(limit: 1);
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(content: Text(_strings.t('connectionOk'))),
      );
    } on Object catch (error) {
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(content: Text('${_strings.t('connectionFailed')}：$error')),
      );
    }
  }

  Future<void> _checkUpdate() async {
    if (_checkingUpdate) return;
    setState(() => _checkingUpdate = true);
    try {
      final result = await _updateService.check();
      if (!mounted) return;
      if (!result.updateAvailable) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${_strings.t('latestVersion')} ${result.currentVersion}',
            ),
          ),
        );
        return;
      }
      final open = await showDialog<bool>(
        context: context,
        builder:
            (context) => AlertDialog(
              title: Text(_strings.t('newVersion')),
              content: Text(
                '${_strings.t('currentVersion')} ${result.currentVersion}'
                '\n${_strings.t('newestVersion')} ${result.latestVersion}',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(_strings.t('later')),
                ),
                FilledButton.icon(
                  onPressed: () => Navigator.pop(context, true),
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: Text(_strings.t('openRelease')),
                ),
              ],
            ),
      );
      if (open == true) await _updateService.openRelease(result);
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${_strings.t('updateFailed')}：$error')),
        );
      }
    } finally {
      if (mounted) setState(() => _checkingUpdate = false);
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
            title: Text(_strings.t('logout')),
            content: Text(_strings.t('logoutMessage')),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(_strings.t('cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(_strings.t('logoutAction')),
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

  Future<void> _chooseLanguage() async {
    final selected = await showModalBottomSheet<Locale>(
      context: context,
      showDragHandle: true,
      builder:
          (context) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.translate_rounded),
                  title: Text(_strings.t('language')),
                ),
                for (final item in const [
                  (Locale('zh'), '中文'),
                  (Locale('en'), 'English'),
                  (Locale('ja'), '日本語'),
                ])
                  RadioListTile<String>(
                    value: item.$1.languageCode,
                    groupValue: widget.locale.languageCode,
                    title: Text(item.$2),
                    onChanged: (_) => Navigator.pop(context, item.$1),
                  ),
                const SizedBox(height: 12),
              ],
            ),
          ),
    );
    if (selected != null) widget.onLocaleChanged(selected);
  }

  Future<void> _chooseAppIcon() async {
    final selected = await showModalBottomSheet<AppIconStyle>(
      context: context,
      showDragHandle: true,
      builder:
          (context) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.apps_rounded),
                  title: Text(_strings.t('appIcon')),
                ),
                _IconChoice(
                  style: AppIconStyle.classic,
                  selected: widget.appIconStyle,
                  label: _strings.t('classicIcon'),
                  asset: 'assets/branding/app_icon_source.png',
                ),
                _IconChoice(
                  style: AppIconStyle.anime,
                  selected: widget.appIconStyle,
                  label: _strings.t('animeIcon'),
                  asset: 'assets/branding/app_icon_anime.png',
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
    );
    if (selected != null) widget.onAppIconStyleChanged(selected);
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
    final strings = AppLocalizations.of(context);
    final user = widget.authService?.user;
    return SafeArea(
      child: ContentFrame(
        maxWidth: 960,
        child: ListView(
          key: const PageStorageKey('profile-scroll'),
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 30),
          children: [
            PageHeader(
              title: strings.t('profile'),
              subtitle: strings.t('profileSubtitle'),
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
                              user?.displayName ?? strings.t('guestMode'),
                              style: const TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              user == null
                                  ? strings.t('loginSync')
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
                              label: Text(strings.t('login')),
                            )
                            : IconButton(
                              tooltip: strings.t('logout'),
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
                            value:
                                values == null
                                    ? '--'
                                    : '${values.subjects + widget.repository.pendingSubjectCollectionDelta}',
                            label: strings.t('collections'),
                          ),
                          _Stat(
                            value:
                                values == null
                                    ? '--'
                                    : '${values.characters + values.persons}',
                            label: strings.t('people'),
                          ),
                          _Stat(
                            value: values == null ? '--' : '${values.friends}',
                            label: strings.t('friends'),
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
            Text(
              strings.t('shortcuts'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _Shortcut(
                  icon: Icons.bookmarks_outlined,
                  label: strings.t('myCollections'),
                  onTap: () => _openMyProfile(1),
                ),
                _Shortcut(
                  icon: Icons.theater_comedy_outlined,
                  label: strings.t('characterCollections'),
                  onTap: () => _openMyProfile(2),
                ),
                _Shortcut(
                  icon: Icons.article_outlined,
                  label: strings.t('myBlogs'),
                  onTap: () => _openMyProfile(3),
                ),
                _Shortcut(
                  icon: Icons.list_alt_outlined,
                  label: strings.t('myIndexes'),
                  onTap: () => _openMyProfile(4),
                ),
                _Shortcut(
                  icon: Icons.people_outline_rounded,
                  label: strings.t('myFriends'),
                  onTap: () => _openMyProfile(5),
                ),
                _Shortcut(
                  icon: Icons.timeline_rounded,
                  label: strings.t('myTimeline'),
                  onTap: () => _openMyProfile(6),
                ),
                _Shortcut(
                  icon: Icons.bar_chart_rounded,
                  label: strings.t('myStats'),
                  onTap: () => _openMyProfile(7),
                ),
              ],
            ),
            const SizedBox(height: 26),
            Text(
              strings.t('account'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            SurfaceBlock(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.manage_accounts_outlined),
                    title: Text(strings.t('accountProfile')),
                    subtitle: Text(
                      user == null
                          ? strings.t('loginToManage')
                          : '@${user.username}',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: user == null ? _openLogin : () => _openMyProfile(0),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.privacy_tip_outlined),
                    title: Text(strings.t('privacy')),
                    subtitle: Text(strings.t('privacySubtitle')),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap:
                        () => ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(strings.t('privacyHint'))),
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            Text(
              strings.t('displayPerformance'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            SurfaceBlock(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.palette_outlined),
                    title: Text(strings.t('appearance')),
                    subtitle: Text(
                      Theme.of(context).brightness == Brightness.dark
                          ? strings.t('darkTheme')
                          : strings.t('lightTheme'),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: widget.onToggleTheme,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.translate_rounded),
                    title: Text(strings.t('language')),
                    subtitle: Text(strings.t('languageSubtitle')),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: _chooseLanguage,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(7),
                      child: Image.asset(
                        widget.appIconStyle == AppIconStyle.anime
                            ? 'assets/branding/app_icon_anime.png'
                            : 'assets/branding/app_icon_source.png',
                        width: 36,
                        height: 36,
                        fit: BoxFit.cover,
                      ),
                    ),
                    title: Text(strings.t('appIcon')),
                    subtitle: Text(
                      '${widget.appIconStyle == AppIconStyle.anime ? strings.t('animeIcon') : strings.t('classicIcon')} · '
                      '${Theme.of(context).platform == TargetPlatform.android ? strings.t('iconAndroidHint') : strings.t('iconDesktopHint')}',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: _chooseAppIcon,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.speed_rounded),
                    title: Text(strings.t('screenRefresh')),
                    subtitle: Text(strings.t('screenRefreshSubtitle')),
                    trailing: const Icon(Icons.check_circle_outline_rounded),
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    secondary: const Icon(Icons.play_circle_outline_rounded),
                    title: Text(strings.t('autoPlay')),
                    value: _autoPlay,
                    onChanged: (value) => setState(() => _autoPlay = value),
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    secondary: const Icon(Icons.animation_outlined),
                    title: Text(strings.t('reduceMotion')),
                    subtitle: Text(strings.t('reduceMotionSubtitle')),
                    value: _reduceMotion,
                    onChanged: (value) => setState(() => _reduceMotion = value),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            Text(
              strings.t('notifications'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            SurfaceBlock(
              padding: EdgeInsets.zero,
              child: SwitchListTile(
                secondary: const Icon(Icons.notifications_outlined),
                title: Text(strings.t('updateReminder')),
                subtitle: Text(strings.t('updateReminderSubtitle')),
                value: _notifications,
                onChanged: (value) => setState(() => _notifications = value),
              ),
            ),
            const SizedBox(height: 22),
            Text(
              strings.t('dataNetwork'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            SurfaceBlock(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.cleaning_services_outlined),
                    title: Text(strings.t('clearCache')),
                    subtitle: Text(strings.t('clearCacheSubtitle')),
                    trailing: const Icon(Icons.delete_sweep_outlined),
                    onTap: _clearImageCache,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.network_check_rounded),
                    title: Text(strings.t('networkDiagnostics')),
                    subtitle: Text(strings.t('networkDiagnosticsSubtitle')),
                    trailing: const Icon(Icons.play_arrow_rounded),
                    onTap: _testNetwork,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            Text(
              strings.t('about'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            SurfaceBlock(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.info_outline_rounded),
                    title: const Text('Bangumi Flutter'),
                    subtitle: FutureBuilder<String>(
                      future: _appVersion,
                      builder:
                          (_, snapshot) => Text(
                            '${strings.t('version')} ${snapshot.data ?? strings.t('loading')} · Android 11+ / Windows',
                          ),
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading:
                        _checkingUpdate
                            ? const Padding(
                              padding: EdgeInsets.all(3),
                              child: SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                            : const Icon(Icons.system_update_outlined),
                    title: Text(strings.t('checkUpdate')),
                    subtitle: Text(strings.t('checkUpdateSubtitle')),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: _checkingUpdate ? null : _checkUpdate,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.api_outlined),
                    title: Text(strings.t('dataSource')),
                    subtitle: const Text('Bangumi Next API · next.bgm.tv'),
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

class _IconChoice extends StatelessWidget {
  const _IconChoice({
    required this.style,
    required this.selected,
    required this.label,
    required this.asset,
  });

  final AppIconStyle style;
  final AppIconStyle selected;
  final String label;
  final String asset;

  @override
  Widget build(BuildContext context) => RadioListTile<AppIconStyle>(
    value: style,
    groupValue: selected,
    secondary: ClipRRect(
      borderRadius: BorderRadius.circular(9),
      child: Image.asset(asset, width: 46, height: 46, fit: BoxFit.cover),
    ),
    title: Text(label),
    onChanged: (value) => Navigator.pop(context, value),
  );
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
