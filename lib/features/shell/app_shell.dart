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
  });

  final BangumiRepository repository;
  final AuthService? authService;
  final ThemeMode themeMode;
  final VoidCallback onToggleTheme;
  final Locale locale;
  final ValueChanged<Locale> onLocaleChanged;
  final AppIconStyle appIconStyle;
  final ValueChanged<AppIconStyle> onAppIconStyleChanged;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;

  List<Widget> get _pages => [
    DiscoverPage(repository: widget.repository),
    TimelinePage(repository: widget.repository),
    BrowsePage(repository: widget.repository),
    RakuenPage(repository: widget.repository),
    ProfilePage(
      authService: widget.authService,
      repository: widget.repository,
      themeMode: widget.themeMode,
      onToggleTheme: widget.onToggleTheme,
      locale: widget.locale,
      onLocaleChanged: widget.onLocaleChanged,
      appIconStyle: widget.appIconStyle,
      onAppIconStyleChanged: widget.onAppIconStyleChanged,
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
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final destinations = _destinations(context);
    final strings = AppLocalizations.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final showRail = constraints.maxWidth >= 760;
        final extendRail = constraints.maxWidth >= 1180;
        final content = IndexedStack(index: _selectedIndex, children: _pages);

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
