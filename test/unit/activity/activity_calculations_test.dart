import 'package:flutter_test/flutter_test.dart';
import 'package:run_track_app/features/activity/domain/models/activity_models.dart';
import 'package:run_track_app/features/achievements/domain/models/achievements_models.dart';
import 'package:run_track_app/features/profile/domain/models/you_models.dart';

Map<String, dynamic> workoutJson({
  String id = 'a',
  String start = '2026-11-10T09:00:00Z',
  String end = '2026-11-10T09:30:00Z',
  double? distance = 5000,
  double? active = 1500,
  double? elapsed = 1800,
  String? duplicateOf,
}) => {
  'id': id,
  'user_id': 'athlete',
  'provider': 'test_only',
  'provider_workout_id': id,
  'type': 'running',
  'started_at': start,
  'ended_at': end,
  'distance_m': distance,
  'active_duration_s': active,
  'elapsed_duration_s': elapsed,
  'duplicate_of': duplicateOf,
};
Activity workout({
  String id = 'a',
  DateTime? start,
  double distance = 5000,
  double elapsed = 1800,
  String? duplicateOf,
  String type = 'running',
}) => Activity(
  id: id,
  userId: 'athlete',
  provider: 'test_only',
  providerWorkoutId: id,
  type: type,
  startedAt: start ?? DateTime(2026, 11, 10, 9),
  endedAt: (start ?? DateTime(2026, 11, 10, 9)).add(
    Duration(seconds: elapsed.round()),
  ),
  distanceM: distance,
  activeDurationS: elapsed,
  elapsedDurationS: elapsed,
  duplicateOf: duplicateOf,
);

void main() {
  final now = DateTime(2026, 11, 12, 12);
  group('Canonical activity', () {
    test('pace uses active duration rather than elapsed duration', () {
      final activity = Activity.fromJson(workoutJson());
      expect(activity.paceSecondsPerKm, 300);
      expect(activity.elapsedDurationS, 1800);
      expect(activity.visibility, 'private');
    });
    test(
      'missing and zero measurements never create a pace or health reading',
      () {
        final missing = Activity.fromJson(
          workoutJson(distance: null, active: null),
        );
        expect(missing.distanceM, isNull);
        expect(missing.activeDurationS, isNull);
        expect(missing.paceSecondsPerKm, isNull);
        expect(missing.averageHeartRate, isNull);
        expect(
          Activity.fromJson(workoutJson(distance: 0)).paceSecondsPerKm,
          isNull,
        );
      },
    );
    test('invalid chronology, duration and negative values fail', () {
      expect(
        () => Activity.fromJson(workoutJson(end: '2026-11-10T08:00:00Z')),
        throwsFormatException,
      );
      expect(
        () => Activity.fromJson(workoutJson(active: 1900)),
        throwsFormatException,
      );
      expect(
        () => Activity.fromJson(workoutJson(distance: -1)),
        throwsFormatException,
      );
      expect(
        () => Activity.fromJson(workoutJson(distance: double.nan)),
        throwsFormatException,
      );
    });
    test(
      'explicit offsets preserve instants across daylight saving transitions',
      () {
        final activity = Activity.fromJson(
          workoutJson(
            start: '2026-10-25T01:45:00+01:00',
            end: '2026-10-25T01:15:00+00:00',
            active: 1800,
            elapsed: 1800,
          ),
        );
        expect(
          activity.endedAt.difference(activity.startedAt),
          const Duration(minutes: 30),
        );
        expect(activity.startedAt.isUtc, isTrue);
      },
    );
  });
  group('Training and achievements', () {
    test('empty history has no personal bests or earned achievements', () {
      final summary = TrainingSummary.calculate([], now);
      expect(summary.totalRuns, 0);
      expect(summary.weekDistanceM, 0);
      expect(summary.personalBests, isEmpty);
      expect(
        RunningAchievement.calculate([], now: now).where((a) => a.earned),
        isEmpty,
      );
    });
    test(
      'explicit duplicate and future records excluded, distinct similar runs retained',
      () {
        final runs = [
          workout(id: 'a'),
          workout(id: 'b'),
          workout(id: 'duplicate', duplicateOf: 'a'),
          workout(id: 'future', start: DateTime(2027)),
          workout(id: 'bike', type: 'cycling'),
        ];
        final summary = TrainingSummary.calculate(runs, now);
        expect(summary.totalRuns, 2);
        expect(summary.weekDistanceM, 10000);
      },
    );
    test('calendar totals distinguish previous week and month', () {
      final summary = TrainingSummary.calculate([
        workout(id: 'this', start: DateTime(2026, 11, 9)),
        workout(id: 'last', start: DateTime(2026, 11, 2), distance: 10000),
        workout(id: 'old', start: DateTime(2026, 10, 31), distance: 2000),
      ], now);
      expect(summary.weekDistanceM, 5000);
      expect(summary.previousWeekDistanceM, 10000);
      expect(summary.monthDistanceM, 15000);
      expect(summary.activeWeeks, 3);
    });
    test(
      'PBs compare full elapsed workouts and never extrapolate longer runs',
      () {
        final summary = TrainingSummary.calculate([
          workout(id: 'slow', elapsed: 1800),
          workout(id: 'fast', elapsed: 1600),
          workout(id: 'longer', distance: 5500, elapsed: 1000),
        ], now);
        expect(summary.personalBests.single.activity.id, 'fast');
      },
    );
    test(
      'milestones are derived from real distances, consistency and attendance',
      () {
        final earned = RunningAchievement.calculate(
          [workout(distance: 10000)],
          now: now,
          attendedSessions: 1,
        ).where((a) => a.earned).map((a) => a.id).toSet();
        expect(earned, {'first_5k', 'first_10k', 'club_first'});
      },
    );
    test('running streak uses consecutive calendar days', () {
      final activities = List.generate(
        7,
        (i) => workout(id: '$i', start: DateTime(2026, 11, 1 + i)),
      );
      expect(
        RunningAchievement.calculate(
          activities,
          now: now,
        ).singleWhere((a) => a.id == 'streak').earned,
        isTrue,
      );
      expect(
        RunningAchievement.calculate(
          activities.take(6).toList(),
          now: now,
        ).singleWhere((a) => a.id == 'streak').earned,
        isFalse,
      );
    });
    test('three runs in each of four consecutive weeks earns consistency', () {
      final activities = [
        for (var week = 0; week < 4; week++)
          for (var run = 0; run < 3; run++)
            workout(
              id: '$week-$run',
              start: DateTime(2026, 10, 12 + week * 7 + run),
            ),
      ];
      expect(
        RunningAchievement.calculate(
          activities,
          now: now,
        ).singleWhere((a) => a.id == 'consistency').earned,
        isTrue,
      );
    });
    test('monthly achievement does not combine different calendar months', () {
      final split = [
        workout(id: 'oct', start: DateTime(2026, 10, 20), distance: 50000),
        workout(id: 'nov', start: DateTime(2026, 11, 1), distance: 50000),
      ];
      expect(
        RunningAchievement.calculate(
          split,
          now: now,
        ).singleWhere((a) => a.id == 'monthly_100').earned,
        isFalse,
      );
      split.add(
        workout(id: 'nov2', start: DateTime(2026, 11, 2), distance: 50000),
      );
      expect(
        RunningAchievement.calculate(
          split,
          now: now,
        ).singleWhere((a) => a.id == 'monthly_100').earned,
        isTrue,
      );
    });
    test(
      'in-progress and future-ended workouts do not earn completed milestones',
      () {
        final ongoing = workout(
          start: now.subtract(const Duration(minutes: 10)),
          distance: 42195,
          elapsed: 7200,
        );
        final summary = TrainingSummary.calculate([ongoing], now);
        expect(summary.totalRuns, 0);
        expect(summary.personalBests, isEmpty);
        expect(
          RunningAchievement.calculate([
            ongoing,
          ], now: now).where((a) => a.earned),
          isEmpty,
        );
      },
    );
  });
}
