import 'package:flutter/foundation.dart';
import 'package:run_track_app/features/activity/domain/models/activity_models.dart';

@immutable
class RunningAchievement {
  const RunningAchievement({
    required this.id,
    required this.title,
    required this.description,
    required this.earned,
  });
  final String id;
  final String title;
  final String description;
  final bool earned;

  static List<RunningAchievement> calculate(
    List<Activity> activities, {
    required DateTime now,
    int attendedSessions = 0,
  }) {
    final runs = activities
        .where(
          (a) =>
              a.isRunning && a.duplicateOf == null && !a.endedAt.isAfter(now),
        )
        .toList();
    bool reached(double distance) =>
        runs.any((a) => (a.distanceM ?? 0) >= distance);
    final monthly = <String, double>{};
    final yearly = <int, double>{};
    final weeks = <DateTime, int>{};
    final days = <DateTime>{};
    for (final run in runs) {
      final date = run.startedAt.toLocal();
      final key = '${date.year}-${date.month}';
      monthly[key] = (monthly[key] ?? 0) + (run.distanceM ?? 0);
      yearly[date.year] = (yearly[date.year] ?? 0) + (run.distanceM ?? 0);
      final week = DateTime(date.year, date.month, date.day - date.weekday + 1);
      weeks[week] = (weeks[week] ?? 0) + 1;
      days.add(DateTime.utc(date.year, date.month, date.day));
    }
    int longestStreak = 0, streak = 0;
    DateTime? previous;
    final orderedDays = days.toList()..sort();
    for (final day in orderedDays) {
      streak = previous != null && day.difference(previous).inDays == 1
          ? streak + 1
          : 1;
      if (streak > longestStreak) longestStreak = streak;
      previous = day;
    }
    bool consistent = false;
    for (final week in weeks.keys) {
      if (List.generate(
        4,
        (i) => DateTime(week.year, week.month, week.day - i * 7),
      ).every((w) => (weeks[w] ?? 0) >= 3)) {
        consistent = true;
      }
    }
    return [
      RunningAchievement(
        id: 'first_5k',
        title: 'First 5K',
        description: 'Complete a run of at least 5 km.',
        earned: reached(5000),
      ),
      RunningAchievement(
        id: 'first_10k',
        title: 'First 10K',
        description: 'Complete a run of at least 10 km.',
        earned: reached(10000),
      ),
      RunningAchievement(
        id: 'first_half',
        title: 'First half marathon',
        description: 'Complete a run of at least 21.0975 km.',
        earned: reached(21097.5),
      ),
      RunningAchievement(
        id: 'first_marathon',
        title: 'First marathon',
        description: 'Complete a run of at least 42.195 km.',
        earned: reached(42195),
      ),
      RunningAchievement(
        id: 'monthly_100',
        title: '100 km in a month',
        description: 'Record 100 km in one calendar month.',
        earned: monthly.values.any((v) => v >= 100000),
      ),
      RunningAchievement(
        id: 'yearly_1000',
        title: '1,000 km in a year',
        description: 'Record 1,000 km in one calendar year.',
        earned: yearly.values.any((v) => v >= 1000000),
      ),
      RunningAchievement(
        id: 'consistency',
        title: 'A consistent month',
        description: 'Run three times a week for four consecutive weeks.',
        earned: consistent,
      ),
      RunningAchievement(
        id: 'streak',
        title: 'Seven-day running streak',
        description: 'Record runs on seven consecutive calendar days.',
        earned: longestStreak >= 7,
      ),
      RunningAchievement(
        id: 'club_first',
        title: 'Together on the start line',
        description: 'Have attendance confirmed at a club session.',
        earned: attendedSessions >= 1,
      ),
      RunningAchievement(
        id: 'club_ten',
        title: 'A familiar face',
        description: 'Have attendance confirmed at ten club sessions.',
        earned: attendedSessions >= 10,
      ),
    ];
  }
}

@immutable
class RaceResult {
  const RaceResult({
    required this.id,
    required this.eventName,
    required this.eventDate,
    required this.distanceM,
    required this.durationS,
    required this.verified,
    this.evidenceUrl,
  });
  final String id;
  final String eventName;
  final DateTime eventDate;
  final double distanceM;
  final double durationS;
  final bool verified;
  final String? evidenceUrl;
  factory RaceResult.fromJson(Map<String, dynamic> json) => RaceResult(
    id: json['id'] as String,
    eventName: json['event_name'] as String,
    eventDate: DateTime.parse(json['event_date'] as String),
    distanceM: (json['distance_m'] as num).toDouble(),
    durationS: (json['duration_s'] as num).toDouble(),
    verified: json['verified'] == true,
    evidenceUrl: json['evidence_url'] as String?,
  );
}
