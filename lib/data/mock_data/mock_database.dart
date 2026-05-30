import 'dart:math';
import 'package:run_track_app/core/theme/mock_themes.dart';

class MockUser {
  final String id;
  final String clubId;
  final String fullName;
  final String avatarUrl;
  final String profilePicUrl; // Added for backward compatibility
  final String city;
  final double totalDistanceKm;

  MockUser({
    required this.id,
    required this.clubId,
    required this.fullName,
    required this.avatarUrl,
    required this.profilePicUrl,
    required this.city,
    required this.totalDistanceKm,
  });
}

class MockClub {
  final String id;
  final String name;
  final String shortName;
  final Map<String, dynamic> themeJson;

  MockClub({
    required this.id,
    required this.name,
    required this.shortName,
    required this.themeJson,
  });
}

class MockDatabase {
  // Centralized list of club members
  static List<MockUser>? _cachedMembers;

  static final List<MockClub> clubs = [
    MockClub(
      id: 'club_tbh',
      name: 'Tyne Bridge Harriers',
      shortName: 'TBH',
      themeJson: tyneBridgeHarriersTheme,
    ),
    MockClub(
      id: 'club_claremont',
      name: 'Claremont Road Runners',
      shortName: 'CRR',
      themeJson: claremontTheme,
    ),
    MockClub(
      id: 'club_heaton',
      name: 'Heaton Harriers',
      shortName: 'HH',
      themeJson: heatonHarriersTheme,
    ),
  ];

  static List<MockUser> get clubMembers {
    if (_cachedMembers != null) return _cachedMembers!;

    final List<String> names = [
      "Shane O'Neill",
      "Alice Thompson",
      "Bob Richards",
      "Charlie Davis",
      "Diana Prince",
      "Edward Norton",
      "Fiona Gallagher",
      "George Miller",
      "Hannah Abbott",
      "Ian Wright",
      "Jenny Slate",
      "Kevin Hart",
      "Laura Palmer",
      "Mike Tyson",
      "Nina Simone",
      "Oscar Isaac",
      "Peter Parker",
      "Quinn Fabray",
      "Riley Reid",
      "Steve Rogers",
      "Tony Stark",
      "Bruce Banner",
      "Natasha Romanoff",
      "Wanda Maximoff",
      "Vision",
    ];

    final List<String> stockAvatars = [
      'https://images.unsplash.com/photo-1539571696357-5a69c17a67c6?w=150&h=150&fit=crop',
      'https://images.unsplash.com/photo-1438761681033-6461ffad8d80?w=150&h=150&fit=crop',
      'https://images.unsplash.com/photo-1472099645785-5658abf4ff4e?w=150&h=150&fit=crop',
      'https://images.unsplash.com/photo-1531123897727-8f129e1688ce?w=150&h=150&fit=crop',
      'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=150&h=150&fit=crop',
      'https://images.unsplash.com/photo-1544005313-94ddf0286df2?w=150&h=150&fit=crop',
      'https://images.unsplash.com/photo-1506794778202-cad84cf45f1d?w=150&h=150&fit=crop',
      'https://images.unsplash.com/photo-1554151228-14d9def656e4?w=150&h=150&fit=crop',
      'https://images.unsplash.com/photo-1504257432389-52343af06ae3?w=150&h=150&fit=crop',
      'https://images.unsplash.com/photo-1488426862026-3ee34a7d66df?w=150&h=150&fit=crop',
      'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=150&h=150&fit=crop',
      'https://images.unsplash.com/photo-1491349174775-aaafddd81942?w=150&h=150&fit=crop',
      'https://images.unsplash.com/photo-1521119989659-a83eee488004?w=150&h=150&fit=crop',
      'https://images.unsplash.com/photo-1567532939604-b6b5b0db2a04?w=150&h=150&fit=crop',
      'https://images.unsplash.com/photo-1522075469751-3a6694fb2f61?w=150&h=150&fit=crop',
      'https://images.unsplash.com/photo-1557053910-d9eabe1c59a4?w=150&h=150&fit=crop',
      'https://images.unsplash.com/photo-1463453091185-61582044d556?w=150&h=150&fit=crop',
      'https://images.unsplash.com/photo-1508214751196-bcfd4ca60f91?w=150&h=150&fit=crop',
      'https://images.unsplash.com/photo-1500048993953-d23a436266cf?w=150&h=150&fit=crop',
      'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=150&h=150&fit=crop',
    ];

    final List<String> cities = [
      "London",
      "New York",
      "Dublin",
      "Berlin",
      "Paris",
      "Tokyo",
    ];

    final random = Random(42); // Fixed seed for consistent mock data

    _cachedMembers = List.generate(names.length, (index) {
      final avatar = stockAvatars[index % stockAvatars.length];
      // Distribute members across the 3 clubs
      final club = clubs[index % clubs.length];
      return MockUser(
        id: 'strava_user_${index + 100}',
        clubId: club.id,
        fullName: names[index],
        avatarUrl: avatar,
        profilePicUrl: avatar,
        city: cities[random.nextInt(cities.length)],
        totalDistanceKm: (random.nextDouble() * 500).roundToDouble(),
      );
    });

    return _cachedMembers!;
  }

  // Mock "Current Logged In User"
  static MockUser? _currentUser;
  static MockUser get currentUser => _currentUser ?? clubMembers[0];
  static set currentUser(MockUser user) {
    _currentUser = user;
  }

  static Map<String, dynamic> getClubProfile(String clubId) {
    final club = clubs.firstWhere(
      (c) => c.id == clubId,
      orElse: () => clubs[0],
    );
    return {
      'id': club.id,
      'name': club.name,
      'shortName': club.shortName,
      'theme_json': club.themeJson,
    };
  }

  /// The "Super View": Aggregates all activity data into a single read-model
  /// for every club member. This simulates a Postgres View in Supabase.
  static List<Map<String, dynamic>> getAggregatedStatsView({
    String? forClubId,
  }) {
    // Newcastle Grid boundaries for Map Bingo (4x4).
    // These are adjusted to better align with the map center (54.9696, -1.6018)
    // and the typical view area shown at zoom 14 in the UI.
    const double centerLat = 54.9696;
    const double centerLng = -1.6018;
    const double topLat = centerLat + 0.012;
    const double bottomLat = centerLat - 0.012;
    const double leftLng = centerLng - 0.020;
    const double rightLng = centerLng + 0.020;

    final latStep = (topLat - bottomLat) / 4;
    final lngStep = (rightLng - leftLng) / 4;

    final filteredMembers = forClubId != null
        ? clubMembers.where((u) => u.clubId == forClubId).toList()
        : clubMembers;

    return filteredMembers.map((user) {
      final activities = getActivitiesForUser(user.id);
      final now = DateTime.now();
      final Set<String> visitedTileIds = {};

      final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
      final startOfMonth = DateTime(now.year, now.month, 1);

      int clubEvents = 0;
      double weeklyDistance = 0;
      double monthlyElevation = 0;
      int sunriseRuns = 0;
      int socialCount = 0; 

      // 1. Calculate General Stats (Full History)
      for (final act in activities) {
        final date = DateTime.tryParse(act['start_date'] ?? '') ?? now;
        if (act['verified_club_run'] == true) clubEvents++;
        if (date.isAfter(startOfWeek)) {
          weeklyDistance += (act['distance'] as double);
        }
        if (date.isAfter(startOfMonth)) {
          monthlyElevation += (act['elevation_gain'] ?? 0.0);
        }
        if (date.hour < 9) sunriseRuns++;
        if (act['cluster_label'] != 'Solo') socialCount++;
      }

      // 2. Calculate Bingo Progress (Top 5 Recent Only)
      // We only process the 5 most recent runs for Bingo to ensure the ticked
      // squares perfectly match the lines drawn on the Map UI.
      final bingoActivities = activities.take(5).toList();

      for (final act in bingoActivities) {
        final List<double> lats = (act['path_lats'] as List<double>? ?? []);
        final List<double> lngs = (act['path_lngs'] as List<double>? ?? []);

        // REAL POLICING: Check line segments between points.
        for (int pt = 0; pt < lats.length - 1; pt++) {
          final lat1 = lats[pt];
          final lng1 = lngs[pt];
          final lat2 = lats[pt + 1];
          final lng2 = lngs[pt + 1];

          // High-precision interpolation: check 15 points along each segment
          // to ensure no square is missed when a runner crosses a boundary.
          for (int step = 0; step <= 15; step++) {
            final t = step / 15.0;
            final lat = lat1 + (lat2 - lat1) * t;
            final lng = lng1 + (lng2 - lng1) * t;

            if (lat <= topLat &&
                lat >= bottomLat &&
                lng >= leftLng &&
                lng <= rightLng) {
              final rowIndex = ((topLat - lat) / latStep).floor().clamp(0, 3);
              final colIndex = ((lng - leftLng) / lngStep).floor().clamp(0, 3);

              final rowLabel = String.fromCharCode(65 + rowIndex); // A, B, C, D
              final colLabel = colIndex + 1; // 1, 2, 3, 4
              visitedTileIds.add('$rowLabel$colLabel');
            }
          }
        }
      }

      final random = Random(user.id.hashCode);
      return <String, dynamic>{
        'id': user.id,
        'name': user.fullName,
        'imageUrl': user.avatarUrl,
        'clubEvents': clubEvents,
        'weeklyDistance': weeklyDistance / 1000.0,
        'zone2Ratio': 0.6 + random.nextDouble() * 0.35,
        'monthlyElevation': monthlyElevation,
        'sunriseRuns': sunriseRuns,
        'socialCount': socialCount,
        'mapTiles': visitedTileIds.length,
        'visitedTileIds': visitedTileIds.toList(),
        'prCount': random.nextInt(12),
        'currentStreak': random.nextInt(20),
      };
    }).toList();
  }

  // Cache to prevent re-generating 800+ activities on every request
  static final Map<String, List<Map<String, dynamic>>> _activityCache = {};

  // Mock activities linked to user IDs
  static List<Map<String, dynamic>> getActivitiesForUser(String userId) {
    if (_activityCache.containsKey(userId)) return _activityCache[userId]!;

    final random = Random(userId.hashCode);
    final List<String> titles = [
      "Morning Run",
      "Evening Run",
      "Long Run",
      "Tempo Session",
      "Easy Jog",
      "Recovery Run",
      "Threshold Intervals",
      "Hill Repeats",
      "Lunchtime Loop",
      "Trail Run",
    ];

    // Generate a rich history of 20-40 activities per user
    final activities = List.generate(20 + random.nextInt(20), (index) {
      final isLongRun = index % 7 == 0; // Weekly long run logic
      final isWorkout = index % 3 == 0; // Intervals or Tempo logic

      double distance;
      int paceSecPerKm;

      if (index == 0 && userId == 'strava_user_100') {
        distance = 6400.0; // Shane's 4-mile run across the top row
        paceSecPerKm = 255; // ~6:50/mi
      } else if (isLongRun) {
        distance = 18000.0 + random.nextDouble() * 14000.0; // 18-32km
        paceSecPerKm =
            300 + random.nextInt(60); // 5:00 - 6:00 (Slower long pace)
      } else if (isWorkout) {
        distance = 6000.0 + random.nextDouble() * 6000.0; // 6-12km
        paceSecPerKm = 230 + random.nextInt(40); // 3:50 - 4:30 (Fast)
      } else {
        distance = 4000.0 + random.nextDouble() * 8000.0; // 4-12km
        paceSecPerKm = 300 + random.nextInt(90); // 5:00 - 6:30 (Easy)
      }

      final movingTime = (distance / 1000 * paceSecPerKm).round();
      final date = (index == 0 && userId == 'strava_user_100')
          ? DateTime.now().subtract(const Duration(hours: 1))
          : DateTime.now().subtract(
              Duration(
                days: index,
                hours: random.nextInt(24),
                minutes: random.nextInt(60),
              ),
            );

      // Get user info for feed consistency
      final user = clubMembers.firstWhere(
        (u) => u.id == userId,
        orElse: () => currentUser,
      );

      final elevationGain = 10.0 + random.nextDouble() * 200.0;

      // Logic for data consistency:
      // Tuesdays are typically Intervals (Workouts) and Sundays are Long Runs.
      final isClubDay =
          date.weekday == DateTime.tuesday || date.weekday == DateTime.sunday;
      final verifiedClubRun =
          isClubDay && (isWorkout || isLongRun) && random.nextDouble() > 0.2;
      final clusterLabel = verifiedClubRun
          ? 'Official Club Group'
          : (random.nextDouble() > 0.7 ? 'With Friends' : 'Solo');

      // Generate real GPS coordinates for Shane's run today hitting Row A
      final List<double> pathLats = [];
      final List<double> pathLngs = [];

      if (index == 0 && userId == 'strava_user_100') {
        // Traversing the top row boundaries (approx lat 54.978)
        for (int i = 0; i < 20; i++) {
          pathLats.add(54.978);
          pathLngs.add(-1.625 + (i * 0.0022)); // Hits -1.625 down to -1.581
        }
      } else {
        // Default random-ish Newcastle coordinates
        final jitter = (random.nextDouble() - 0.5) * 0.02;
        double curLat = 54.9696 + jitter;
        double curLng = -1.6018 + jitter;
        for (int i = 0; i < 12; i++) {
          pathLats.add(curLat);
          pathLngs.add(curLng);
          curLat += (random.nextDouble() - 0.5) * 0.006;
          curLng += (random.nextDouble() - 0.5) * 0.006;
        }
      }

      final String encodedPolyline = _encodePolyline(pathLats, pathLngs);

      return {
        'id': 'act_${userId}_$index',
        'athlete_id': userId,
        'athlete_name': user.fullName,
        'athlete_initials': user.fullName.split(' ').map((e) => e[0]).join(),
        'athlete_image_url': user.avatarUrl,
        'club_id': user.clubId,
        'source': 'Strava',
        'title': titles[random.nextInt(titles.length)],
        'subtitle': '',
        'polyline': encodedPolyline,
        'path_lats': pathLats,
        'path_lngs': pathLngs,
        'distance': distance,
        'elevation_gain': elevationGain,
        'moving_time': movingTime,
        'type': 'Run',
        'start_date': date.toIso8601String(),
        'pace':
            '${(paceSecPerKm ~/ 60)}:${(paceSecPerKm % 60).toString().padLeft(2, '0')}',
        'heart_rate':
            '${isWorkout ? 155 + random.nextInt(20) : 130 + random.nextInt(15)} bpm',
        'efficiency_factor': (() {
          // EF Calculation: Speed (m/min) / Heart Rate - Normalizing for consistent leaderboard scores
          final double speedMins = (movingTime > 0 ? movingTime : 1) / 60.0;
          final double mPerMin = distance / speedMins;
          final int hr = int.parse(
            (isWorkout ? 155 + random.nextInt(20) : 130 + random.nextInt(15))
                .toString(),
          );
          // Resulting EF typically falls between 1.2 and 2.2 for runners
          return (mPerMin / hr).toStringAsFixed(3);
        })(),
        'verified_club_run': verifiedClubRun,
        'cluster_label': clusterLabel,
        'is_workout': isWorkout,
        'is_long_run': isLongRun,
      };
    });

    _activityCache[userId] = activities;
    return activities;
  }

  /// Encodes a list of coordinates into a standard Google/Strava polyline string.
  static String _encodePolyline(List<double> lats, List<double> lngs) {
    var str = StringBuffer();
    void encode(num v) {
      int value = (v.toInt() << 1) ^ (v.toInt() >> 31);
      while (value >= 0x20) {
        str.write(String.fromCharCode((0x20 | (value & 0x1f)) + 63));
        value >>= 5;
      }
      str.write(String.fromCharCode(value + 63));
    }

    int lastLat = 0, lastLng = 0;
    for (int i = 0; i < lats.length; i++) {
      int nextLat = (lats[i] * 1e5).round();
      int nextLng = (lngs[i] * 1e5).round();
      encode(nextLat - lastLat);
      encode(nextLng - lastLng);
      lastLat = nextLat;
      lastLng = nextLng;
    }
    return str.toString();
  }

  // Mock health data (HRV, Sleep, RHR) linked to user IDs over a period of time
  static List<Map<String, dynamic>> getHealthDataForUser(
    String userId,
    int days,
  ) {
    final random = Random(userId.hashCode + 123);
    return List.generate(days, (index) {
      final date = DateTime.now().subtract(Duration(days: index));
      // HRV: 40-75 ms base
      final hrv = 40.0 + random.nextInt(35) + random.nextDouble();
      // Sleep: 360 - 540 minutes (6-9 hours)
      final sleepMinutes = 360 + random.nextInt(180);

      return {
        'date': date.toIso8601String(),
        'hrv': hrv,
        'sleep_minutes': sleepMinutes,
        'rhr': 48 + random.nextInt(12),
      };
    });
  }
}
