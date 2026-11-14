import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:run_track_app/core/theme/club_branding.dart';
import 'club_branding_editor.dart';
import 'package:run_track_app/core/theme/premium_typography.dart';
import 'package:run_track_app/core/widgets/premium_card.dart';
import 'package:run_track_app/domain/run_track_snapshot.dart';
import 'package:run_track_app/features/application/run_track_controller.dart';
import 'package:run_track_app/features/club_hub/domain/models/club_models.dart';
import 'package:run_track_app/features/shared/feature_widgets.dart';

class ClubHubView extends StatelessWidget {
  const ClubHubView({
    required this.data,
    required this.controller,
    required this.onJoinClub,
    super.key,
  });
  final RunTrackSnapshot data;
  final RunTrackController controller;
  final VoidCallback onJoinClub;
  @override
  Widget build(BuildContext context) {
    final membership = data.membership;
    if (membership == null) {
      return FeaturePage(
        children: [
          const FeatureTitle('Club Hub'),
          EmptyFeature(
            icon: Icons.groups_outlined,
            title: "You're not in a club yet",
            message:
                'Enter your club joining code to find sessions and run together.',
            actionLabel: 'Enter joining code',
            onAction: onJoinClub,
          ),
        ],
      );
    }
    final activeClubs = data.memberships
        .where((club) => club.isActive)
        .toList();
    final installPath = clubInstallPath(membership);
    final now = DateTime.now();
    final upcoming =
        data.sessions.where((s) => !s.startsAt.isBefore(now)).toList()
          ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    final previous =
        data.sessions.where((s) => s.startsAt.isBefore(now)).toList()
          ..sort((a, b) => b.startsAt.compareTo(a.startsAt));
    return FeaturePage(
      children: [
        FeatureTitle(
          membership.clubName,
          subtitle: membership.isAdmin
              ? 'Your club, ready to run. You are a club administrator.'
              : 'Your people. Your next run.',
        ),
        if (activeClubs.length > 1)
          DropdownButtonFormField<String>(
            key: ValueKey(membership.clubId),
            initialValue: membership.clubId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Active club'),
            items: [
              for (final club in activeClubs)
                DropdownMenuItem(
                  value: club.clubId,
                  child: Text(club.clubName, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: controller.saving
                ? null
                : (clubId) {
                    if (clubId != null) controller.switchClub(clubId);
                  },
          ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (kIsWeb && installPath != null)
              OutlinedButton.icon(
                onPressed: () => launchUrl(
                  Uri.base.resolve(installPath),
                  webOnlyWindowName: '_blank',
                ),
                icon: const Icon(Icons.install_mobile),
                label: const Text('Install club app'),
              ),
            TextButton.icon(
              onPressed: controller.saving ? null : onJoinClub,
              icon: const Icon(Icons.group_add_outlined),
              label: const Text('Join another club'),
            ),
          ],
        ),
        if (membership.isAdmin)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: controller.saving
                    ? null
                    : () => _editSession(context),
                icon: const Icon(Icons.add),
                label: const Text('Create session'),
              ),
              OutlinedButton.icon(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (context) => _ClubManagement(controller: controller),
                ),
                icon: const Icon(Icons.settings_outlined),
                label: const Text('Manage club'),
              ),
            ],
          ),
        if (upcoming.isEmpty)
          EmptyFeature(
            icon: Icons.event_outlined,
            title: 'No club sessions scheduled',
            message: membership.isAdmin
                ? 'Create the first session for your club. Members will be able to RSVP here.'
                : 'Your next club session will appear here when an administrator schedules it.',
            actionLabel: membership.isAdmin ? 'Create first session' : null,
            onAction: membership.isAdmin ? () => _editSession(context) : null,
          ),
        for (final session in upcoming)
          _session(context, session, membership, past: false),
        if (previous.isNotEmpty)
          Text(
            'Past sessions',
            style: Theme.of(context).textTheme.serifSectionTitle,
          ),
        for (final session in previous)
          _session(context, session, membership, past: true),
      ],
    );
  }

  void _editSession(BuildContext context, [ClubSession? session]) =>
      showDialog<void>(
        context: context,
        builder: (context) =>
            _SessionEditor(controller: controller, session: session),
      );
  Widget _session(
    BuildContext context,
    ClubSession session,
    ClubMembership membership, {
    required bool past,
  }) {
    final own = session.rsvps
        .where((r) => r.userId == data.profile.id)
        .firstOrNull;
    final going = session.rsvps.where((r) => r.status == 'going').toList();
    return PremiumCard(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                session.title,
                style: Theme.of(context).textTheme.serifSectionTitle,
              ),
            ),
            if (membership.isAdmin)
              PopupMenuButton<String>(
                tooltip: 'Manage session',
                onSelected: (action) async {
                  if (action == 'edit') {
                    _editSession(context, session);
                  } else if (await _confirm(
                    context,
                    'Delete session?',
                    'This also removes its RSVP and attendance records.',
                  )) {
                    await controller.mutate(
                      () => controller.repository.deleteSession(session.id),
                    );
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit session')),
                  PopupMenuItem(value: 'delete', child: Text('Delete session')),
                ],
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(dateTimeLabel(session.startsAt)),
        if (session.location.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Meeting point: ${session.location}'),
        ],
        if (session.details.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(session.details),
        ],
        const SizedBox(height: 16),
        Text('${going.length} going'),
        if (going.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            going
                .map((r) => data.memberNames[r.userId] ?? 'Club member')
                .join(', '),
          ),
        ],
        if (!past) ...[
          const SizedBox(height: 14),
          FilledButton.tonalIcon(
            onPressed: controller.saving
                ? null
                : () => controller.mutate(
                    () => controller.repository.rsvp(
                      session.id,
                      own?.status != 'going',
                    ),
                  ),
            icon: Icon(
              own?.status == 'going' ? Icons.check : Icons.event_available,
            ),
            label: Text(
              own?.status == 'going' ? 'Cancel RSVP' : "I'll be there",
            ),
          ),
        ],
        if (own?.attended == true) ...[
          const SizedBox(height: 12),
          const Text('Your attendance is confirmed.'),
        ],
        if (membership.isAdmin && past && going.isNotEmpty) ...[
          const Divider(height: 28),
          const Text('Confirm attendance'),
          for (final rsvp in going)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(data.memberNames[rsvp.userId] ?? 'Club member'),
              value: rsvp.attended,
              onChanged: controller.saving
                  ? null
                  : (attended) => controller.mutate(
                      () => controller.repository.confirmAttendance(
                        rsvp.id,
                        attended!,
                      ),
                    ),
            ),
        ],
      ],
    );
  }
}

Future<bool> _confirm(
  BuildContext context,
  String title,
  String message,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    ) ??
    false;

class _SessionEditor extends StatefulWidget {
  const _SessionEditor({required this.controller, this.session});
  final RunTrackController controller;
  final ClubSession? session;
  @override
  State<_SessionEditor> createState() => _SessionEditorState();
}

class _SessionEditorState extends State<_SessionEditor> {
  final form = GlobalKey<FormState>();
  late final TextEditingController title;
  late final TextEditingController details;
  late final TextEditingController location;
  late DateTime startsAt;
  bool saving = false;
  @override
  void initState() {
    super.initState();
    title = TextEditingController(text: widget.session?.title);
    details = TextEditingController(text: widget.session?.details);
    location = TextEditingController(text: widget.session?.location);
    startsAt =
        widget.session?.startsAt.toLocal() ??
        DateTime.now().add(const Duration(days: 1));
  }

  @override
  void dispose() {
    title.dispose();
    details.dispose();
    location.dispose();
    super.dispose();
  }

  Future<void> pick() async {
    final date = await showDatePicker(
      context: context,
      initialDate: startsAt,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(startsAt),
    );
    if (time != null && mounted) {
      setState(
        () => startsAt = DateTime(
          date.year,
          date.month,
          date.day,
          time.hour,
          time.minute,
        ),
      );
    }
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    setState(() => saving = true);
    final success = await widget.controller.mutate(
      () => widget.controller.repository.saveSession(
        id: widget.session?.id,
        clubId: widget.controller.snapshot!.membership!.clubId,
        title: title.text,
        details: details.text,
        location: location.text,
        startsAt: startsAt,
      ),
    );
    if (!mounted) return;
    if (success) {
      Navigator.pop(context);
    } else {
      setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.session == null ? 'Create club session' : 'Edit club session',
    ),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: title,
                decoration: const InputDecoration(labelText: 'Session title'),
                maxLength: 150,
                validator: (v) => v!.trim().isEmpty ? 'Enter a title.' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: details,
                decoration: const InputDecoration(labelText: 'Session details'),
                maxLines: 3,
                maxLength: 4000,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: location,
                decoration: const InputDecoration(labelText: 'Meeting point'),
                maxLength: 300,
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Start date and time'),
                subtitle: Text(dateTimeLabel(startsAt)),
                trailing: const Icon(Icons.edit_calendar_outlined),
                onTap: saving ? null : pick,
              ),
              const Text(
                'Times use your device timezone and are stored as UTC.',
              ),
              if (widget.controller.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(widget.controller.error!),
                ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: saving ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: saving ? null : save,
        child: Text(saving ? 'Saving…' : 'Save session'),
      ),
    ],
  );
}

class _ClubManagement extends StatelessWidget {
  const _ClubManagement({required this.controller});
  final RunTrackController controller;
  Future<void> _textChange(
    BuildContext context,
    String title,
    String label,
    String initial,
    Future<void> Function(String) save, {
    String? description,
  }) async {
    final input = TextEditingController(text: initial);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (description != null) ...[
              Text(description),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: input,
              decoration: InputDecoration(labelText: label),
              maxLength: 150,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, input.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    input.dispose();
    if (value != null && value.isNotEmpty) {
      await controller.mutate(() => save(value));
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final data = controller.snapshot!;
      final membership = data.membership;
      if (membership == null || !membership.isAdmin) {
        return AlertDialog(
          title: const Text('Club access updated'),
          content: const Text(
            'Your club administrator permissions have changed. Close this window to continue.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      }
      return AlertDialog(
        title: const Text('Manage club'),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Club branding'),
                  subtitle: Text(membership.clubName),
                  trailing: const Icon(Icons.palette_outlined),
                  onTap: controller.saving
                      ? null
                      : () => showDialog<void>(
                          context: context,
                          builder: (_) => ClubBrandingEditor(
                            controller: controller,
                            club: membership,
                          ),
                        ),
                ),
                OutlinedButton.icon(
                  onPressed: controller.saving
                      ? null
                      : () => _textChange(
                          context,
                          'Rotate joining code',
                          'New joining code',
                          '',
                          (value) => controller.repository.rotateCode(
                            membership.clubId,
                            value,
                          ),
                          description:
                              'The previous code will stop working. Existing members keep their membership. Share the new code privately.',
                        ),
                  icon: const Icon(Icons.key_outlined),
                  label: const Text('Rotate joining code'),
                ),
                const Divider(height: 30),
                Text(
                  'Memberships',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                for (final member in data.clubMembers)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      data.memberNames[member.userId] ??
                          'Member ${member.userId.substring(0, 8)}',
                    ),
                    subtitle: Text(
                      '${member.role == 'admin' ? 'Club administrator' : 'Athlete'} · ${member.status}',
                    ),
                    trailing: PopupMenuButton<String>(
                      enabled: !controller.saving,
                      tooltip: 'Manage membership',
                      onSelected: (action) async {
                        final status = action == 'remove'
                            ? 'removed'
                            : 'active';
                        final role = action == 'admin' ? 'admin' : 'athlete';
                        if (await _confirm(
                          context,
                          'Update membership?',
                          action == 'remove'
                              ? 'Remove this member from the club?'
                              : action == 'admin'
                              ? 'Grant this member club administrator permissions?'
                              : 'Set this member to an active athlete?',
                        )) {
                          await controller.mutate(
                            () => controller.repository.updateMember(
                              member,
                              status,
                              role,
                            ),
                          );
                        }
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: 'athlete',
                          child: Text('Approve / make athlete'),
                        ),
                        PopupMenuItem(
                          value: 'admin',
                          child: Text('Make club administrator'),
                        ),
                        PopupMenuItem(
                          value: 'remove',
                          child: Text('Remove membership'),
                        ),
                      ],
                    ),
                  ),
                if (controller.error != null) Text(controller.error!),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      );
    },
  );
}
