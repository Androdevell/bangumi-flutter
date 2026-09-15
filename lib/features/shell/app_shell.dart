import 'package:flutter/material.dart';

import '../../core/app_strings.dart';
import '../../core/auth/auth_service.dart';
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
  });

  final BangumiRepository repository;
  final AuthService? authService;
  final ThemeMode themeMode;
  final VoidCallback onToggleTheme;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;

  static const _destinations = <_AppDestination>[
    _AppDestination(
      AppStrings.discover,
      Icons.home_rounded,
      Icons.home_outlined,
    ),
    _AppDestination(
      AppStrings.timeline,
      Icons.view_timeline_rounded,
      Icons.view_timeline_outlined,
    ),
    _AppDestination(
      AppStrings.browse,
      Icons.explore_rounded,
      Icons.explore_outlined,
    ),
    _AppDestination(
      AppStrings.rakuen,
      Icons.forum_rounded,
      Icons.forum_outlined,
    ),
    _AppDestination(
      AppStrings.profile,
      Icons.account_circle_rounded,
      Icons.account_circle_outlined,
    ),
  ];

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
    ),
  ];

  void _select(int index) {
    if (index == _selectedIndex) return;
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final showRail = constraints.maxWidth >= 760;
        final extendRail = constraints.maxWidth >= 1180;
        final content = _AnimatedPage(
          pageKey: ValueKey(_selectedIndex),
          child: _pages[_selectedIndex],
        );

        if (!showRail) {
          return Scaffold(
            body: content,
            bottomNavigationBar: NavigationBar(
              selectedIndex: _selectedIndex,
              onDestinationSelected: _select,
              destinations: [
                for (final item in _destinations)
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
                  child: _BrandMark(showLabel: extendRail),
                ),
                trailing: Expanded(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 18),
                      child: IconButton(
                        tooltip: '切换主题',
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
                  for (final item in _destinations)
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

class _AnimatedPage extends StatelessWidget {
  const _AnimatedPage({required this.pageKey, required this.child});

  final Key pageKey;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        final offset = Tween<Offset>(
          begin: const Offset(0.025, 0),
          end: Offset.zero,
        ).animate(animation);
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(position: offset, child: child),
        );
      },
      child: KeyedSubtree(key: pageKey, child: child),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({required this.showLabel});

  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final mark = Container(
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Text(
        'B',
        style: TextStyle(
          color: Colors.white,
          fontSize: 22,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
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
