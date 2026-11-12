import 'package:run_track_app/features/activity/domain/models/activity_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:run_track_app/features/achievements/presentation/views/achievements_view.dart';
import 'package:run_track_app/features/activity/presentation/views/run_track_view.dart';
import 'package:run_track_app/features/application/run_track_controller.dart';
import 'package:run_track_app/features/club_hub/presentation/views/club_hub_view.dart';
import 'package:run_track_app/features/profile/presentation/views/you_tab.dart';
import '../helpers.dart';

class PrivacyRepository extends TestRepository {
  bool revoked = false;
  @override
  Future<void> shareActivity(String id, String? clubId) async {
    revoked = clubId == null;
  }
}

void main() {
  testWidgets('dashboard offers data connection without invented metrics', (
    tester,
  ) async {
    var connect = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: YouTabScreen(
            data: emptySnapshot(),
            onConnectHealth: () => connect = true,
            onAccount: () {},
          ),
        ),
      ),
    );
    expect(find.text('No runs recorded yet'), findsOneWidget);
    expect(find.text('Morning readiness'), findsNothing);
    await tester.tap(find.text('Connect your running data').first);
    expect(connect, isTrue);
    expect(tester.takeException(), isNull);
  });
  testWidgets('empty feed does not present simulated sync success', (
    tester,
  ) async {
    final controller = RunTrackController(TestRepository());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RunTrackView(
            data: emptySnapshot(),
            controller: controller,
            onConnectHealth: () {},
          ),
        ),
      ),
    );
    expect(find.text('No runs recorded yet'), findsOneWidget);
    expect(find.textContaining('Synced'), findsNothing);
    controller.dispose();
  });
  testWidgets('unassigned athlete can retry club joining', (tester) async {
    var join = false;
    final controller = RunTrackController(TestRepository());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ClubHubView(
            data: emptySnapshot(),
            controller: controller,
            onJoinClub: () => join = true,
          ),
        ),
      ),
    );
    expect(find.text("You're not in a club yet"), findsOneWidget);
    await tester.tap(find.text('Enter joining code'));
    expect(join, isTrue);
    controller.dispose();
  });
  testWidgets('administrator with no sessions can create the first session', (
    tester,
  ) async {
    final repository = TestRepository()..data = emptySnapshot(admin: true);
    final controller = RunTrackController(repository);
    await controller.refresh();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ClubHubView(
            data: repository.data,
            controller: controller,
            onJoinClub: () {},
          ),
        ),
      ),
    );
    expect(find.text('No club sessions scheduled'), findsOneWidget);
    await tester.tap(find.text('Create first session'));
    await tester.pumpAndSettle();
    expect(find.text('Create club session'), findsOneWidget);
    expect(find.text('Save session'), findsOneWidget);
    expect(tester.takeException(), isNull);
    controller.dispose();
  });
  testWidgets('zero history has unearned achievement experience', (
    tester,
  ) async {
    final controller = RunTrackController(TestRepository());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AchievementsView(data: emptySnapshot(), controller: controller),
        ),
      ),
    );
    expect(find.text('Your running achievements start here'), findsOneWidget);
    expect(find.textContaining('0 earned'), findsOneWidget);
    expect(find.text('Map bingo'), findsNothing);
    expect(tester.takeException(), isNull);
    controller.dispose();
  });
  testWidgets('empty feature screens fit a narrow mobile viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = TestRepository();
    final controller = RunTrackController(repository);
    for (final screen in <Widget>[
      YouTabScreen(
        data: repository.data,
        onConnectHealth: () {},
        onAccount: () {},
      ),
      RunTrackView(
        data: repository.data,
        controller: controller,
        onConnectHealth: () {},
      ),
      ClubHubView(
        data: repository.data,
        controller: controller,
        onJoinClub: () {},
      ),
      AchievementsView(data: repository.data, controller: controller),
    ]) {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: screen)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    controller.dispose();
  });
  testWidgets('removed members can revoke a previously shared activity', (
    tester,
  ) async {
    final repository = PrivacyRepository()
      ..data = emptySnapshot(
        activities: [
          Activity(
            id: 'old-shared-run',
            userId: 'test-user',
            provider: 'test_only',
            providerWorkoutId: '1',
            type: 'running',
            startedAt: DateTime(2026, 11, 1),
            endedAt: DateTime(2026, 11, 1, 1),
            visibility: 'club',
            sharedClubId: 'previous-club',
          ),
        ],
      );
    final controller = RunTrackController(repository);
    await controller.refresh();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RunTrackView(
            data: repository.data,
            controller: controller,
            onConnectHealth: () {},
          ),
        ),
      ),
    );
    expect(find.text('Shared with a previous club'), findsOneWidget);
    final switchTile = find.byType(SwitchListTile);
    await tester.ensureVisible(switchTile);
    expect(tester.widget<SwitchListTile>(switchTile).onChanged, isNotNull);
    await tester.tap(switchTile);
    await tester.pumpAndSettle();
    expect(repository.revoked, isTrue);
    controller.dispose();
  });
  testWidgets('club management handles removal of the current administrator', (
    tester,
  ) async {
    final repository = TestRepository()..data = emptySnapshot(admin: true);
    final controller = RunTrackController(repository);
    await controller.refresh();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ClubHubView(
            data: repository.data,
            controller: controller,
            onJoinClub: () {},
          ),
        ),
      ),
    );
    await tester.tap(find.text('Manage club'));
    await tester.pumpAndSettle();
    expect(find.text('Memberships'), findsOneWidget);
    await controller.mutate(() async {
      repository.data = emptySnapshot();
    });
    await tester.pumpAndSettle();
    expect(find.text('Club access updated'), findsOneWidget);
    expect(tester.takeException(), isNull);
    controller.dispose();
  });
}
