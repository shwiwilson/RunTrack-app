import 'package:flutter/foundation.dart';
import 'package:run_track_app/features/activity/domain/models/activity_models.dart';

@immutable
class AthleteProfile {
  const AthleteProfile({required this.id, required this.displayName});
  final String id;
  final String displayName;

  factory AthleteProfile.fromJson(Map<String, dynamic> json) => AthleteProfile(
    id: json['id'] as String,
    displayName: json['display_name'] as String? ?? '',
  );
}

@immutable
class TrainingSummary {
  const TrainingSummary({
    required this.weekDistanceM,
    required this.previousWeekDistanceM,
    required this.monthDistanceM,
    required this.activeWeeks,
    required this.totalRuns,
    required this.personalBests,
  });
  final double weekDistanceM;
  final double previousWeekDistanceM;
  final double monthDistanceM;
  final int activeWeeks;
  final int totalRuns;
  final List<WorkoutBest> personalBests;

  factory TrainingSummary.calculate(List<Activity> activities, DateTime now) {
    final localNow = now.toLocal();
    final today = DateTime(localNow.year, localNow.month, localNow.day);
    final week = DateTime(
      today.year,
      today.month,
      today.day - today.weekday + 1,
    );
    final previous = DateTime(week.year, week.month, week.day - 7);
    final month = DateTime(today.year, today.month);
    final runs = activities
        .where(
          (a) =>
              a.isRunning && a.duplicateOf == null && !a.endedAt.isAfter(now),
        )
        .toList();
    double distance(DateTime start, DateTime end) => runs
        .where((a) => !a.startedAt.isBefore(start) && a.startedAt.isBefore(end))
        .fold(0.0, (sum, a) => sum + (a.distanceM ?? 0));
    final activeWeeks = runs
        .where(
          (a) => !a.startedAt.isBefore(
            DateTime(week.year, week.month, week.day - 21),
          ),
        )
        .map((a) {
          final d = a.startedAt.toLocal();
          return DateTime(d.year, d.month, d.day - d.weekday + 1);
        })
        .toSet()
        .length;
    final bests = <WorkoutBest>[];
    // Whole workout times only. Never extrapolate a 5K split from a longer run.
    for (final target in const [5000.0, 10000.0, 21097.5, 42195.0]) {
      final candidates =
          runs
              .where(
                (a) =>
                    a.distanceM != null &&
                    a.distanceM! >= target &&
                    a.distanceM! <= target * 1.01 &&
                    a.elapsedDurationS != null &&
                    a.elapsedDurationS! > 0,
              )
              .toList()
            ..sort(
              (a, b) => a.elapsedDurationS!.compareTo(b.elapsedDurationS!),
            );
      if (candidates.isNotEmpty) {
        bests.add(WorkoutBest(distanceM: target, activity: candidates.first));
      }
    }
    return TrainingSummary(
      weekDistanceM: distance(week, now.add(const Duration(microseconds: 1))),
      previousWeekDistanceM: distance(previous, week),
      monthDistanceM: distance(month, now.add(const Duration(microseconds: 1))),
      activeWeeks: activeWeeks,
      totalRuns: runs.length,
      personalBests: List.unmodifiable(bests),
    );
  }
}

@immutable
class WorkoutBest {
  const WorkoutBest({required this.distanceM, required this.activity});
  final double distanceM;
  final Activity activity;
}
