import 'package:flutter_test/flutter_test.dart';
import 'package:run_track_app/features/club_hub/domain/models/club_models.dart';

void main() {
  group('ClubSessionItem', () {
    test('should create from JSON correctly', () {
      const json = {
        'id': 'session-1',
        'title': 'Morning Run Club',
        'description': '5k run with fellow athletes',
        'date': '2024-01-15',
        'time': '09:00',
        'location': 'Central Park',
        'athlete_name': 'John Doe',
        'attendees': [
          {
            'athlete_id': 'athlete-john',
            'athlete_initials': 'JD',
            'athlete_image_url': 'https://example.com/john.jpg',
            'rsvp_status': 'yes',
          },
          {
            'athlete_id': 'athlete-jane',
            'athlete_initials': 'JW',
            'athlete_image_url': null,
            'rsvp_status': 'maybe',
          },
        ],
      };

      final session = ClubSessionItem.fromJson(json, 'athlete-jane');

      expect(session.id, equals('session-1'));
      expect(session.title, equals('Morning Run Club'));
      expect(session.description, contains('5k run'));
      expect(session.date, equals('2024-01-15'));
      expect(session.time, equals('09:00'));
      expect(session.location, equals('Central Park'));
      expect(session.attendees.length, equals(2));
      expect(session.attendees.first.rsvpStatus, equals('yes'));
      expect(session.attendees.last.rsvpStatus, equals('maybe'));
      expect(session.currentUserRsvp, equals('maybe'));
    });

    test('should handle empty attendees list', () {
      const json = {
        'id': 'session-2',
        'title': 'Solo Run',
        'description': 'Individual workout',
        'date': '2024-01-20',
        'time': '18:00',
        'location': 'Home',
        'athlete_name': null,
        'attendees': [],
      };

      final session = ClubSessionItem.fromJson(json, 'missing-athlete');

      expect(session.attendees, isEmpty);
      expect(session.athleteName, isNull);
      expect(session.currentUserRsvp, equals('none'));
    });
  });

  group('ClubSessionAttendee', () {
    test('should create from JSON correctly', () {
      const json = {
        'athlete_initials': 'JD',
        'athlete_image_url': 'https://example.com/john.jpg',
        'rsvp_status': 'no',
      };

      final attendee = ClubSessionAttendee.fromJson(json);

      expect(attendee.initials, equals('JD'));
      expect(attendee.imageUrl, equals('https://example.com/john.jpg'));
      expect(attendee.rsvpStatus, equals('no'));
    });

    test('should handle null image URL', () {
      const json = {'athlete_initials': 'AK', 'athlete_image_url': null};

      final attendee = ClubSessionAttendee.fromJson(json);

      expect(attendee.imageUrl, isNull);
      expect(attendee.rsvpStatus, equals('yes'));
    });
  });

  group('NewsletterStagingItem', () {
    test('should create from JSON correctly', () {
      const json = {
        'status': 'Pending',
        'extracted_json': {
          'description': 'Weekly Newsletter Draft',
          'date': '2024-01-10',
          'time': '14:00',
          'location': 'Email',
        },
      };

      final item = NewsletterStagingItem.fromJson(json);

      expect(item.status, equals('Pending'));
      expect(item.description, equals('Weekly Newsletter Draft'));
    });

    test('should handle different status values', () {
      const statuses = ['Pending', 'Published', 'Draft', 'Cancelled'];

      for (final status in statuses) {
        final json = {
          'status': status,
          'extracted_json': {
            'description': 'Test',
            'date': '2024-01-10',
            'time': '14:00',
            'location': 'Email',
          },
        };
        final item = NewsletterStagingItem.fromJson(json);
        expect(item.status, equals(status));
      }
    });
  });
}
