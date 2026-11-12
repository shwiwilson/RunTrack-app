import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:run_track_app/core/theme/club_theme_config.dart';
import 'package:run_track_app/core/theme/theme_controller.dart';
import 'package:run_track_app/data/repositories/supabase_run_track_repository.dart';
import 'package:run_track_app/features/application/run_track_controller.dart';
import 'package:run_track_app/features/achievements/presentation/views/achievements_view.dart';
import 'package:run_track_app/features/activity/presentation/views/run_track_view.dart';
import 'package:run_track_app/features/club_hub/presentation/views/club_hub_view.dart';
import 'package:run_track_app/features/profile/presentation/views/you_tab.dart';
import 'package:run_track_app/features/shared/feature_widgets.dart';

class RunTrackShell extends StatelessWidget {
  const RunTrackShell({
    required this.client,
    required this.onConnectHealth,
    required this.onAccount,
    required this.onJoinClub,
    required this.onSignOut,
    super.key,
  });
  final SupabaseClient client;
  final VoidCallback onConnectHealth;
  final VoidCallback onAccount;
  final VoidCallback onJoinClub;
  final Future<void> Function() onSignOut;
  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) =>
        RunTrackController(SupabaseRunTrackRepository(client))..refresh(),
    child: Consumer<RunTrackController>(
      builder: (context, controller, _) {
        final data = controller.snapshot;
        final body = controller.loading
            ? const Center(child: CircularProgressIndicator())
            : data == null
            ? FeaturePage(
                children: [
                  EmptyFeature(
                    icon: Icons.cloud_off_outlined,
                    title: 'Unable to connect',
                    message:
                        controller.error ?? 'Your data could not be loaded.',
                    actionLabel: 'Try again',
                    onAction: controller.refresh,
                  ),
                ],
              )
            : switch (controller.selectedTab) {
                0 => YouTabScreen(
                  data: data,
                  onConnectHealth: onConnectHealth,
                  onAccount: onAccount,
                ),
                1 => RunTrackView(
                  data: data,
                  controller: controller,
                  onConnectHealth: onConnectHealth,
                ),
                2 => ClubHubView(
                  data: data,
                  controller: controller,
                  onJoinClub: onJoinClub,
                ),
                _ => AchievementsView(data: data, controller: controller),
              };
        Widget scaffold = Scaffold(
          appBar: AppBar(
            title: Text(
              data?.membership?.clubName ?? 'RunTrack',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            actions: [
              IconButton(
                tooltip: 'Refresh data',
                onPressed: controller.loading || controller.saving
                    ? null
                    : controller.refresh,
                icon: const Icon(Icons.refresh),
              ),
              IconButton(
                tooltip: 'Account settings',
                onPressed: onAccount,
                icon: const Icon(Icons.person_outline),
              ),
              IconButton(
                tooltip: 'Sign out',
                onPressed: onSignOut,
                icon: const Icon(Icons.logout_outlined),
              ),
              IconButton(
                tooltip: 'Toggle theme',
                onPressed: () => ThemeController.instance.toggleTheme(
                  Theme.of(context).brightness != Brightness.dark,
                ),
                icon: const Icon(Icons.brightness_6_outlined),
              ),
            ],
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: Column(
                children: [
                  if (controller.saving)
                    const LinearProgressIndicator(minHeight: 2),
                  if (controller.error != null &&
                      data != null &&
                      !controller.loading)
                    MaterialBanner(
                      content: Text(controller.error!),
                      actions: [
                        TextButton(
                          onPressed: controller.refresh,
                          child: const Text('Reload'),
                        ),
                      ],
                    ),
                  Expanded(child: body),
                ],
              ),
            ),
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: controller.selectedTab,
            onDestinationSelected: controller.selectTab,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person),
                label: 'You',
              ),
              NavigationDestination(
                icon: Icon(Icons.directions_run_outlined),
                selectedIcon: Icon(Icons.directions_run),
                label: 'RunTrack',
              ),
              NavigationDestination(
                icon: Icon(Icons.groups_outlined),
                selectedIcon: Icon(Icons.groups),
                label: 'Club',
              ),
              NavigationDestination(
                icon: Icon(Icons.emoji_events_outlined),
                selectedIcon: Icon(Icons.emoji_events),
                label: 'Achievements',
              ),
            ],
          ),
        );
        final clubTheme = data?.membership?.theme;
        if (clubTheme != null && clubTheme.isNotEmpty) {
          final config = ClubThemeConfig.fromJson(clubTheme);
          scaffold = Theme(data: config.toThemeData(), child: scaffold);
        }
        return scaffold;
      },
    ),
  );
}
