import 'dart:math';
import 'package:flutter/material.dart';
import 'package:run_track_app/features/club_hub/domain/repositories/run_track_repository.dart';
import 'package:run_track_app/features/achievements/presentation/view_models/achievements_view_model.dart';
import 'package:run_track_app/features/activity/domain/models/activity_models.dart';
import 'package:run_track_app/features/club_hub/presentation/view_models/club_hub_view_model.dart';
import 'package:run_track_app/features/profile/presentation/view_models/you_view_model.dart';
import 'package:run_track_app/data/mock_data/mock_supabase_db.dart';
import 'package:run_track_app/data/mock_data/mock_database.dart';

/// Mock repository restoring all data for profile pics, attendees, and runs.
/// This fulfills the async contract needed for the Supabase migration.
class MockRunTrackRepository implements RunTrackRepository {
  // Cache the processed feed to keep the UI snappy
  List<ActivityFeedItem>? _cachedFeed;
  String? _cachedClubId;

  /// Clears the local cache to force a re-fetch and re-processing of activities.
  void clearCache() {
    _cachedFeed = null;
    _cachedClubId = null;
  }

  @override
  Future<Map<String, dynamic>> fetchDefaultClubProfile() async {
    // If an athlete context is established in the mock database, use their club.
    // Otherwise, return the first club profile as a neutral starting point for the login screen.
    final user = MockDatabase.currentUser;
    final clubId = user.id.isNotEmpty
        ? user.clubId
        : MockDatabase.clubs.first.id;
    return MockDatabase.getClubProfile(clubId);
  }

  @override
  Future<YouTabState> fetchReadiness(String clubId, String athleteId) async {
    final rows =
        mockSupabaseDb['athlete_readiness'] as List<Map<String, dynamic>>;

    // Find data for specific athlete
    Map<String, dynamic> data;
    try {
      data = rows.firstWhere((r) => r['athlete_id'] == athleteId);
    } catch (_) {
      // Generate dynamic data if not explicitly defined
      final athlete = MockDatabase.clubMembers.firstWhere(
        (u) => u.id == athleteId,
        orElse: () => MockDatabase.currentUser,
      );

      final activities = MockDatabase.getActivitiesForUser(athleteId);
      final now = DateTime.now();

      // Calculate dynamic EF Stats (Moved from Achievements)
      double calculateEfForPeriod(int startDaysAgo, int endDaysAgo) {
        final periodActs = activities.where((a) {
          final date = DateTime.tryParse(a['start_date'] ?? '') ?? now;
          final diff = now.difference(date).inDays;
          return diff >= startDaysAgo && diff < endDaysAgo;
        });
        if (periodActs.isEmpty) return 0.0;
        final totalEf = periodActs.fold(
          0.0,
          (sum, a) =>
              sum + (double.tryParse(a['efficiency_factor'].toString()) ?? 0.0),
        );
        return totalEf / periodActs.length;
      }

      final current14DayEf = calculateEfForPeriod(0, 14);
      final previous14DayEf = calculateEfForPeriod(14, 28);
      String efTrend = 'Stable';
      if (current14DayEf > previous14DayEf * 1.05) {
        efTrend = 'Best 14-day block';
      } else if (current14DayEf > previous14DayEf) {
        efTrend =
            '+${((current14DayEf / (previous14DayEf > 0 ? previous14DayEf : 1) - 1) * 100).toStringAsFixed(1)}% vs last block';
      } else {
        efTrend = 'Maintaining aerobic base';
      }

      // Derive TSB and Readiness from activity history
      final tsbValue = _calculateTSBFromHistory(activities);

      // REAL 7-DAY BASELINE: Health data generation
      final healthHistory = MockDatabase.getHealthDataForUser(athleteId, 7);
      final todayHealth = healthHistory.first;
      final hrvBaseline =
          healthHistory.map((h) => h['hrv'] as double).reduce((a, b) => a + b) /
          7;
      final avgSleepMins =
          healthHistory
              .map((h) => h['sleep_minutes'] as int)
              .reduce((a, b) => a + b) /
          7;
      final sleepBaseline = avgSleepMins / 60.0;

      final calculatedScore = _calculateReadinessFromTSB(tsbValue, athleteId);

      data = {
        'athlete_id': athleteId,
        'athlete_name': athlete.fullName,
        'athlete_initials': athlete.fullName.split(' ').map((n) => n[0]).join(),
        'athlete_image_url': athlete.avatarUrl,
        'readiness_score': calculatedScore,
        'efficiency_label': 'Aerobic Efficiency',
        'efficiency_value': current14DayEf.toStringAsFixed(3),
        'efficiency_trend': efTrend,
        'hrv_baseline': hrvBaseline,
        'sleep_baseline': sleepBaseline,
        'metrics': [
          {
            'label': 'HRV',
            'value': '${todayHealth['hrv'].toStringAsFixed(0)}ms',
            'trend': todayHealth['hrv'] >= hrvBaseline ? 'up' : 'down',
            'status': 'Stable',
          },
          {
            'label': 'Sleep',
            'value':
                '${(todayHealth['sleep_minutes'] as int) ~/ 60}h ${(todayHealth['sleep_minutes'] as int) % 60}m',
            'trend': 'stable',
            'status': 'Stable',
          },
          {
            'label': 'RHR',
            'value': '${todayHealth['rhr']} bpm',
            'trend': 'stable',
            'status': 'Stable',
          },
        ],
        'training_load': {'tsb': tsbValue.round()},
      };
    }

    final score = int.tryParse(data['readiness_score'].toString()) ?? 0;
    final metricsMap = _extractMetrics(data['metrics'] as List);

    return YouTabState(
      athleteName: data['athlete_name'] ?? 'Athlete',
      athleteInitials: data['athlete_initials'] ?? '??',
      athleteImageUrl: data['athlete_image_url'],
      readinessScore: score.toString(),
      readinessLabel: _deriveReadinessLabel(score, metricsMap),
      coachInsight: _synthesizeCoachInsight(score, metricsMap, data),
      efficiencyLabel: (data['efficiency_label'] ?? 'Efficiency').toString(),
      efficiencyValue: (data['efficiency_value'] ?? '0.000').toString(),
      efficiencyTrend: (data['efficiency_trend'] ?? '--').toString(),
      metrics: (data['metrics'] as List).map((m) {
        final map = Map<String, dynamic>.from(m as Map);
        map['trend'] ??= '--';
        map['status'] ??= 'Stable';
        return BiometricMetric.fromJson(map);
      }).toList(),
      benchmarks: _calculateDynamicBenchmarks(data),
    );
  }

  // --- Private Deterministic Logic Engine ---

  /// Calculates TSB (Form) using a simplified Banister Model.
  /// ATL (Acute Training Load): 7-day weighted average of stress.
  /// CTL (Chronic Training Load): 28-day weighted average of stress.
  /// TSB = CTL - ATL.
  double _calculateTSBFromHistory(List<Map<String, dynamic>> activities) {
    final now = DateTime.now();
    double atlSum = 0;
    double ctlSum = 0;

    for (var act in activities) {
      final date = DateTime.parse(act['start_date'] as String);
      final daysAgo = now.difference(date).inDays;

      // Calculate "Stress" for the activity
      // In a real API, this would use Power or Heart Rate (TRIMP)
      // Here we use (Distance * Intensity Factor)
      final distKm = (act['distance'] as double) / 1000.0;
      final isWorkout = act['is_workout'] as bool? ?? false;
      final stress = distKm * (isWorkout ? 1.5 : 1.0);

      if (daysAgo <= 7) atlSum += stress;
      if (daysAgo <= 28) ctlSum += stress;
    }

    final atl = atlSum / 7.0;
    final ctl = ctlSum / 28.0;

    return ctl - atl; // Returns "Form"
  }

  /// Derives a Readiness Score (0-100) based on Training Stress and seeded physiology.
  int _calculateReadinessFromTSB(double tsb, String athleteId) {
    final random = Random(athleteId.hashCode);

    // Base readiness on TSB (The "Freshness" factor)
    // TSB usually ranges from -30 to +20.
    // We map a "Neutral" TSB (0) to a base readiness of 70.
    double baseReadiness = 70.0 + (tsb * 1.5);

    // Add "Physiological Noise" (Seeded so it stays consistent for the user)
    // This simulates random daily fluctuations in HRV/Sleep
    final noise = (random.nextDouble() * 20) - 10;

    return (baseReadiness + noise).clamp(10, 100).round();
  }

  Map<String, double> _extractMetrics(List metrics) {
    return {
      for (var m in metrics)
        (m['label'] as String).toLowerCase(): _smartParse(
          m['value'].toString(),
        ),
    };
  }

  /// Robust parser for diverse biometric units (e.g., "7h 42m", "62 bpm", "45ms")
  double _smartParse(String value) {
    final lowerValue = value.toLowerCase();
    // Handle duration format (7h 42m -> 7.7 hours)
    if (lowerValue.contains('h') || lowerValue.contains('m')) {
      final hours =
          double.tryParse(
            RegExp(r'(\d+)h').firstMatch(lowerValue)?.group(1) ?? '0',
          ) ??
          0.0;
      final mins =
          double.tryParse(
            RegExp(r'(\d+)m').firstMatch(lowerValue)?.group(1) ?? '0',
          ) ??
          0.0;
      return hours + (mins / 60.0);
    }
    // Extract numeric only (e.g., "62 bpm" -> 62.0)
    return double.tryParse(value.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0.0;
  }

  String _deriveReadinessLabel(int score, Map<String, double> metrics) {
    // Logic based on Kiviniemi et al. (2007) regarding HRV-guided training
    final hrv = metrics['hrv'] ?? 0.0;
    if (score > 90 && hrv > 50) return 'Peak Performance';
    if (score > 75) return 'Productive';
    if (score < 50) return 'Overreaching';
    if (score < 30) return 'Strained';
    return 'Maintaining';
  }

  /// Uses Combinatorial Synthesis to generate unique coach insights.
  /// Logic segments: [Status] + [Biometric Reason] + [Training Load Context] + [Prescription]
  String _synthesizeCoachInsight(
    int score,
    Map<String, double> metrics,
    Map<String, dynamic> rawData,
  ) {
    final hrv = metrics['hrv'] ?? 0.0;
    final sleep = metrics['sleep'] ?? 0.0;
    final hrvBaseline =
        double.tryParse(rawData['hrv_baseline']?.toString() ?? '50') ?? 50.0;
    final sleepBaseline =
        double.tryParse(rawData['sleep_baseline']?.toString() ?? '7.5') ?? 7.5;

    final tsb =
        double.tryParse((rawData['training_load']?['tsb'] ?? 0).toString()) ??
        0.0; // Training Stress Balance

    // 2. Biometric Fragments (The 'Why')
    String biometricReason = "";
    // Compare HRV against real 7-day baseline
    if (hrv > 0 && hrv < hrvBaseline * 0.9) {
      biometricReason =
          "Your HRV is significantly below your 7-day baseline, indicating Autonomic Nervous System stress.";
    }
    // Compare Sleep against real 7-day baseline
    else if (sleep > 0 && sleep < sleepBaseline * 0.9) {
      biometricReason =
          "Total sleep duration fell below your weekly average, potentially hindering metabolic clearance and neural restoration.";
    } else {
      biometricReason =
          "Your vitals are stable and trending within normal standard deviations.";
    }

    // 3. Training Load Context (Banister/TrainingPeaks TSB Windows)
    // Freshness: > +5, Neutral: -10 to +5, Loading: -30 to -10, Danger: < -30
    String loadContext = "";
    if (tsb < -30) {
      loadContext =
          "TSB indicates high accumulated fatigue; your current acute load is significantly outpacing your chronic capacity.";
    } else if (tsb < -10) {
      loadContext =
          "You are in a productive loading phase, maintaining a manageable stress-to-rest ratio.";
    } else if (tsb > 5) {
      loadContext =
          "Your 'Form' is high; the reduction in acute load has primed your system for peak performance.";
    } else {
      loadContext =
          "Your training load is currently in a maintenance zone, balancing stimulus with recovery.";
    }

    // Return only the objective analysis derived from metrics and training load
    return "$biometricReason $loadContext";
  }

  List<BenchmarkMetric> _calculateDynamicBenchmarks(Map<String, dynamic> data) {
    final athleteId = data['athlete_id'] as String;
    final activities = MockDatabase.getActivitiesForUser(athleteId);

    // Calculate actual average Efficiency Factor from history
    double totalEf = 0;
    for (var act in activities) {
      totalEf += double.tryParse(act['efficiency_factor'].toString()) ?? 0.0;
    }
    final avgEf = activities.isNotEmpty ? totalEf / activities.length : 0.0;

    // Determine fitness status based on TSB and Consistency
    final tsb =
        double.tryParse((data['training_load']?['tsb'] ?? 0).toString()) ?? 0.0;
    String fitnessStatus = "Steady";
    if (tsb < -10) fitnessStatus = "Building";
    if (tsb > 5) fitnessStatus = "Peaked";
    if (avgEf > 1.8) fitnessStatus = "Elite EF";

    return [
      BenchmarkMetric(label: '90d Fitness', value: fitnessStatus),
      BenchmarkMetric(
        label: 'Efficiency Factor',
        value: avgEf.toStringAsFixed(2),
      ),
    ];
  }

  @override
  Future<List<ActivityFeedItem>> fetchActivities(String clubId) async {
    // Only return cache if it matches the requested clubId
    if (_cachedFeed != null && _cachedClubId == clubId) return _cachedFeed!;

    final List<Map<String, dynamic>> combinedRows = [];

    // Add historical data for members of the current club only
    final clubMembers = MockDatabase.clubMembers.where(
      (m) => m.clubId == clubId,
    );
    for (var member in clubMembers) {
      combinedRows.addAll(MockDatabase.getActivitiesForUser(member.id));
    }

    // Add any specific feed items from the static mock DB
    final feedRows =
        mockSupabaseDb['activity_feed'] as List<Map<String, dynamic>>? ?? [];

    combinedRows.addAll(feedRows.where((r) => r['club_id'] == clubId));

    // Sort raw data by start_date descending before converting to objects
    // to avoid property naming issues in the ActivityFeedItem model.
    combinedRows.sort(
      (a, b) => (b['start_date']?.toString() ?? '').compareTo(
        a['start_date']?.toString() ?? '',
      ),
    );

    // Deduplication logic: If multiple sources (Strava/Garmin) report the same activity,
    // we fingerprint based on start time and distance to only show one.
    final seenActivities = <String, bool>{};
    final uniqueRows = combinedRows.where((r) {
      final startTime = r['start_date']?.toString() ?? '';
      // Use raw distance for fingerprinting, normalizing units
      final rawDist = r['distance'];
      double distMeters = rawDist is num
          ? rawDist.toDouble()
          : (double.tryParse(
                      rawDist.toString().replaceAll(RegExp(r'[^0-9.]'), ''),
                    ) ??
                    0.0) *
                (rawDist.toString().contains('mi') ? 1609.34 : 1000.0);

      // Fingerprint: Start time + distance rounded to nearest 100m.
      // If startTime is empty (undated mock), we use the map hash.
      final fingerprint =
          '${startTime.isEmpty ? r.hashCode : startTime}-${(distMeters / 100).toStringAsFixed(0)}';

      if (seenActivities.containsKey(fingerprint)) return false;
      seenActivities[fingerprint] = true;
      return true;
    }).toList();

    final results = uniqueRows
        .map((r) {
          try {
            final dist =
                double.tryParse(
                  r['distance'].toString().replaceAll(RegExp(r'[^0-9.]'), ''),
                ) ??
                0.0;
            final pace = r['pace'] as String? ?? "";
            final mutableRow = Map<String, dynamic>.from(r);

            mutableRow['distance'] = r['distance'] is num
                ? '${(dist / 1000).toStringAsFixed(2)} km'
                : r['distance']?.toString() ?? '0.00 km';

            mutableRow['description'] = _generateActivitySubTitle(dist, pace);
            mutableRow['start_date'] ??= DateTime.now().toIso8601String();
            mutableRow['source'] ??= 'Strava';
            mutableRow['subtitle'] ??= '';
            return ActivityFeedItem.fromJson(
              Map<String, dynamic>.from(mutableRow),
            );
          } catch (e) {
            debugPrint('Error parsing mock activity: $e');
            return null;
          }
        })
        .whereType<ActivityFeedItem>()
        .toList();

    _cachedFeed = results;
    _cachedClubId = clubId;
    return results;
  }

  String _generateActivitySubTitle(double distance, String pace) {
    if (distance > 15) return "Endurance Threshold Build";
    if (distance < 5 && pace.contains('4:')) return "Anaerobic Power Intervals";
    return "Aerobic Maintenance Run";
  }

  @override
  Future<List<ClubSessionItem>> fetchClubSessions(String clubId) async {
    final rows = mockSupabaseDb['club_sessions'] as List<Map<String, dynamic>>;
    final currentAthleteId = MockDatabase.currentUser.id;
    return rows
        .where((r) => r['club_id'] == clubId)
        .map<ClubSessionItem>(
          (r) => ClubSessionItem.fromJson(r, currentAthleteId),
        )
        .toList();
  }

  @override
  Future<List<NewsletterStagingItem>> fetchNewsletterStaging(
    String clubId,
  ) async {
    final rows =
        mockSupabaseDb['newsletter_staging'] as List<Map<String, dynamic>>;
    return rows
        .where((r) => r['club_id'] == clubId)
        .map((r) => NewsletterStagingItem.fromJson(r))
        .toList();
  }

  @override
  Future<AchievementsState> fetchAchievements(String clubId) async {
    // Get the Super View data for the entire club
    final List<Map<String, dynamic>> statsView =
        MockDatabase.getAggregatedStatsView(forClubId: clubId);

    // Find current user's aggregated row (defaulting to Shane for the demo)
    final Map<String, dynamic> userStats = statsView.firstWhere(
      (s) => s['id'] == MockDatabase.currentUser.id,
      orElse: () =>
          statsView.isNotEmpty ? statsView.first : <String, dynamic>{},
    );
    final Set<String> visitedIds =
        (userStats['visitedTileIds'] as List<dynamic>? ?? [])
            .cast<String>()
            .toSet();

    final rawData =
        mockSupabaseDb['achievements'] as Map<String, dynamic>? ?? {};

    // Dynamically fetch the club center to ensure paths align with the background map
    final clubProfile = MockDatabase.getClubProfile(clubId);
    final center = clubProfile['location'] ?? {'lat': 54.9696, 'lng': -1.6018};

    final currentUserId = MockDatabase.currentUser.id;
    debugPrint('Fetching achievements for User: $currentUserId');

    // Fetch real polylines from the user's actual history
    final userActivities = MockDatabase.getActivitiesForUser(currentUserId);
    final recentPolylines = userActivities
        .take(5) // Show the last 5 runs on the map
        .map((a) => a['polyline'] as String)
        .toList();

    debugPrint('Found ${recentPolylines.length} polylines in history');

    return AchievementsState(
      raceResults: [
        for (final result in (rawData['race_results'] as List<dynamic>? ?? []))
          RaceResultItem.fromJson(result as Map<String, dynamic>),
      ],
      challengeFlags: [
        for (final flag in (rawData['challenge_flags'] as List<dynamic>? ?? []))
          ChallengeFlag.fromJson(flag as Map<String, dynamic>),
      ],
      mapTiles: [
        // Dynamically build the 4x4 grid based on the Super View results
        for (int r = 0; r < 4; r++)
          for (int c = 1; c <= 4; c++)
            MapBingoTileState(
              id: '${String.fromCharCode(65 + r)}$c',
              label: '${String.fromCharCode(65 + r)}$c',
              visited: visitedIds.contains('${String.fromCharCode(65 + r)}$c'),
            ),
      ],
      bingoConfig: MapBingoConfig(
        centerLat: center['lat'] ?? 54.9696,
        centerLng: center['lng'] ?? -1.6018,
        zoom: 14,
        gridSize: 4,
      ),
      leaderboards: _calculateFunLeaderboards(clubId),
      recentPolylines: recentPolylines,
    );
  }

  List<LeaderboardPillState> _calculateFunLeaderboards(String clubId) {
    final statsView = MockDatabase.getAggregatedStatsView(forClubId: clubId);

    LeaderboardPillState buildBoard({
      required String id,
      required String title,
      required String icon,
      required String unit,
      required num Function(Map<String, dynamic>) extractor,
      String Function(num)? formatter,
    }) {
      final entries = statsView.map((s) {
        final val = extractor(s);
        return _SortableEntry(
          entry: LeaderboardEntry(
            name: s['name'] as String,
            value: formatter != null ? formatter(val) : val.toString(),
            imageUrl: s['imageUrl'] as String?,
            isCurrentUser: s['id'] == MockDatabase.currentUser.id,
          ),
          sortValue: val.toDouble(),
        );
      }).toList();

      entries.sort((a, b) => b.sortValue.compareTo(a.sortValue));

      final mappedEntries = <LeaderboardEntry>[];
      for (int i = 0; i < entries.length; i++) {
        mappedEntries.add(entries[i].entry.copyWith(rank: i + 1));
      }

      final userEntry = mappedEntries.firstWhere((e) => e.isCurrentUser);

      return LeaderboardPillState(
        id: id,
        title: title,
        iconName: icon,
        userRank: userEntry.rank,
        userValue: userEntry.value,
        unit: unit,
        allEntries: mappedEntries,
      );
    }

    return [
      buildBoard(
        id: 'ambassador',
        title: 'Club Ambassador',
        icon: 'verified_user',
        unit: ' events',
        extractor: (s) => (s['clubEvents'] ?? 0) as int,
      ),
      buildBoard(
        id: 'grinder',
        title: 'Grinder of the Week',
        icon: 'timer',
        unit: ' km',
        extractor: (s) => (s['weeklyDistance'] ?? 0.0) as double,
        formatter: (v) => v.toStringAsFixed(1),
      ),
      buildBoard(
        id: 'sandbagger',
        title: 'Sandbagger (Zone 2)',
        icon: 'bed',
        unit: '%',
        extractor: (s) => ((s['zone2Ratio'] ?? 0.0) as double) * 100,
        formatter: (v) => v.toStringAsFixed(0),
      ),
      buildBoard(
        id: 'mountain_goat',
        title: 'Mountain Goat',
        icon: 'terrain',
        unit: ' m',
        extractor: (s) => (s['monthlyElevation'] ?? 0.0) as double,
        formatter: (v) => v.toStringAsFixed(0),
      ),
      buildBoard(
        id: 'sunrise',
        title: 'Sunrise Serialist',
        icon: 'wb_sunny',
        unit: ' runs',
        extractor: (s) => (s['sunriseRuns'] ?? 0) as int,
      ),
      buildBoard(
        id: 'butterfly',
        title: 'Social Butterfly',
        icon: 'groups',
        unit: ' partners',
        extractor: (s) => (s['socialCount'] ?? 0) as int,
      ),
      buildBoard(
        id: 'pr_hunter',
        title: 'PR Hunter',
        icon: 'bolt',
        unit: ' PRs',
        extractor: (s) => (s['prCount'] ?? 0) as int,
      ),
      buildBoard(
        id: 'streak',
        title: 'Streak Specialist',
        icon: 'whatshot',
        unit: ' days',
        extractor: (s) => (s['currentStreak'] ?? 0) as int,
      ),
      buildBoard(
        id: 'bingo_master',
        title: 'Map Bingo Master',
        icon: 'map',
        unit: '%',
        extractor: (s) => (((s['mapTiles'] ?? 0) as int) / 16.0) * 100,
        formatter: (v) => v.toStringAsFixed(0),
      ),
    ];
  }

  @override
  Future<void> updateRsvp(
    String sessionId,
    String athleteId,
    String status,
  ) async {
    // Simulate network latency
    await Future.delayed(const Duration(milliseconds: 300));

    final sessions =
        mockSupabaseDb['club_sessions'] as List<Map<String, dynamic>>;

    try {
      final session = sessions.firstWhere((s) => s['id'] == sessionId);
      final attendees = List<Map<String, dynamic>>.from(
        session['attendees'] as List,
      );

      // Try to find the athlete in the current attendee list
      final index = attendees.indexWhere((a) => a['athlete_id'] == athleteId);

      if (index != -1) {
        // Update existing RSVP status
        attendees[index]['rsvp_status'] = status;
      } else {
        // Add new attendee to the list
        final user = MockDatabase.clubMembers.firstWhere(
          (u) => u.id == athleteId,
        );
        attendees.add({
          'athlete_id': athleteId,
          'athlete_initials': user.fullName.split(' ').map((n) => n[0]).join(),
          'athlete_image_url': user.avatarUrl,
          'rsvp_status': status,
        });
      }

      // Save the updated list back to the mock database
      session['attendees'] = attendees;
    } catch (e) {
      debugPrint('Error updating mock RSVP: $e');
    }
  }
}

class _SortableEntry {
  final LeaderboardEntry entry;
  final double sortValue;
  _SortableEntry({required this.entry, required this.sortValue});
}
