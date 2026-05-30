class MockActivityFeedItem {
  const MockActivityFeedItem({
    required this.athleteInitial,
    required this.athleteName,
    required this.title,
    required this.pace,
    required this.milesString,
    required this.isVerifiedClubRun,
  });

  final String athleteInitial;
  final String athleteName;
  final String title;
  final String pace;
  final String milesString;
  final bool isVerifiedClubRun;
}

const mockFeedData = <MockActivityFeedItem>[
  MockActivityFeedItem(
    athleteInitial: 'S',
    athleteName: 'Sarah M.',
    title: 'Quayside tempo progression',
    pace: '6:18/mi',
    milesString: '7.4 mi',
    isVerifiedClubRun: true,
  ),
  MockActivityFeedItem(
    athleteInitial: 'J',
    athleteName: 'Jon R.',
    title: 'Easy loops before work',
    pace: '7:42/mi',
    milesString: '4.1 mi',
    isVerifiedClubRun: false,
  ),
  MockActivityFeedItem(
    athleteInitial: 'A',
    athleteName: 'Amina K.',
    title: 'Track reps with steady recoveries',
    pace: '5:58/mi',
    milesString: '5.6 mi',
    isVerifiedClubRun: true,
  ),
];
