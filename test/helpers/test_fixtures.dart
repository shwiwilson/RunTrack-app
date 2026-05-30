import 'package:flutter/material.dart';
import 'package:run_track_app/core/theme/club_theme_config.dart';
import 'package:run_track_app/core/theme/mock_themes.dart';
import 'package:run_track_app/features/achievements/domain/models/achievements_models.dart';
import 'package:run_track_app/features/activity/domain/models/activity_models.dart';
import 'package:run_track_app/features/club_hub/domain/models/club_models.dart';
import 'package:run_track_app/features/club_hub/domain/repositories/run_track_repository.dart';
import 'package:run_track_app/features/profile/domain/models/you_models.dart';

Widget themedTestApp(Widget child) {
  final theme = ClubThemeConfig.fromJson(tyneBridgeHarriersTheme).toThemeData();

  return MaterialApp(theme: theme, home: Scaffold(body: child));
}

ActivityFeedItem activityFixture({
  String title = 'Quayside tempo progression',
  String startDate = '2026-06-01T08:00:00.000',
  bool verifiedClubRun = true,
}) {
  return ActivityFeedItem(
    source: 'Strava',
    athleteInitials: 'SO',
    athleteName: 'Shane ONeill',
    title: title,
    subtitle: 'Negative split from the Swing Bridge',
    distance: '10.0 km',
    pace: '4:10/km',
    heartRate: '152 bpm',
    efficiencyFactor: '0.040',
    verifiedClubRun: verifiedClubRun,
    clusterLabel: verifiedClubRun ? 'TBH threshold group' : 'Solo',
    startDate: startDate,
    polyline: 'abc123',
  );
}

YouTabState readinessFixture() {
  return const YouTabState(
    athleteInitials: 'SO',
    athleteName: 'Shane ONeill',
    readinessScore: '86',
    readinessLabel: 'Productive',
    coachInsight: 'Vitals are stable and training load is balanced.',
    efficiencyLabel: 'Aerobic Efficiency',
    efficiencyValue: '0.040',
    efficiencyTrend: 'Best 14-day block',
    metrics: [
      BiometricMetric(
        label: 'HRV',
        value: '62 ms',
        trend: '+8%',
        status: 'Up',
      ),
      BiometricMetric(
        label: 'Sleep',
        value: '7h 42m',
        trend: '+31m',
        status: 'Solid',
      ),
    ],
    benchmarks: [
      BenchmarkMetric(label: '90d Fitness', value: 'Steady'),
      BenchmarkMetric(label: 'Weekly volume', value: '42.6 mi'),
    ],
  );
}

ClubSessionItem sessionFixture({
  String id = 'session-1',
  String currentUserRsvp = 'yes',
}) {
  return ClubSessionItem(
    id: id,
    title: 'Tuesday Intervals',
    description: '6 x 800m at controlled 10K effort.',
    date: 'Tue',
    time: '18:30',
    location: 'Churchill Track',
    athleteName: 'Maya Coach',
    attendees: const [
      ClubSessionAttendee(initials: 'SO', rsvpStatus: 'yes'),
      ClubSessionAttendee(initials: 'JT', rsvpStatus: 'maybe'),
    ],
    currentUserRsvp: currentUserRsvp,
  );
}

NewsletterStagingItem newsletterFixture() {
  return const NewsletterStagingItem(
    status: 'staged',
    description: 'Road relays briefing and vest collection.',
    date: 'Friday',
    time: '19:00',
    location: 'The Cycle Hub',
  );
}

AchievementsState achievementsFixture() {
  return const AchievementsState(
    raceResults: [
      RaceResultItem(
        event: 'North Tyneside 10K',
        result: 'Power of 10 verified',
        time: '36:42',
        rank: '-',
      ),
    ],
    challengeFlags: [
      ChallengeFlag(label: 'Sandbagger check', value: 'Clear', isAchieved: true),
    ],
    mapTiles: [
      MapBingoTileState(id: 'A1', label: 'A1', visited: true),
      MapBingoTileState(id: 'A2', label: 'A2', visited: false),
      MapBingoTileState(id: 'B1', label: 'B1', visited: false),
      MapBingoTileState(id: 'B2', label: 'B2', visited: true),
    ],
    bingoConfig: MapBingoConfig(
      centerLat: 54.9696,
      centerLng: -1.6018,
      zoom: 14,
      gridSize: 2,
    ),
    leaderboards: [
      LeaderboardPillState(
        id: 'ambassador',
        title: 'Club Ambassador',
        iconName: 'verified_user',
        userRank: 1,
        userValue: '4',
        unit: ' events',
        allEntries: [
          LeaderboardEntry(
            name: 'Shane ONeill',
            value: '4',
            isCurrentUser: true,
            rank: 1,
          ),
          LeaderboardEntry(name: 'Maya Coach', value: '3', rank: 2),
        ],
      ),
    ],
  );
}

class FakeRunTrackRepository implements RunTrackRepository {
  Map<String, dynamic> defaultClubProfile = {
    'id': 'club_tbh',
    'name': 'Tyne Bridge Harriers',
    'shortName': 'TBH',
    'theme_json': tyneBridgeHarriersTheme,
  };
  YouTabState readiness = readinessFixture();
  List<ActivityFeedItem> activities = [activityFixture()];
  List<ClubSessionItem> sessions = [sessionFixture()];
  List<NewsletterStagingItem> stagedItems = [newsletterFixture()];
  AchievementsState achievements = achievementsFixture();

  final readinessCalls = <({String clubId, String athleteId})>[];
  final activityClubIds = <String>[];
  final sessionClubIds = <String>[];
  final stagingClubIds = <String>[];
  final achievementClubIds = <String>[];
  final rsvpUpdates =
      <({String sessionId, String athleteId, String status})>[];

  @override
  Future<Map<String, dynamic>> fetchDefaultClubProfile() async {
    return defaultClubProfile;
  }

  @override
  Future<YouTabState> fetchReadiness(String clubId, String athleteId) async {
    readinessCalls.add((clubId: clubId, athleteId: athleteId));
    return readiness;
  }

  @override
  Future<List<ActivityFeedItem>> fetchActivities(String clubId) async {
    activityClubIds.add(clubId);
    return activities;
  }

  @override
  Future<List<ClubSessionItem>> fetchClubSessions(String clubId) async {
    sessionClubIds.add(clubId);
    return sessions;
  }

  @override
  Future<List<NewsletterStagingItem>> fetchNewsletterStaging(
    String clubId,
  ) async {
    stagingClubIds.add(clubId);
    return stagedItems;
  }

  @override
  Future<AchievementsState> fetchAchievements(String clubId) async {
    achievementClubIds.add(clubId);
    return achievements;
  }

  @override
  Future<void> updateRsvp(
    String sessionId,
    String athleteId,
    String status,
  ) async {
    rsvpUpdates.add((
      sessionId: sessionId,
      athleteId: athleteId,
      status: status,
    ));
  }
}
