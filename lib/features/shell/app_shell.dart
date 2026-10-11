import 'package:flutter/material.dart';

import '../../core/app_strings.dart';
import '../../core/auth/auth_service.dart';
import '../../core/localization/app_localizations.dart';
import '../../core/settings/app_preferences.dart';
import '../../data/bangumi_repository.dart';
import '../browse/browse_page.dart';
import '../discover/discover_page.dart';
import '../profile/profile_page.dart';
import '../rakuen/rakuen_page.dart';
import '../timeline/timeline_page.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.repository,
    required this.authService,
    required this.themeMode,
    required this.onToggleTheme,
    required this.locale,
    required this.onLocaleChanged,
    required this.appIconStyle,
    required this.onAppIconStyleChanged,
    this.reduceMotion = false,
    this.onReduceMotionChanged,
  });

  final BangumiRepository repository;
  final AuthService? authService;
  final ThemeMode themeMode;
  final VoidCallback onToggleTheme;
  final Locale locale;
  final ValueChanged<Locale> onLocaleChanged;
  final AppIconStyle appIconStyle;
  final ValueChanged<AppIconStyle> onAppIconStyleChanged;
  final bool reduceMotion;
  final ValueChanged<bool>? onReduceMotionChanged;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;
  int _sessionRevision = 0;
  final Set<int> _visited = {0};
  String _authIdentity = '';
  String get _identity =>
      '${widget.authService?.sessionEpoch}:${widget.authService?.user?.id}:${widget.authService?.user?.username}';

  @override
  void initState() {
    super.initState();
    _authIdentity = _identity;
    widget.authService?.addListener(_authChanged);
  }

  @override
  void didUpdateWidget(covariant AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.authService != widget.authService) {
      oldWidget.authService?.removeListener(_authChanged);
      widget.authService?.addListener(_authChanged);
      _authChanged();
    }
  }

  void _authChanged() {
    if (_identity == _authIdentity) return;
    _authIdentity = _identity;
    invalidateRepositoryCache(widget.repository);
    setState(() {
      _sessionRevision++;
    });
  }

  @override
  void dispose() {
    widget.authService?.removeListener(_authChanged);
    super.dispose();
  }

  List<Widget> _createPages() => [
    DiscoverPage(repository: widget.repository),
    TimelinePage(
      repository: widget.repository,
      sessionRevision: _sessionRevision,
    ),
    BrowsePage(repository: widget.repository),
    RakuenPage(
      repository: widget.repository,
      sessionRevision: _sessionRevision,
    ),
    ProfilePage(
      authService: widget.authService,
      repository: widget.repository,
      themeMode: widget.themeMode,
      onToggleTheme: widget.onToggleTheme,
      locale: widget.locale,
      onLocaleChanged: widget.onLocaleChanged,
      appIconStyle: widget.appIconStyle,
      onAppIconStyleChanged: widget.onAppIconStyleChanged,
      reduceMotion: widget.reduceMotion,
      onReduceMotionChanged: widget.onReduceMotionChanged,
    ),
  ];

  List<_AppDestination> _destinations(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return [
      _AppDestination(
        strings.t('discover'),
        Icons.home_rounded,
        Icons.home_outlined,
      ),
      _AppDestination(
        strings.t('timeline'),
        Icons.view_timeline_rounded,
        Icons.view_timeline_outlined,
      ),
      _AppDestination(
        strings.t('browse'),
        Icons.explore_rounded,
        Icons.explore_outlined,
      ),
      _AppDestination(
        strings.t('rakuen'),
        Icons.forum_rounded,
        Icons.forum_outlined,
      ),
      _AppDestination(
        strings.t('profile'),
        Icons.account_circle_rounded,
        Icons.account_circle_outlined,
      ),
    ];
  }

  void _select(int index) {
    if (index == _selectedIndex) return;
    setState(() {
      _selectedIndex = index;
      _visited.add(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    final destinations = _destinations(context);
    final strings = AppLocalizations.of(context);
    return PopScope(
      canPop: _selectedIndex == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _select(0);
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final showRail = constraints.maxWidth >= 760;
          final extendRail = constraints.maxWidth >= 1180;
          final pages = _createPages();
          final content = IndexedStack(
            index: _selectedIndex,
            children: [
              for (var index = 0; index < pages.length; index++)
                TickerMode(
                  enabled: index == _selectedIndex,
                  child:
                      _visited.contains(index)
                          ? pages[index]
                          : const SizedBox.shrink(),
                ),
            ],
          );

          if (!showRail) {
            return Scaffold(
              body: content,
              bottomNavigationBar: NavigationBar(
                selectedIndex: _selectedIndex,
                onDestinationSelected: _select,
                destinations: [
                  for (final item in destinations)
                    NavigationDestination(
                      icon: Icon(item.icon),
                      selectedIcon: Icon(item.selectedIcon),
                      label: item.label,
                    ),
                ],
              ),
            );
          }

          return Scaffold(
            body: Row(
              children: [
                NavigationRail(
                  extended: extendRail,
                  minExtendedWidth: 212,
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: _select,
                  groupAlignment: -0.35,
                  leading: Padding(
                    padding: const EdgeInsets.only(top: 14, bottom: 22),
                    child: _BrandMark(
                      showLabel: extendRail,
                      iconStyle: widget.appIconStyle,
                    ),
                  ),
                  trailing: Expanded(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 18),
                        child: IconButton(
                          tooltip: strings.t('toggleTheme'),
                          onPressed: widget.onToggleTheme,
                          icon: Icon(
                            Theme.of(context).brightness == Brightness.dark
                                ? Icons.light_mode_outlined
                                : Icons.dark_mode_outlined,
                          ),
                        ),
                      ),
                    ),
                  ),
                  destinations: [
                    for (final item in destinations)
                      NavigationRailDestination(
                        icon: Icon(item.icon),
                        selectedIcon: Icon(item.selectedIcon),
                        label: Text(item.label),
                      ),
                  ],
                ),
                VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: Theme.of(context).dividerColor,
                ),
                Expanded(child: content),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({required this.showLabel, required this.iconStyle});

  final bool showLabel;
  final AppIconStyle iconStyle;

  @override
  Widget build(BuildContext context) {
    final mark = ClipRRect(
      borderRadius: BorderRadius.circular(9),
      child: Image.asset(
        iconStyle == AppIconStyle.anime
            ? 'assets/branding/app_icon_anime.png'
            : 'assets/branding/app_icon_source.png',
        width: 38,
        height: 38,
        fit: BoxFit.cover,
      ),
    );
    if (!showLabel) return mark;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        const SizedBox(width: 12),
        Text(AppStrings.appName, style: Theme.of(context).textTheme.titleLarge),
      ],
    );
  }
}

class _AppDestination {
  const _AppDestination(this.label, this.selectedIcon, this.icon);

  final String label;
  final IconData selectedIcon;
  final IconData icon;
}
