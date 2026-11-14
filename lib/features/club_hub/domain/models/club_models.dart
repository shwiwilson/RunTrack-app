import 'package:flutter/foundation.dart';

@immutable
class ClubMembership {
  const ClubMembership({
    required this.id,
    required this.clubId,
    required this.userId,
    required this.role,
    required this.status,
    required this.clubName,
    this.theme = const {},
    this.installSlug,
    this.brandingUpdatedAt,
    this.clubStatus = 'active',
  });
  final String id;
  final String clubId;
  final String userId;
  final String role;
  final String status;
  final String clubName;
  final Map<String, dynamic> theme;
  final String? installSlug;
  final String? brandingUpdatedAt;
  final String clubStatus;

  bool get isActive => status == 'active' && clubStatus == 'active';
  bool get isAdmin => role == 'admin' && isActive;

  static ClubMembership? selectActive(
    Iterable<ClubMembership> memberships, {
    String? preferredId,
    String? launchSlug,
  }) {
    final active = memberships.where((membership) => membership.isActive);
    return active
            .where((membership) => membership.clubId == preferredId)
            .firstOrNull ??
        active
            .where(
              (membership) =>
                  membership.installSlug == launchSlug && launchSlug != null,
            )
            .firstOrNull ??
        active.firstOrNull;
  }

  factory ClubMembership.fromJson(Map<String, dynamic> json) {
    final club = Map<String, dynamic>.from(json['clubs'] as Map? ?? {});
    return ClubMembership(
      id: json['id'] as String,
      clubId: json['club_id'] as String,
      userId: json['user_id'] as String,
      role: json['role'] as String,
      status: json['status'] as String,
      clubName: club['name'] as String? ?? 'Your club',
      installSlug: club['install_slug'] as String?,
      brandingUpdatedAt: club['updated_at'] as String?,
      clubStatus:
          club['status'] as String? ?? (club.isEmpty ? 'inactive' : 'active'),
      theme: Map<String, dynamic>.from(club['theme_json'] as Map? ?? {}),
    );
  }
}

@immutable
class SessionRsvp {
  const SessionRsvp({
    required this.id,
    required this.userId,
    required this.status,
    required this.attended,
  });
  final String id;
  final String userId;
  final String status;
  final bool attended;
  factory SessionRsvp.fromJson(Map<String, dynamic> json) => SessionRsvp(
    id: json['id'] as String,
    userId: json['user_id'] as String,
    status: json['status'] as String,
    attended: json['attended'] == true,
  );
}

@immutable
class ClubSession {
  const ClubSession({
    required this.id,
    required this.clubId,
    required this.title,
    required this.details,
    required this.location,
    required this.startsAt,
    this.endsAt,
    this.rsvps = const [],
  });
  final String id;
  final String clubId;
  final String title;
  final String details;

  /// A written meeting point only; the app never asks for location permissions.
  final String location;
  final DateTime startsAt;
  final DateTime? endsAt;
  final List<SessionRsvp> rsvps;
  factory ClubSession.fromJson(Map<String, dynamic> json) => ClubSession(
    id: json['id'] as String,
    clubId: json['club_id'] as String,
    title: json['title'] as String,
    details: json['details'] as String? ?? '',
    location: json['location'] as String? ?? '',
    startsAt: DateTime.parse(json['starts_at'] as String).toUtc(),
    endsAt: json['ends_at'] == null
        ? null
        : DateTime.parse(json['ends_at'] as String).toUtc(),
    rsvps: (json['session_rsvps'] as List? ?? [])
        .map((e) => SessionRsvp.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(),
  );
}

@immutable
class ClubChallenge {
  const ClubChallenge({
    required this.id,
    required this.clubId,
    required this.title,
    required this.description,
    required this.startsAt,
    required this.endsAt,
    required this.targetDistanceM,
    required this.joined,
  });
  final String id;
  final String clubId;
  final String title;
  final String description;
  final DateTime startsAt;
  final DateTime endsAt;
  final double targetDistanceM;
  final bool joined;
  factory ClubChallenge.fromJson(Map<String, dynamic> json, String userId) =>
      ClubChallenge(
        id: json['id'] as String,
        clubId: json['club_id'] as String,
        title: json['title'] as String,
        description: json['description'] as String? ?? '',
        startsAt: DateTime.parse(json['starts_at'] as String).toUtc(),
        endsAt: DateTime.parse(json['ends_at'] as String).toUtc(),
        targetDistanceM: (json['target_distance_m'] as num).toDouble(),
        joined: (json['challenge_participants'] as List? ?? []).any(
          (e) => e['user_id'] == userId,
        ),
      );
}
