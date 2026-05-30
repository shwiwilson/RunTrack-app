import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:run_track_app/features/achievements/presentation/view_models/achievements_view_model.dart';
import 'package:run_track_app/features/activity/presentation/view_models/run_track_view_model.dart';
import 'package:run_track_app/features/club_hub/presentation/view_models/club_hub_view_model.dart';
import 'package:run_track_app/features/profile/presentation/view_models/you_view_model.dart';
import 'package:run_track_app/features/club_hub/domain/repositories/run_track_repository.dart';
import 'package:run_track_app/data/repositories/mock_run_track_repository.dart';
import 'package:run_track_app/data/mock_data/funny_messages.dart';
import 'package:run_track_app/data/mock_data/mock_database.dart';
import 'package:run_track_app/core/theme/club_theme_config.dart';
import 'package:run_track_app/core/theme/theme_controller.dart';
import 'package:run_track_app/run_track_shell.dart';

final ValueNotifier<bool> useMocksNotifier = ValueNotifier<bool>(true);

void main() async {
  // Required for accessing platform channels (like SharedPreferences) before runApp
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  final repository = MockRunTrackRepository();

  runApp(
    RunTrackApp(
      viewModel: RunTrackAppViewModel(repository: repository, prefs: prefs),
    ),
  );
}

/// A global scroll behavior that removes the Android 12+ "stretch" effect
/// and ensures a consistent, stop-at-the-edge feel across all platforms.
class GlobalScrollBehavior extends MaterialScrollBehavior {
  const GlobalScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const ClampingScrollPhysics();
  }
}

@immutable
class RunTrackAppState {
  const RunTrackAppState({
    required this.clubName,
    required this.clubShortName,
    required this.activeClubTheme,
    required this.selectedTabIndex,
    required this.athleteId,
  });

  final String clubName;
  final String clubShortName;
  final ClubThemeConfig activeClubTheme;
  final int selectedTabIndex;
  final String? athleteId;
}

class RunTrackAppViewModel extends ChangeNotifier {
  factory RunTrackAppViewModel({
    required RunTrackRepository repository,
    required SharedPreferences prefs,
  }) {
    return RunTrackAppViewModel._(repository, prefs);
  }

  RunTrackAppViewModel._(this._repository, this._prefs) {
    _init();
  }

  Future<void> _init() async {
    try {
      // Load the persistent athlete ID on startup
      _athleteId = _prefs.getString(_athleteKey);

      // Ensure the mock database "logged in" user matches the persisted athlete ID
      if (_athleteId != null) {
        try {
          MockDatabase.currentUser = MockDatabase.clubMembers.firstWhere(
            (u) => u.id == _athleteId,
          );
        } catch (e) {
          debugPrint(
            'Persistence sync: Athlete $_athleteId not found in mock DB: $e',
          );
        }
      }

      _isLoggingIn = false;

      final clubProfile = await _repository.fetchDefaultClubProfile();
      _clubId = clubProfile['id'] as String;
      _clubName = clubProfile['name'] as String;
      _clubShortName = clubProfile['shortName'] as String;
      _clubTheme = ClubThemeConfig.fromJson(
        clubProfile['theme_json'] as Map<String, dynamic>,
      );

      youViewModel = YouViewModel(
        repository: _repository,
        clubId: _clubId,
        athleteId: _athleteId ?? '',
      );
      runTrackViewModel = RunTrackViewModel(
        repository: _repository,
        clubId: _clubId,
      );
      clubHubViewModel = ClubHubViewModel(
        repository: _repository,
        clubId: _clubId,
        athleteId: _athleteId,
      );
      achievementsViewModel = AchievementsViewModel(
        repository: _repository,
        clubId: _clubId,
      );

      // Only load state if we actually have an active athlete logged in.
      if (_athleteId != null) {
        await Future.wait([
          youViewModel.loadState(),
          runTrackViewModel.loadState(),
          clubHubViewModel.loadState(),
          achievementsViewModel.loadState(),
        ]);
      }

      _updateDailyFunnyMessage();
    } catch (e) {
      debugPrint('Error initializing app: $e');
    } finally {
      _isInitializing = false;
      notifyListeners();
    }
  }

  final RunTrackRepository _repository;
  final SharedPreferences _prefs;
  static const _athleteKey = 'active_athlete_id';
  static const _funnyMessageKey = 'today_funny_message';

  late String _clubId;
  late String _clubName;
  late String _clubShortName;
  late ClubThemeConfig _clubTheme;
  int _selectedTabIndex = 0;
  String? _athleteId;
  bool _isLoggingIn = false;
  bool _isInitializing = true;

  bool get isInitializing => _isInitializing;
  String? _dailyFunnyMessage;
  String get dailyFunnyMessage =>
      _dailyFunnyMessage ?? "Rest day? Or just resting your soul?";

  late YouViewModel youViewModel;
  late RunTrackViewModel runTrackViewModel;
  late ClubHubViewModel clubHubViewModel;
  late AchievementsViewModel achievementsViewModel;

  /// Logic to select exactly one funny message per day, rotating through the 250 options
  /// without repeats until the entire list has been shown.
  void _updateDailyFunnyMessage() {
    final now = DateTime.now();
    final todayStr = "${now.year}-${now.month}-${now.day}";
    final lastUpdate = _prefs.getString('last_funny_message_date');

    if (lastUpdate == todayStr) {
      _dailyFunnyMessage = _prefs.getString(_funnyMessageKey);
      if (_dailyFunnyMessage != null) return;
    }

    // Get the current queue of indices
    List<String> queue = _prefs.getStringList('funny_message_queue') ?? [];

    // If queue is empty, generate all 250 indices and shuffle them
    if (queue.isEmpty) {
      final indices = List<int>.generate(clubFunnyMessages.length, (i) => i);
      indices.shuffle();
      queue = indices.map((i) => i.toString()).toList();
    }

    // Take the first index from the shuffled queue
    final nextIndexStr = queue.removeAt(0);
    final nextIndex = int.parse(nextIndexStr);
    final message = clubFunnyMessages[nextIndex];

    // Save state: The remaining queue, the chosen message, and today's date
    _prefs.setStringList('funny_message_queue', queue);
    _prefs.setString(_funnyMessageKey, message);
    _prefs.setString('last_funny_message_date', todayStr);

    _dailyFunnyMessage = message;
  }

  bool get isLoggingIn => _isLoggingIn;

  RunTrackAppState get state {
    return RunTrackAppState(
      clubName: _clubName,
      clubShortName: _clubShortName,
      activeClubTheme: _clubTheme,
      selectedTabIndex: _selectedTabIndex,
      athleteId: _athleteId,
    );
  }

  void selectTab(int index) {
    _selectedTabIndex = index;
    if (index == 2) {
      debugPrint('--- DEBUG: Navigated to Club Page ---');
      debugPrint('Active Club: $_clubName (ID: $_clubId)');
      debugPrint('Member List:');
      final members = MockDatabase.clubMembers.where(
        (u) => u.clubId == _clubId,
      );
      for (final member in members) {
        debugPrint('  - ${member.fullName} (Club: ${member.clubId})');
      }

      final sessions = clubHubViewModel.state?.sessions ?? [];
      for (final session in sessions) {
        debugPrint('RSVP Status for Session: "${session.title}"');
        for (final attendee in session.attendees) {
          debugPrint('  - ${attendee.initials}: ${attendee.rsvpStatus}');
        }
      }
    }
    notifyListeners();
  }

  /// Performs a "hard" refresh of the current tab by clearing any local
  /// repository caches and re-running the entire app initialization sequence.
  /// This mimics a browser-style reload by returning to the loading state.
  Future<void> refreshCurrentTab() async {
    _isInitializing = true;
    notifyListeners();

    // If we are using the mock repository, we need to clear its internal
    // activity cache to ensure a "first-time" loading experience.
    if (_repository is MockRunTrackRepository) {
      (_repository).clearCache();
    }

    await _init();
  }

  /// Mock implementation of Strava Login
  Future<void> loginWithStrava(String athleteId) async {
    _isLoggingIn = true;
    notifyListeners();

    // Simulate network delay and OAuth redirect
    await Future.delayed(const Duration(seconds: 2));

    _athleteId = athleteId;

    // Clear the repository cache to ensure the new club's activities are loaded
    if (_repository is MockRunTrackRepository) {
      (_repository).clearCache();
    }

    // Persist the ID so the user stays logged in
    await _prefs.setString(_athleteKey, _athleteId!);

    // Re-initialize state based on the new athlete
    await _init();

    _isLoggingIn = false;
    notifyListeners();
  }

  Future<void> logout() async {
    _athleteId = null;
    await _prefs.remove(_athleteKey);

    // Reset mock database current user to default (Shane O'Neill)
    MockDatabase.currentUser = MockDatabase.clubMembers[0];

    // Clear the repository cache on logout
    if (_repository is MockRunTrackRepository) {
      (_repository).clearCache();
    }

    notifyListeners();
  }
}

class RunTrackApp extends StatelessWidget {
  const RunTrackApp({required this.viewModel, super.key});

  final RunTrackAppViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([viewModel, ThemeController.instance]),
      builder: (context, _) {
        if (viewModel.isInitializing) {
          return const MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              backgroundColor: Color(0xFF000000),
              body: Center(
                child: CircularProgressIndicator(color: Colors.white24),
              ),
            ),
          );
        }

        final appState = viewModel.state;

        return MaterialApp(
          scrollBehavior: const GlobalScrollBehavior(),
          title: appState.clubName,
          debugShowCheckedModeBanner: false,
          theme: appState.activeClubTheme.toThemeData(),
          darkTheme: ThemeData.dark().copyWith(
            brightness: Brightness.dark,
            colorScheme: ColorScheme.fromSeed(
              seedColor: appState.activeClubTheme
                  .toThemeData()
                  .colorScheme
                  .primary,
              brightness: Brightness.dark,
              surface: const Color(0xFF000000),
              onSurface: Colors.white,
            ),
            scaffoldBackgroundColor: const Color(0xFF000000),
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFF000000),
              elevation: 0,
            ),
            bottomNavigationBarTheme: BottomNavigationBarThemeData(
              backgroundColor: const Color(0xFF080808),
              unselectedItemColor: Colors.white54,
              type: BottomNavigationBarType.fixed,
              elevation: 8,
            ),
          ),
          themeMode: ThemeController.instance.themeMode,
          // AUTH GATE: Only show the shell if an athlete is logged in
          home: appState.athleteId == null
              ? StravaLoginPage(viewModel: viewModel)
              : RunTrackShell(
                  key: ValueKey(appState.athleteId),
                  viewModel: viewModel,
                  appState: appState,
                ),
        );
      },
    );
  }
}

class StravaLoginPage extends StatefulWidget {
  const StravaLoginPage({required this.viewModel, super.key});

  final RunTrackAppViewModel viewModel;

  @override
  State<StravaLoginPage> createState() => _StravaLoginPageState();
}

class _StravaLoginPageState extends State<StravaLoginPage> {
  MockClub? _selectedClub;
  MockUser? _selectedUser;

  @override
  void initState() {
    super.initState();
    _selectedClub = MockDatabase.clubs.first;
    _updateSelectionForClub(_selectedClub!);
  }

  void _updateSelectionForClub(MockClub club) {
    final members = MockDatabase.clubMembers
        .where((u) => u.clubId == club.id)
        .toList();
    _selectedUser = members.isNotEmpty ? members.first : null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: ListenableBuilder(
        listenable: widget.viewModel,
        builder: (context, _) {
          final clubMembers = MockDatabase.clubMembers
              .where((u) => u.clubId == _selectedClub?.id)
              .toList();

          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.directions_run,
                    size: 80,
                    color: Color(0xFFFC4C02),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'RUNTRACK',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Connect your profile to access the club hub',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 40),
                  DropdownButtonFormField<MockClub>(
                    initialValue: _selectedClub,
                    dropdownColor: colorScheme.surface,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: colorScheme.onSurface,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Select Club (Mock)',
                      labelStyle: TextStyle(
                        color: colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                      prefixIcon: Icon(
                        Icons.groups_outlined,
                        color: colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                    items: MockDatabase.clubs.map((club) {
                      return DropdownMenuItem(
                        value: club,
                        child: Text(club.name),
                      );
                    }).toList(),
                    onChanged: (club) {
                      if (club != null) {
                        setState(() {
                          _selectedClub = club;
                          _updateSelectionForClub(club);
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<MockUser>(
                    initialValue: _selectedUser,
                    dropdownColor: colorScheme.surface,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: colorScheme.onSurface,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Select Athlete (Mock)',
                      labelStyle: TextStyle(
                        color: colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                      prefixIcon: Icon(
                        Icons.person_outline,
                        color: colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                    items: clubMembers.map((user) {
                      return DropdownMenuItem(
                        value: user,
                        child: Text(user.fullName),
                      );
                    }).toList(),
                    onChanged: (user) => setState(() => _selectedUser = user),
                  ),
                  const SizedBox(height: 32),
                  if (widget.viewModel.isLoggingIn)
                    CircularProgressIndicator(color: colorScheme.primary)
                  else
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _selectedUser == null
                            ? null
                            : () {
                                // Mock the OAuth response by setting the current user
                                MockDatabase.currentUser = _selectedUser!;
                                widget.viewModel.loginWithStrava(
                                  _selectedUser!.id,
                                );
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(
                            0xFFFC4C02,
                          ), // Strava Orange
                          foregroundColor: Colors.white,
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.bolt),
                            SizedBox(width: 12),
                            Text(
                              'CONNECT WITH STRAVA',
                              style: TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  Text(
                    'OAuth Stub: This simulates the response from the Strava API.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 11,
                      color: colorScheme.onSurface.withValues(alpha: 0.4),
                      fontStyle: FontStyle.italic,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
