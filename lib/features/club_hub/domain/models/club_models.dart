import 'package:flutter/foundation.dart';

@immutable
class ClubHubState {
  const ClubHubState({required this.sessions, required this.stagedItems});

  final List<ClubSessionItem> sessions;
  final List<NewsletterStagingItem> stagedItems;
}

@immutable
class ClubSessionItem {
  const ClubSessionItem({
    required this.id,
    required this.title,
    required this.description,
    required this.date,
    required this.time,
    required this.location,
    this.athleteName,
    required this.attendees,
    required this.currentUserRsvp,
  });

  final String id;
  final String title;
  final String description;
  final String date;
  final String time;
  final String location;
  final String? athleteName;
  final List<ClubSessionAttendee> attendees;
  final String currentUserRsvp;

  factory ClubSessionItem.fromJson(
    Map<String, dynamic> json,
    String currentAthleteId,
  ) {
    final attendeesJson = json['attendees'] as List<dynamic>? ?? const [];
    final attendees = [
      for (final attendee in attendeesJson)
        ClubSessionAttendee.fromJson(attendee as Map<String, dynamic>),
    ];

    // Find current user in attendees to set their RSVP status
    String status = "none";
    try {
      final userAttendee = attendeesJson.firstWhere(
        (a) => a['athlete_id'] == currentAthleteId,
      );
      status = userAttendee['rsvp_status'] ?? "none";
    } catch (_) {}

    return ClubSessionItem(
      id: json['id']?.toString() ?? '',
      title: json['title'] as String,
      description: json['description'] as String,
      date: json['date'] as String,
      time: json['time'] as String,
      location: json['location'] as String,
      athleteName: json['athlete_name'] as String?,
      attendees: attendees,
      currentUserRsvp: status,
    );
  }
}

@immutable
class ClubSessionAttendee {
  const ClubSessionAttendee({
    required this.initials,
    this.imageUrl,
    required this.rsvpStatus,
  });

  final String initials;
  final String? imageUrl;
  final String rsvpStatus;

  factory ClubSessionAttendee.fromJson(Map<String, dynamic> json) {
    return ClubSessionAttendee(
      initials: json['athlete_initials'] as String,
      imageUrl: json['athlete_image_url'] as String?,
      rsvpStatus: json['rsvp_status'] ?? "yes",
    );
  }
}

@immutable
class NewsletterStagingItem {
  const NewsletterStagingItem({
    required this.status,
    required this.description,
    required this.date,
    required this.time,
    required this.location,
  });

  final String status;
  final String description;
  final String date;
  final String time;
  final String location;

  factory NewsletterStagingItem.fromJson(Map<String, dynamic> json) {
    final extractedJson = json['extracted_json'] as Map<String, dynamic>;

    return NewsletterStagingItem(
      status: json['status'] as String,
      description: extractedJson['description'] as String,
      date: extractedJson['date'] as String,
      time: extractedJson['time'] as String,
      location: extractedJson['location'] as String,
    );
  }
}
