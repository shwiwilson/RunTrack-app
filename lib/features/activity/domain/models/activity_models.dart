import 'package:flutter/foundation.dart';

/// The only workout representation used by the app. Measurements are optional;
/// absent provider data remains absent. All instants are normalised to UTC.
@immutable
class Activity {
  const Activity({
    required this.id,
    required this.userId,
    required this.provider,
    required this.providerWorkoutId,
    required this.type,
    required this.startedAt,
    required this.endedAt,
    this.timeZone,
    this.distanceM,
    this.activeDurationS,
    this.elapsedDurationS,
    this.averageHeartRate,
    this.maximumHeartRate,
    this.caloriesKcal,
    this.elevationGainM,
    this.visibility = 'private',
    this.sharedClubId,
    this.syncStatus = 'synced',
    this.deviceInfo = const {},
    this.provenance = const {},
    this.laps = const [],
    this.duplicateOf,
  });

  final String id;
  final String userId;
  final String provider;
  final String providerWorkoutId;
  final String type;
  final DateTime startedAt;
  final DateTime endedAt;
  final String? timeZone;
  final double? distanceM;
  final double? activeDurationS;
  final double? elapsedDurationS;
  final double? averageHeartRate;
  final double? maximumHeartRate;
  final double? caloriesKcal;
  final double? elevationGainM;
  final String visibility;
  final String? sharedClubId;
  final String syncStatus;
  final Map<String, dynamic> deviceInfo;
  final Map<String, dynamic> provenance;
  final List<ActivityLap> laps;
  final String? duplicateOf;

  bool get isRunning => const {
    'run',
    'running',
    'trail_run',
    'treadmill',
    'treadmill_running',
  }.contains(type.toLowerCase());

  /// seconds per kilometre, based on active time (including no paused time).
  double? get paceSecondsPerKm =>
      distanceM != null &&
          distanceM! > 0 &&
          activeDurationS != null &&
          activeDurationS! > 0
      ? activeDurationS! * 1000 / distanceM!
      : null;

  factory Activity.fromJson(Map<String, dynamic> json) {
    final started = DateTime.parse(json['started_at'] as String).toUtc();
    final ended = DateTime.parse(json['ended_at'] as String).toUtc();
    if (ended.isBefore(started)) {
      throw const FormatException('Workout ends before it starts.');
    }
    final distance = measurement(json['distance_m']);
    final active = measurement(json['active_duration_s']);
    final elapsed = measurement(json['elapsed_duration_s']);
    if (active != null && elapsed != null && active > elapsed) {
      throw const FormatException('Active time exceeds elapsed time.');
    }
    return Activity(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      provider: json['provider'] as String,
      providerWorkoutId: json['provider_workout_id'] as String,
      type: json['type'] as String,
      startedAt: started,
      endedAt: ended,
      timeZone: json['time_zone'] as String?,
      distanceM: distance,
      activeDurationS: active,
      elapsedDurationS: elapsed,
      averageHeartRate: measurement(json['average_heart_rate']),
      maximumHeartRate: measurement(json['maximum_heart_rate']),
      caloriesKcal: measurement(json['calories_kcal']),
      elevationGainM: measurement(json['elevation_gain_m']),
      visibility: json['visibility'] as String? ?? 'private',
      sharedClubId: json['shared_club_id'] as String?,
      syncStatus: json['sync_status'] as String? ?? 'synced',
      deviceInfo: Map<String, dynamic>.from(json['device_info'] as Map? ?? {}),
      provenance: Map<String, dynamic>.from(json['provenance'] as Map? ?? {}),
      duplicateOf: json['duplicate_of'] as String?,
      laps: (json['activity_laps'] as List? ?? [])
          .map((e) => ActivityLap.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(growable: false),
    );
  }

  static double? measurement(dynamic value) {
    if (value == null) return null;
    final result = (value as num).toDouble();
    if (!result.isFinite || result < 0) {
      throw const FormatException('Invalid workout measurement.');
    }
    return result;
  }
}

@immutable
class ActivityLap {
  const ActivityLap({required this.index, this.distanceM, this.durationS});
  final int index;
  final double? distanceM;
  final double? durationS;

  factory ActivityLap.fromJson(Map<String, dynamic> json) => ActivityLap(
    index: (json['lap_index'] as num).toInt(),
    distanceM: Activity.measurement(json['distance_m']),
    durationS: Activity.measurement(json['duration_s']),
  );
}
