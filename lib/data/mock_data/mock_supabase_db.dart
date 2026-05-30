import 'package:run_track_app/core/theme/mock_themes.dart';

const defaultClubSlug = 'tyne_bridge_harriers';

/// A helper to generate consistent mock athletes
List<Map<String, dynamic>> _generateAthletes() {
  final stockAvatars = [
    'https://images.unsplash.com/photo-1539571696357-5a69c17a67c6?w=200&h=200&fit=crop',
    'https://images.unsplash.com/photo-1438761681033-6461ffad8d80?w=200&h=200&fit=crop',
    'https://images.unsplash.com/photo-1472099645785-5658abf4ff4e?w=200&h=200&fit=crop',
    'https://images.unsplash.com/photo-1531123897727-8f129e1688ce?w=200&h=200&fit=crop',
    'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=200&h=200&fit=crop',
    'https://images.unsplash.com/photo-1544005313-94ddf0286df2?w=200&h=200&fit=crop',
    'https://images.unsplash.com/photo-1506794778202-cad84cf45f1d?w=200&h=200&fit=crop',
    'https://images.unsplash.com/photo-1554151228-14d9def656e4?w=200&h=200&fit=crop',
    'https://images.unsplash.com/photo-1504257432389-52343af06ae3?w=200&h=200&fit=crop',
    'https://images.unsplash.com/photo-1488426862026-3ee34a7d66df?w=200&h=200&fit=crop',
    'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=200&h=200&fit=crop',
    'https://images.unsplash.com/photo-1491349174775-aaafddd81942?w=200&h=200&fit=crop',
    'https://images.unsplash.com/photo-1521119989659-a83eee488004?w=200&h=200&fit=crop',
    'https://images.unsplash.com/photo-1567532939604-b6b5b0db2a04?w=200&h=200&fit=crop',
    'https://images.unsplash.com/photo-1522075469751-3a6694fb2f61?w=200&h=200&fit=crop',
    'https://images.unsplash.com/photo-1557053910-d9eabe1c59a4?w=200&h=200&fit=crop',
    'https://images.unsplash.com/photo-1463453091185-61582044d556?w=200&h=200&fit=crop',
    'https://images.unsplash.com/photo-1508214751196-bcfd4ca60f91?w=200&h=200&fit=crop',
    'https://images.unsplash.com/photo-1500048993953-d23a436266cf?w=200&h=200&fit=crop',
    'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=200&h=200&fit=crop',
  ];

  final firstNames = [
    'Shane',
    'Sarah',
    'Jon',
    'Amina',
    'David',
    'Lucy',
    'Mark',
    'Elena',
    'Rob',
    'Sophie',
    'Michael',
    'Hannah',
    'Alex',
    'Rachel',
    'Tom',
    'Emma',
    'Dan',
    'Chloe',
    'James',
    'Katie',
  ];
  final lastNames = [
    'Miller',
    'M.',
    'R.',
    'K.',
    'Ross',
    'Thompson',
    'Patterson',
    'V.',
    'Turner',
    'Jones',
    'Wright',
    'Abbott',
    'Carter',
    'Green',
    'Baker',
    'Hill',
    'Scott',
    'Adams',
    'Baker',
    'Clark',
  ];

  return List.generate(20, (i) {
    final name = "${firstNames[i]} ${lastNames[i]}";
    final initials =
        (firstNames[i][0] + (lastNames[i].isNotEmpty ? lastNames[i][0] : ''))
            .toUpperCase();
    return {
      'id': 'athlete_${i + 1}',
      'athlete_name': name,
      'athlete_initials': initials,
      'athlete_image_url': stockAvatars[i % stockAvatars.length],
    };
  });
}

final List<Map<String, dynamic>> _mockAthletes = _generateAthletes();

final mockSupabaseDb = <String, dynamic>{
  'club_profiles': [
    {
      'id': 'club_tbh',
      'slug': 'tyne_bridge_harriers',
      'name': 'Tyne Bridge Harriers',
      'shortName': 'TBH',
      'theme_json': tyneBridgeHarriersTheme,
    },
    {
      'id': 'club_heaton',
      'slug': 'heaton_harriers',
      'name': 'Heaton Harriers',
      'shortName': 'HH',
      'theme_json': heatonHarriersTheme,
    },
    {
      'id': 'club_claremont',
      'slug': 'claremont_road_runners',
      'name': 'Claremont Road Runners',
      'shortName': 'CRR',
      'theme_json': claremontTheme,
    },
  ],
  'athletes': _mockAthletes,
  'athlete_readiness': [
    {
      'club_id': 'club_tbh',
      'athlete_id': _mockAthletes[0]['id'],
      'athlete_name': _mockAthletes[0]['athlete_name'],
      'athlete_initials': _mockAthletes[0]['athlete_initials'],
      'athlete_image_url': _mockAthletes[0]['athlete_image_url'],
      'readiness_score': 86,
      'readiness_label': 'Ready for controlled quality',
      'coach_insight':
          'Your aerobic markers are stable; keep the first reps measured and only press if recovery HR stays calm.',
      'coach_prompt_payload': {
        'avg_pace': '6:31/mi',
        'hr_zone': 3,
        'consistency_score': 0.88,
        'previous_90_day_avg': '6:44/mi',
        'recovery_hr_baseline': 34,
      },
      'metrics': [
        {'label': 'HRV', 'value': '62 ms', 'trend': '+8%', 'status': 'Up'},
        {
          'label': 'Sleep Window',
          'value': '7h 42m',
          'trend': '+31m',
          'status': 'Solid',
        },
        {
          'label': 'Training Load',
          'value': '418',
          'trend': '-4%',
          'status': 'Balanced',
        },
        {
          'label': 'Recovery HR',
          'value': '34 bpm',
          'trend': 'baseline',
          'status': 'Prime',
        },
      ],
      'benchmarks': [
        {'label': '90-day pace delta', 'value': '13 sec/mi faster'},
        {'label': 'Weekly volume', 'value': '42.6 mi'},
        {'label': 'Easy-day discipline', 'value': '91%'},
      ],
    },
  ],
  'activity_feed': [
    {
      'club_id': 'club_tbh',
      'source': 'Strava',
      'athlete_initials': 'SM',
      'athlete_image_url': _mockAthletes[1]['athlete_image_url'],
      'athlete_name': 'Sarah M.',
      'title': 'Quayside tempo progression',
      'subtitle': 'Negative split from the Swing Bridge',
      'polyline': 'u{piHpx_@?a@_@cAo@eAg@u@s@w@o@i@m@i@k@k@sM',
      'distance': '7.4 mi',
      'pace': '6:18/mi',
      'heart_rate': '158 bpm',
      'efficiency_factor': '0.040',
      'verified_club_run': true,
      'cluster_label': 'TBH threshold group',
      'start_date': DateTime.now()
          .subtract(const Duration(hours: 2))
          .toIso8601String(),
    },
    {
      'club_id': 'club_tbh',
      'source': 'Garmin',
      'athlete_initials': 'JR',
      'athlete_image_url': _mockAthletes[2]['athlete_image_url'],
      'athlete_name': 'Jon R.',
      'title': 'Easy loops before work',
      'subtitle': 'Kept it honest on the Town Moor',
      'polyline': 'u{piHpx_@?a@_@cAo@eAg@u@s@w@o@i@m@i@k@k@jR',
      'distance': '4.1 mi',
      'pace': '7:42/mi',
      'heart_rate': '132 bpm',
      'efficiency_factor': '0.058',
      'verified_club_run': false,
      'cluster_label': 'Solo',
      'start_date': DateTime.now()
          .subtract(const Duration(hours: 5))
          .toIso8601String(),
    },
    {
      'club_id': 'club_tbh',
      'source': 'COROS',
      'athlete_initials': 'AK',
      'athlete_image_url': _mockAthletes[3]['athlete_image_url'],
      'athlete_name': 'Amina K.',
      'title': 'Track reps with steady recoveries',
      'subtitle': 'Smooth 800s, no late fade',
      'polyline': 'u{piHpx_@?a@_@cAo@eAg@u@s@w@o@i@m@i@k@k@aK',
      'distance': '5.6 mi',
      'pace': '5:58/mi',
      'heart_rate': '164 bpm',
      'efficiency_factor': '0.036',
      'verified_club_run': true,
      'cluster_label': 'Tuesday track',
      'start_date': DateTime.now()
          .subtract(const Duration(days: 1))
          .toIso8601String(),
    },
  ],
  'club_sessions': [
    {
      'id': 'session_tbh_tue',
      'club_id': 'club_tbh',
      'title': 'Tuesday Intervals',
      'description': '6 x 800m at controlled 10K effort with rolling recovery.',
      'date': 'Tue',
      'time': '18:30',
      'location': 'Churchill Track',
      'spond_url': 'https://spond.com/client/sessions/tbh-tuesday',
      'attendees': [
        {
          'athlete_id': 'strava_user_100', // Shane
          'athlete_initials': _mockAthletes[0]['athlete_initials'],
          'athlete_image_url': _mockAthletes[0]['athlete_image_url'],
          'rsvp_status': 'yes',
        },
        {
          'athlete_id': 'athlete_6',
          'athlete_initials': _mockAthletes[5]['athlete_initials'],
          'athlete_image_url': _mockAthletes[5]['athlete_image_url'],
          'rsvp_status': 'yes',
        },
        {
          'athlete_id': 'athlete_3',
          'athlete_initials': _mockAthletes[2]['athlete_initials'],
          'athlete_image_url': _mockAthletes[2]['athlete_image_url'],
          'rsvp_status': 'maybe',
        },
        {
          'athlete_id': 'athlete_4',
          'athlete_initials': _mockAthletes[3]['athlete_initials'],
          'athlete_image_url': _mockAthletes[3]['athlete_image_url'],
          'rsvp_status': 'no',
        },
        {
          'athlete_id': 'athlete_8',
          'athlete_initials': _mockAthletes[7]['athlete_initials'],
          'athlete_image_url': _mockAthletes[7]['athlete_image_url'],
          'rsvp_status': 'yes',
        },
        {
          'athlete_id': 'athlete_9',
          'athlete_initials': _mockAthletes[8]['athlete_initials'],
          'athlete_image_url': _mockAthletes[8]['athlete_image_url'],
          'rsvp_status': 'yes',
        },
      ],
    },
    {
      'id': 'session_tbh_sun',
      'club_id': 'club_tbh',
      'title': 'Sunday Long Run',
      'description': 'Conversational miles, two distance groups, coffee after.',
      'date': 'Sun',
      'time': '09:00',
      'location': 'Exhibition Park',
      'spond_url': 'https://spond.com/client/sessions/tbh-sunday',
      'attendees': [
        {
          'athlete_id': 'athlete_11',
          'athlete_initials': _mockAthletes[10]['athlete_initials'],
          'athlete_image_url': _mockAthletes[10]['athlete_image_url'],
          'rsvp_status': 'yes',
        },
        {
          'athlete_id': 'athlete_12',
          'athlete_initials': _mockAthletes[11]['athlete_initials'],
          'athlete_image_url': _mockAthletes[11]['athlete_image_url'],
          'rsvp_status': 'yes',
        },
        {
          'athlete_id': 'athlete_13',
          'athlete_initials': _mockAthletes[12]['athlete_initials'],
          'athlete_image_url': _mockAthletes[12]['athlete_image_url'],
          'rsvp_status': 'maybe',
        },
        {
          'athlete_id': 'athlete_3',
          'athlete_initials': _mockAthletes[2]['athlete_initials'],
          'athlete_image_url': _mockAthletes[2]['athlete_image_url'],
          'rsvp_status': 'yes',
        },
      ],
    },
    {
      'id': 'session_heaton_wed',
      'club_id': 'club_heaton',
      'title': 'Town Moor Tempo',
      'description': 'Meet at the start of the 5K course for 4 x 1 mile reps.',
      'date': 'Wed',
      'time': '19:00',
      'location': 'Town Moor',
      'spond_url': 'https://spond.com/client/sessions/heaton-wednesday',
      'attendees': [
        {
          'athlete_id': 'strava_user_120', // Tony Stark
          'athlete_initials': 'TS',
          'athlete_image_url':
              'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=200&h=200&fit=crop',
          'rsvp_status': 'yes',
        },
        {
          'athlete_id': 'strava_user_121', // Bruce Banner
          'athlete_initials': 'BB',
          'athlete_image_url':
              'https://images.unsplash.com/photo-1544005313-94ddf0286df2?w=200&h=200&fit=crop',
          'rsvp_status': 'maybe',
        },
      ],
    },
    {
      'id': 'session_claremont_mon',
      'club_id': 'club_claremont',
      'title': 'Claremont Social',
      'description': 'Easy recovery miles followed by a social gathering.',
      'date': 'Mon',
      'time': '18:15',
      'location': 'Exhibition Park',
      'spond_url': 'https://spond.com/client/sessions/claremont-monday',
      'attendees': [
        {
          'athlete_id': 'strava_user_122', // Natasha Romanoff
          'athlete_initials': 'NR',
          'athlete_image_url':
              'https://images.unsplash.com/photo-1506794778202-cad84cf45f1d?w=200&h=200&fit=crop',
          'rsvp_status': 'yes',
        },
        {
          'athlete_id': 'strava_user_123', // Wanda Maximoff
          'athlete_initials': 'WM',
          'athlete_image_url':
              'https://images.unsplash.com/photo-1554151228-14d9def656e4?w=200&h=200&fit=crop',
          'rsvp_status': 'no',
        },
      ],
    },
  ],
  'newsletter_staging': [
    {
      'club_id': 'club_tbh',
      'source': 'captains@tynebridgeharriers.com',
      'status': 'staged',
      'extracted_json': {
        'date': 'Friday',
        'time': '19:00',
        'location': 'The Cycle Hub',
        'description': 'Road relays briefing and vest collection.',
      },
    },
    {
      'club_id': 'club_heaton',
      'source': 'secretary@heatonharriers.com',
      'status': 'staged',
      'extracted_json': {
        'date': 'Next Tuesday',
        'time': '20:30',
        'location': 'The High Main',
        'description': 'Post-training committee meeting and race sign-ups.',
      },
    },
    {
      'club_id': 'club_claremont',
      'source': 'claremont@runners.com',
      'status': 'staged',
      'extracted_json': {
        'date': 'Sunday',
        'time': '11:00',
        'location': 'The Town Moor',
        'description': 'Internal XC championship race briefing.',
      },
    },
  ],
  'achievements': {
    'club_id': 'club_tbh',
    'efficiency_factor': {
      'label': 'Efficiency Factor',
      'value': '0.040',
      'trend': 'Best 14-day block',
    },
    'race_results': [
      {
        'event': 'North Tyneside 10K',
        'time': '36:42',
        'result': 'Power of 10 verified',
      },
      {'event': 'Town Moor 5K', 'time': '17:29', 'result': 'Course PB'},
    ],
    'challenge_flags': [
      {'label': 'Sandbagger check', 'value': 'Clear'},
      {'label': 'Slacker check', 'value': 'Training consistent'},
    ],
    'map_bingo_tiles': [
      {'label': 'A1', 'visited': true},
      {'label': 'A2', 'visited': false},
      {'label': 'A3', 'visited': false},
      {'label': 'A4', 'visited': true},
      {'label': 'B1', 'visited': true},
      {'label': 'B2', 'visited': false},
      {'label': 'B3', 'visited': false},
      {'label': 'B4', 'visited': true},
      {'label': 'C1', 'visited': false},
      {'label': 'C2', 'visited': true},
      {'label': 'C3', 'visited': true},
      {'label': 'C4', 'visited': false},
      {'label': 'D1', 'visited': false},
      {'label': 'D2', 'visited': false},
      {'label': 'D3', 'visited': true},
      {'label': 'D4', 'visited': false},
    ],
  },
};
