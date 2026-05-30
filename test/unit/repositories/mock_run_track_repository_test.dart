import 'package:flutter_test/flutter_test.dart';
import 'package:run_track_app/data/repositories/mock_run_track_repository.dart';

void main() {
  group('MockRunTrackRepository', () {
    final repository = MockRunTrackRepository();

    test('fetches the default club profile', () async {
      final profile = await repository.fetchDefaultClubProfile();

      expect(profile['id'], 'club_tbh');
      expect(profile['name'], 'Tyne Bridge Harriers');
      expect(profile['shortName'], 'TBH');
      expect(profile['theme_json'], isA<Map<String, dynamic>>());
    });

    test(
      'fetches readiness data with joined athlete profile details',
      () async {
        final readiness = await repository.fetchReadiness(
          'club_tbh',
          'athlete_demo',
        );

        expect(readiness.athleteName, isNotEmpty);
        expect(readiness.athleteInitials, isNotEmpty);
        expect(readiness.athleteImageUrl, isNotEmpty);
        expect(readiness.readinessScore, isNotEmpty);
        expect(readiness.readinessLabel, isNotEmpty);
        expect(readiness.coachInsight, isNotEmpty);
        expect(readiness.efficiencyLabel, isNotEmpty);
        expect(double.tryParse(readiness.efficiencyValue), isNotNull);
        expect(readiness.efficiencyTrend, isNotEmpty);
        expect(readiness.metrics, isNotEmpty);
        expect(readiness.benchmarks, isNotEmpty);
      },
    );

    test('fetches activities for the requested club only', () async {
      final activities = await repository.fetchActivities('club_tbh');

      expect(activities, isNotEmpty);
      expect(
        activities,
        contains(
          predicate((activity) {
            final item = activity as dynamic;
            return item.title == 'Quayside tempo progression' &&
                item.source == 'Strava' &&
                item.verifiedClubRun == true &&
                item.clusterLabel == 'TBH threshold group';
          }),
        ),
      );
      for (final activity in activities) {
        expect(activity.title, isNotEmpty);
        expect(activity.source, isNotEmpty);
        expect(activity.athleteName, isNotEmpty);
        expect(activity.distance, isNotEmpty);
        expect(activity.startDate, isNotEmpty);
      }
      final unknownActivities = await repository.fetchActivities(
        'club_unknown',
      );
      expect(unknownActivities, isEmpty);
    });

    test('fetches club sessions with joined attendee avatars', () async {
      final sessions = await repository.fetchClubSessions('club_tbh');

      expect(sessions, hasLength(2));
      expect(sessions.first.title, 'Tuesday Intervals');
      expect(
        sessions.first.description,
        '6 x 800m at controlled 10K effort with rolling recovery.',
      );
      expect(sessions.first.date, 'Tue');
      expect(sessions.first.time, '18:30');
      expect(sessions.first.location, 'Churchill Track');
      expect(sessions.first.id, 'session_tbh_tue');
      expect(sessions.first.attendees, hasLength(6));
      expect(sessions.first.attendees.first.initials, 'SM');
      expect(sessions.first.attendees.first.imageUrl, isNotEmpty);
      expect(sessions.first.attendees.first.rsvpStatus, 'yes');
      expect(sessions.first.currentUserRsvp, 'yes');
      final unknownSessions = await repository.fetchClubSessions(
        'club_unknown',
      );
      expect(unknownSessions, isEmpty);
    });

    test(
      'fetches newsletter staging items for the requested club only',
      () async {
        final stagedItems = await repository.fetchNewsletterStaging('club_tbh');

        expect(stagedItems, hasLength(1));
        expect(stagedItems.single.status, 'staged');
        expect(
          stagedItems.single.description,
          'Road relays briefing and vest collection.',
        );
        expect(stagedItems.single.date, 'Friday');
        expect(stagedItems.single.time, '19:00');
        expect(stagedItems.single.location, 'The Cycle Hub');
        final unknownStaged = await repository.fetchNewsletterStaging(
          'club_unknown',
        );
        expect(unknownStaged, isEmpty);
      },
    );

    test('fetches achievements for the club', () async {
      final achievements = await repository.fetchAchievements('club_tbh');

      expect(achievements.raceResults, hasLength(2));
      expect(achievements.challengeFlags, hasLength(2));
      expect(achievements.mapTiles, hasLength(16));
      expect(achievements.bingoConfig.gridSize, 4);
      expect(achievements.leaderboards, hasLength(9));
      expect(achievements.leaderboards.first.id, 'ambassador');
      expect(achievements.leaderboards.first.allEntries, isNotEmpty);
    });

    test(
      'throws when achievements are requested for an unknown club',
      () async {
        expect(
          repository.fetchAchievements('club_unknown'),
          throwsA(isA<StateError>()),
        );
      },
    );
  });
}
