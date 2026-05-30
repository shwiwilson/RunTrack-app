import 'package:flutter/foundation.dart';

@immutable
class RunTrackFeedState {
  const RunTrackFeedState({
    required this.syncSummary,
    required this.activities,
  });

  final String syncSummary;
  final List<ActivityFeedItem> activities;
}

@immutable
class ActivityFeedItem {
  const ActivityFeedItem({
    required this.source,
    required this.athleteInitials,
    this.athleteImageUrl,
    required this.athleteName,
    required this.title,
    required this.subtitle,
    required this.distance,
    required this.pace,
    required this.heartRate,
    required this.efficiencyFactor,
    required this.verifiedClubRun,
    required this.clusterLabel,
    required this.startDate,
    this.polyline,
  });

  final String source;
  final String athleteInitials;
  final String? athleteImageUrl;
  final String athleteName;
  final String title;
  final String subtitle;
  final String distance;
  final String pace;
  final String heartRate;
  final String efficiencyFactor;
  final bool verifiedClubRun;
  final String clusterLabel;
  final String startDate;
  final String? polyline;

  factory ActivityFeedItem.fromJson(Map<String, dynamic> json) {
    return ActivityFeedItem(
      source: json['source'] as String,
      athleteInitials: json['athlete_initials'] as String,
      athleteImageUrl: json['athlete_image_url'] as String?,
      athleteName: json['athlete_name'] as String,
      title: json['title'] as String,
      subtitle: json['subtitle'] as String,
      distance: json['distance'] as String,
      pace: json['pace'] as String,
      heartRate: json['heart_rate'] as String,
      efficiencyFactor: json['efficiency_factor'] as String,
      verifiedClubRun: json['verified_club_run'] as bool,
      clusterLabel: json['cluster_label'] as String,
      startDate: json['start_date'] as String,
      polyline: json['polyline'] as String?,
    );
  }
}
