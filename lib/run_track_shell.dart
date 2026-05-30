import 'package:flutter/material.dart';
import 'package:run_track_app/main.dart';
import 'package:run_track_app/core/theme/club_theme_config.dart';
import 'package:run_track_app/core/theme/theme_controller.dart';
import 'package:run_track_app/features/achievements/presentation/views/achievements_view.dart';
import 'package:run_track_app/features/activity/presentation/views/run_track_view.dart';
import 'package:run_track_app/features/club_hub/presentation/views/club_hub_view.dart';
import 'package:run_track_app/features/profile/presentation/views/you_tab.dart';

class RunTrackShell extends StatefulWidget {
  const RunTrackShell({
    required this.viewModel,
    required this.appState,
    super.key,
  });

  final RunTrackAppViewModel viewModel;
  final RunTrackAppState appState;

  @override
  State<RunTrackShell> createState() => _RunTrackShellState();
}

class _RunTrackShellState extends State<RunTrackShell> {
  late final List<_ShellTab> _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = [
      _ShellTab(
        title: 'You',
        icon: Icons.person_outline,
        activeIcon: Icons.person,
        view: YouTabScreen(
          viewModel: widget.viewModel.youViewModel,
          onLogout: widget.viewModel.logout,
        ),
      ),
      _ShellTab(
        title: 'RunTrack',
        icon: Icons.directions_run_outlined,
        activeIcon: Icons.directions_run,
        view: RunTrackView(
          viewModel: widget.viewModel.runTrackViewModel,
          dailyMessage: widget.viewModel.dailyFunnyMessage,
        ),
      ),
      _ShellTab(
        title: 'Club',
        icon: Icons.groups_outlined,
        activeIcon: Icons.groups,
        view: ClubHubView(viewModel: widget.viewModel.clubHubViewModel),
      ),
      _ShellTab(
        title: 'Achievements',
        icon: Icons.emoji_events_outlined,
        activeIcon: Icons.emoji_events,
        view: AchievementsView(
          viewModel: widget.viewModel.achievementsViewModel,
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ClubThemeTokens.of(context);
    final theme = Theme.of(context);
    final onAppBar =
        theme.appBarTheme.foregroundColor ?? theme.colorScheme.onSurface;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.refresh),
          color: onAppBar,
          onPressed: widget.viewModel.refreshCurrentTab,
        ),
        title: Text(
          widget.appState.clubName,
          style: theme.textTheme.titleLarge?.copyWith(color: onAppBar),
        ),
        actions: [
          ListenableBuilder(
            listenable: ThemeController.instance,
            builder: (context, _) {
              final isDark = ThemeController.instance.isDarkMode;
              return IconButton(
                icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode),
                onPressed: () => ThemeController.instance.toggleTheme(!isDark),
                color: onAppBar,
              );
            },
          ),
        ],
      ),
      body: IndexedStack(
        index: widget.appState.selectedTabIndex,
        children: [for (final tab in _tabs) tab.view],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: tokens.strokeColor)),
        ),
        child: BottomNavigationBar(
          currentIndex: widget.appState.selectedTabIndex,
          onTap: widget.viewModel.selectTab,
          type: BottomNavigationBarType.fixed,
          items: [
            for (final tab in _tabs)
              BottomNavigationBarItem(
                icon: Icon(tab.icon),
                activeIcon: Icon(tab.activeIcon),
                label: tab.title,
              ),
          ],
        ),
      ),
    );
  }
}

class _ShellTab {
  const _ShellTab({
    required this.title,
    required this.icon,
    required this.activeIcon,
    required this.view,
  });
  final String title;
  final IconData icon;
  final IconData activeIcon;
  final Widget view;
}
