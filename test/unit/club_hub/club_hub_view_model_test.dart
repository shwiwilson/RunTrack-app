import 'package:flutter_test/flutter_test.dart';
import 'package:run_track_app/features/club_hub/presentation/view_models/club_hub_view_model.dart';
import 'package:run_track_app/features/club_hub/domain/repositories/run_track_repository.dart';

void main() {
  group('ClubHubViewModel', () {
    late _FakeRunTrackRepository repository;
    late ClubHubViewModel viewModel;

    setUp(() async {
      repository = _FakeRunTrackRepository(
        sessions: const [
          ClubSessionItem(
            id: 'session-threshold',
            title: 'Threshold Tuesday',
            description: 'Cruise intervals with the club',
            date: '2026-06-02',
            time: '18:30',
            location: 'Riverside Track',
            athleteName: 'Maya Coach',
            attendees: [
              ClubSessionAttendee(initials: 'MS', rsvpStatus: 'yes'),
              ClubSessionAttendee(
                initials: 'JT',
                imageUrl: 'https://example.com/jt.png',
                rsvpStatus: 'maybe',
              ),
            ],
            currentUserRsvp: 'yes',
          ),
          ClubSessionItem(
            id: 'session-long-run',
            title: 'Sunday Long Run',
            description: 'Easy miles and coffee',
            date: '2026-06-07',
            time: '08:00',
            location: 'Canal Gate',
            attendees: [],
            currentUserRsvp: 'none',
          ),
        ],
        stagedItems: const [
          NewsletterStagingItem(
            status: 'Pending',
            description: 'Add the summer relay announcement',
            date: '2026-06-10',
            time: '09:00',
            location: 'Club newsletter',
          ),
        ],
      );
      viewModel = ClubHubViewModel(
        repository: repository,
        clubId: 'club123',
        athleteId: 'athlete123',
      );
      await Future<void>.delayed(Duration.zero);
      repository.clearLookupHistory();
    });

    tearDown(() {
      viewModel.dispose();
    });

    test('builds state from repository data', () async {
      await viewModel.loadState();
      final state = viewModel.state!;

      expect(state.sessions, hasLength(2));
      expect(state.sessions.first.id, 'session-threshold');
      expect(state.sessions.first.title, 'Threshold Tuesday');
      expect(
        state.sessions.first.description,
        'Cruise intervals with the club',
      );
      expect(state.sessions.first.date, '2026-06-02');
      expect(state.sessions.first.time, '18:30');
      expect(state.sessions.first.location, 'Riverside Track');
      expect(state.sessions.first.athleteName, 'Maya Coach');
      expect(state.sessions.first.attendees, hasLength(2));
      expect(state.sessions.first.attendees.first.initials, 'MS');
      expect(state.sessions.first.attendees.first.rsvpStatus, 'yes');
      expect(state.sessions.first.attendees.last.imageUrl, endsWith('/jt.png'));
      expect(state.sessions.first.currentUserRsvp, 'yes');

      expect(state.stagedItems, hasLength(1));
      expect(state.stagedItems.single.status, 'Pending');
      expect(
        state.stagedItems.single.description,
        'Add the summer relay announcement',
      );
      expect(state.stagedItems.single.date, '2026-06-10');
      expect(state.stagedItems.single.time, '09:00');
      expect(state.stagedItems.single.location, 'Club newsletter');
    });

    test('passes the configured club id to each repository lookup', () async {
      await viewModel.loadState();
      viewModel.state;

      expect(repository.sessionClubIds, ['club123']);
      expect(repository.newsletterClubIds, ['club123']);
    });

    test(
      'returns empty state when the repository has no club hub data',
      () async {
        final emptyViewModel = ClubHubViewModel(
          repository: _FakeRunTrackRepository(
            sessions: const [],
            stagedItems: const [],
          ),
          clubId: 'empty-club',
          athleteId: 'athlete123',
        );
        addTearDown(emptyViewModel.dispose);
        await Future<void>.delayed(Duration.zero);

        await emptyViewModel.loadState();
        final state = emptyViewModel.state!;

        expect(state.sessions, isEmpty);
        expect(state.stagedItems, isEmpty);
      },
    );

    test('reads fresh repository data every time state is requested', () async {
      await viewModel.loadState();
      expect(viewModel.state!.sessions, hasLength(2));

      repository.sessions = const [
        ClubSessionItem(
          id: 'session-recovery',
          title: 'Recovery Shakeout',
          description: 'Short social run',
          date: '2026-06-04',
          time: '07:15',
          location: 'Town Square',
          attendees: [],
          currentUserRsvp: 'none',
        ),
      ];
      repository.stagedItems = const [
        NewsletterStagingItem(
          status: 'Approved',
          description: 'Publish race results',
          date: '2026-06-12',
          time: '16:00',
          location: 'Website',
        ),
        NewsletterStagingItem(
          status: 'Draft',
          description: 'Coach notes',
          date: '2026-06-13',
          time: '11:30',
          location: 'Email',
        ),
      ];

      await viewModel.loadState();
      final refreshedState = viewModel.state!;

      expect(refreshedState.sessions, hasLength(1));
      expect(refreshedState.sessions.single.title, 'Recovery Shakeout');
      expect(refreshedState.stagedItems, hasLength(2));
      expect(refreshedState.stagedItems.first.status, 'Approved');
      expect(repository.sessionClubIds, ['club123', 'club123']);
      expect(repository.newsletterClubIds, ['club123', 'club123']);
    });

    test(
      'updates RSVP with the configured athlete id and refreshes state',
      () async {
        await viewModel.loadState();
        repository.sessionClubIds.clear();
        repository.newsletterClubIds.clear();

        await viewModel.updateRsvp('session-threshold', 'no');

        expect(repository.rsvpUpdates, [
          const _RsvpUpdate(
            sessionId: 'session-threshold',
            athleteId: 'athlete123',
            status: 'no',
          ),
        ]);
        expect(repository.sessionClubIds, ['club123']);
        expect(repository.newsletterClubIds, ['club123']);
      },
    );

    test('does not update RSVP when no athlete id is configured', () async {
      final anonymousViewModel = ClubHubViewModel(
        repository: repository,
        clubId: 'club123',
        athleteId: null,
      );
      addTearDown(anonymousViewModel.dispose);
      await Future<void>.delayed(Duration.zero);

      await anonymousViewModel.updateRsvp('session-threshold', 'yes');

      expect(repository.rsvpUpdates, isEmpty);
    });
  });
}

class _FakeRunTrackRepository implements RunTrackRepository {
  _FakeRunTrackRepository({required this.sessions, required this.stagedItems});

  List<ClubSessionItem> sessions;
  List<NewsletterStagingItem> stagedItems;
  final sessionClubIds = <String>[];
  final newsletterClubIds = <String>[];
  final rsvpUpdates = <_RsvpUpdate>[];

  void clearLookupHistory() {
    sessionClubIds.clear();
    newsletterClubIds.clear();
  }

  @override
  Future<List<ClubSessionItem>> fetchClubSessions(String clubId) async {
    sessionClubIds.add(clubId);
    return sessions;
  }

  @override
  Future<List<NewsletterStagingItem>> fetchNewsletterStaging(
    String clubId,
  ) async {
    newsletterClubIds.add(clubId);
    return stagedItems;
  }

  @override
  Future<void> updateRsvp(
    String sessionId,
    String athleteId,
    String status,
  ) async {
    rsvpUpdates.add(
      _RsvpUpdate(sessionId: sessionId, athleteId: athleteId, status: status),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RsvpUpdate {
  const _RsvpUpdate({
    required this.sessionId,
    required this.athleteId,
    required this.status,
  });

  final String sessionId;
  final String athleteId;
  final String status;

  @override
  bool operator ==(Object other) =>
      other is _RsvpUpdate &&
      other.sessionId == sessionId &&
      other.athleteId == athleteId &&
      other.status == status;

  @override
  int get hashCode => Object.hash(sessionId, athleteId, status);
}
