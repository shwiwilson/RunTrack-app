import 'package:flutter/foundation.dart';

@immutable
class AchievementsState {
  const AchievementsState({
    required this.raceResults,
    required this.challengeFlags,
    required this.mapTiles,
    required this.bingoConfig,
    required this.leaderboards,
    this.recentPolylines = const [],
  });

  final List<RaceResultItem> raceResults;
  final List<ChallengeFlag> challengeFlags;
  final List<MapBingoTileState> mapTiles;
  final MapBingoConfig bingoConfig;
  final List<LeaderboardPillState> leaderboards;
  final List<String> recentPolylines;
}

@immutable
class MapBingoConfig {
  const MapBingoConfig({
    required this.centerLat,
    required this.centerLng,
    required this.zoom,
    required this.gridSize,
  });

  final double centerLat;
  final double centerLng;
  final double zoom;
  final int gridSize; // e.g. 4 for 4x4
}

@immutable
class LeaderboardPillState {
  const LeaderboardPillState({
    required this.id,
    required this.title,
    required this.iconName,
    required this.userRank,
    required this.userValue,
    required this.allEntries,
    required this.unit,
  });

  final String id;
  final String title;
  final String iconName;
  final int userRank;
  final String userValue;
  final String unit;
  final List<LeaderboardEntry> allEntries;
}

@immutable
class LeaderboardEntry {
  const LeaderboardEntry({
    required this.name,
    required this.value,
    this.imageUrl,
    this.isCurrentUser = false,
    this.rank = 0,
  });

  final String name;
  final String value;
  final String? imageUrl;
  final bool isCurrentUser;
  final int rank;

  LeaderboardEntry copyWith({int? rank}) => LeaderboardEntry(
    name: name,
    value: value,
    imageUrl: imageUrl,
    isCurrentUser: isCurrentUser,
    rank: rank ?? this.rank,
  );
}

@immutable
class RaceResultItem {
  const RaceResultItem({
    required this.event,
    required this.result,
    required this.time,
    required this.rank,
  });
  final String event;
  final String result;
  final String time;
  final String rank;

  factory RaceResultItem.fromJson(Map<String, dynamic> json) => RaceResultItem(
    event: (json['event'] ?? 'Unknown Event').toString(),
    result: (json['result'] ?? json['time'] ?? 'N/A').toString(),
    time: (json['time'] ?? json['result'] ?? 'N/A').toString(),
    rank: (json['rank'] ?? '-').toString(),
  );
}

@immutable
class ChallengeFlag {
  const ChallengeFlag({
    required this.label,
    required this.value,
    required this.isAchieved,
  });
  final String label;
  final String value;
  final bool isAchieved;

  factory ChallengeFlag.fromJson(Map<String, dynamic> json) => ChallengeFlag(
    label: (json['label'] ?? json['name'] ?? 'Challenge').toString(),
    value:
        (json['value']?.toString() ??
        (json['is_achieved'] == true ? 'Completed' : 'Pending')),
    isAchieved:
        (json['is_achieved'] ??
            (json['value'] is bool ? json['value'] : false)) ==
        true,
  );
}

@immutable
class MapBingoTileState {
  const MapBingoTileState({
    required this.id,
    required this.label,
    required this.visited,
  });
  final String id;
  final String label;
  final bool visited;

  factory MapBingoTileState.fromJson(Map<String, dynamic> json) =>
      MapBingoTileState(
        id: (json['id'] ?? '').toString(),
        label: (json['label'] ?? json['id'] ?? '').toString(),
        visited: (json['visited'] ?? json['is_achieved'] ?? false) == true,
      );
}
