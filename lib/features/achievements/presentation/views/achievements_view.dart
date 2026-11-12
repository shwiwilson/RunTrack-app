import 'package:run_track_app/features/achievements/presentation/views/race_result_editor.dart';
import 'package:flutter/material.dart';
import 'package:run_track_app/core/theme/premium_typography.dart';
import 'package:run_track_app/core/widgets/premium_card.dart';
import 'package:run_track_app/domain/run_track_snapshot.dart';
import 'package:run_track_app/features/achievements/domain/models/achievements_models.dart';
import 'package:run_track_app/features/application/run_track_controller.dart';
import 'package:run_track_app/features/club_hub/domain/models/club_models.dart';
import 'package:run_track_app/features/shared/feature_widgets.dart';

class AchievementsView extends StatelessWidget {
  const AchievementsView({
    required this.data,
    required this.controller,
    super.key,
  });
  final RunTrackSnapshot data;
  final RunTrackController controller;
  @override
  Widget build(BuildContext context) {
    final achievements = RunningAchievement.calculate(
      data.activities,
      now: DateTime.now(),
      attendedSessions: data.attendanceCount,
    );
    final earned = achievements.where((a) => a.earned).length;
    final monthly = <String, double>{};
    final now = DateTime.now();
    for (final activity in data.clubActivities.where((a) => a.isRunning)) {
      final start = activity.startedAt.toLocal();
      if (start.year == now.year &&
          start.month == now.month &&
          !activity.endedAt.isAfter(now)) {
        monthly[activity.userId] =
            (monthly[activity.userId] ?? 0) + (activity.distanceM ?? 0);
      }
    }
    final ranked = monthly.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return FeaturePage(
      children: [
        FeatureTitle(
          'Achievements',
          subtitle:
              '$earned earned · Built from your recorded runs and confirmed attendance.',
        ),
        if (earned == 0)
          const EmptyFeature(
            icon: Icons.emoji_events_outlined,
            title: 'Your running achievements start here',
            message:
                'No achievements earned yet. Your milestones will appear as you complete runs and attend club sessions.',
          ),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 650 ? 2 : 1;
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                for (final achievement in achievements)
                  SizedBox(
                    width:
                        (constraints.maxWidth - 16 * (columns - 1)) / columns,
                    child: PremiumCard(
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              achievement.earned
                                  ? Icons.emoji_events
                                  : Icons.emoji_events_outlined,
                              color: achievement.earned
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.outline,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    achievement.title,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(achievement.description),
                                  const SizedBox(height: 6),
                                  Text(
                                    achievement.earned
                                        ? 'Earned'
                                        : 'Not earned yet',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.labelMedium,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
        PremiumCard(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Club challenges',
                    style: Theme.of(context).textTheme.serifSectionTitle,
                  ),
                ),
                if (data.membership?.isAdmin == true)
                  IconButton(
                    tooltip: 'Create challenge',
                    onPressed: () => _editChallenge(context),
                    icon: const Icon(Icons.add),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (data.challenges.isEmpty)
              Text(
                data.membership?.isAdmin == true
                    ? 'No club challenges yet. Create a distance challenge for your members.'
                    : 'Club challenges will appear here when your club creates them.',
              ),
            for (final challenge in data.challenges)
              _challenge(context, challenge),
          ],
        ),
        PremiumCard(
          children: [
            Text(
              'Monthly club distance',
              style: Theme.of(context).textTheme.serifSectionTitle,
            ),
            const SizedBox(height: 10),
            const Text(
              'Only distances from runs explicitly shared with your club are included. This is not a ranking of private training.',
            ),
            const SizedBox(height: 12),
            if (ranked.isEmpty)
              const Text('No shared runs on the leaderboard this month.'),
            for (var i = 0; i < ranked.length; i++)
              MetricPair(
                '${i > 0 && ranked[i].value == ranked[i - 1].value ? ranked.indexWhere((e) => e.value == ranked[i].value) + 1 : i + 1}. ${data.memberNames[ranked[i].key] ?? 'Club member'}',
                distanceLabel(ranked[i].value),
              ),
          ],
        ),
        PremiumCard(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Race results',
                    style: Theme.of(context).textTheme.serifSectionTitle,
                  ),
                ),
                IconButton(
                  tooltip: 'Add race result',
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (context) =>
                        RaceResultEditor(controller: controller),
                  ),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (data.raceResults.isEmpty)
              const Text('No race results recorded yet.'),
            for (final race in data.raceResults) ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      race.eventName,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Delete race result',
                    onPressed: controller.saving
                        ? null
                        : () async {
                            final remove = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Delete race result?'),
                                content: Text(
                                  'Remove ${race.eventName} from your results?',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, false),
                                    child: const Text('Cancel'),
                                  ),
                                  FilledButton(
                                    onPressed: () =>
                                        Navigator.pop(context, true),
                                    child: const Text('Delete'),
                                  ),
                                ],
                              ),
                            );
                            if (remove == true) {
                              await controller.mutate(
                                () => controller.repository.deleteRaceResult(
                                  race.id,
                                ),
                              );
                            }
                          },
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
              MetricPair(
                '${dateLabel(race.eventDate)} · ${distanceLabel(race.distanceM)}',
                durationLabel(race.durationS),
              ),
              Text(
                race.verified
                    ? 'Verified result with supporting evidence'
                    : 'Unverified result',
              ),
              const SizedBox(height: 16),
            ],
          ],
        ),
      ],
    );
  }

  void _editChallenge(BuildContext context, [ClubChallenge? challenge]) =>
      showDialog<void>(
        context: context,
        builder: (context) =>
            _ChallengeEditor(controller: controller, challenge: challenge),
      );
  Widget _challenge(BuildContext context, ClubChallenge challenge) {
    final distance = data.activities
        .where(
          (a) =>
              a.isRunning &&
              a.duplicateOf == null &&
              !a.startedAt.isBefore(challenge.startsAt) &&
              a.startedAt.isBefore(challenge.endsAt) &&
              !a.endedAt.isAfter(DateTime.now()),
        )
        .fold(0.0, (sum, a) => sum + (a.distanceM ?? 0));
    final ended = !challenge.endsAt.isAfter(DateTime.now());
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  challenge.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (data.membership?.isAdmin == true)
                PopupMenuButton<String>(
                  tooltip: 'Manage challenge',
                  onSelected: (action) async {
                    if (action == 'edit') {
                      _editChallenge(context, challenge);
                    } else {
                      final remove = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Delete challenge?'),
                          content: const Text(
                            'This also removes its participation records.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Cancel'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('Delete'),
                            ),
                          ],
                        ),
                      );
                      if (remove == true) {
                        await controller.mutate(
                          () => controller.repository.deleteChallenge(
                            challenge.id,
                          ),
                        );
                      }
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'edit', child: Text('Edit challenge')),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text('Delete challenge'),
                    ),
                  ],
                ),
            ],
          ),
          Text(challenge.description),
          const SizedBox(height: 6),
          Text(
            '${dateLabel(challenge.startsAt)} – ${dateLabel(challenge.endsAt)} · ${distanceLabel(challenge.targetDistanceM)}',
          ),
          if (challenge.joined) ...[
            const SizedBox(height: 8),
            Text('Your recorded distance: ${distanceLabel(distance)}'),
            if (distance >= challenge.targetDistanceM)
              const Text('Distance goal reached'),
          ],
          if (!ended)
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                onPressed: controller.saving
                    ? null
                    : () => controller.mutate(
                        () => controller.repository.participate(
                          challenge.id,
                          !challenge.joined,
                        ),
                      ),
                child: Text(
                  challenge.joined ? 'Leave challenge' : 'Join challenge',
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ChallengeEditor extends StatefulWidget {
  const _ChallengeEditor({required this.controller, this.challenge});
  final RunTrackController controller;
  final ClubChallenge? challenge;
  @override
  State<_ChallengeEditor> createState() => _ChallengeEditorState();
}

class _ChallengeEditorState extends State<_ChallengeEditor> {
  final form = GlobalKey<FormState>();
  late final TextEditingController title;
  late final TextEditingController description;
  late final TextEditingController distance;
  late DateTime start;
  late DateTime end;
  bool saving = false;
  @override
  void initState() {
    super.initState();
    final c = widget.challenge;
    title = TextEditingController(text: c?.title);
    description = TextEditingController(text: c?.description);
    distance = TextEditingController(
      text: c == null ? '' : (c.targetDistanceM / 1000).toString(),
    );
    start = c?.startsAt.toLocal() ?? DateTime.now();
    end = c?.endsAt.toLocal() ?? start.add(const Duration(days: 30));
  }

  @override
  void dispose() {
    title.dispose();
    description.dispose();
    distance.dispose();
    super.dispose();
  }

  Future<void> pick(bool first) async {
    final value = await showDatePicker(
      context: context,
      initialDate: first ? start : end,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (value != null && mounted) {
      setState(() {
        if (first) {
          start = value;
        } else {
          end = value;
        }
      });
    }
  }

  Future<void> save() async {
    if (!form.currentState!.validate() || !end.isAfter(start)) return;
    setState(() => saving = true);
    final ok = await widget.controller.mutate(
      () => widget.controller.repository.saveChallenge(
        id: widget.challenge?.id,
        clubId: widget.controller.snapshot!.membership!.clubId,
        title: title.text,
        description: description.text,
        startsAt: start,
        endsAt: end,
        targetDistanceM: double.parse(distance.text) * 1000,
      ),
    );
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context);
    } else {
      setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.challenge == null
          ? 'Create distance challenge'
          : 'Edit distance challenge',
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
                maxLength: 150,
                decoration: const InputDecoration(labelText: 'Challenge title'),
                validator: (v) => v!.trim().isEmpty ? 'Enter a title.' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: description,
                maxLength: 2000,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Description'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: distance,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Target distance in kilometres',
                ),
                validator: (v) {
                  final n = double.tryParse(v ?? '');
                  return n == null || !n.isFinite || n <= 0
                      ? 'Enter a positive distance.'
                      : null;
                },
              ),
              ListTile(
                title: const Text('Starts'),
                subtitle: Text(dateLabel(start)),
                onTap: () => pick(true),
              ),
              ListTile(
                title: const Text('Ends (exclusive)'),
                subtitle: Text(dateLabel(end)),
                onTap: () => pick(false),
              ),
              if (!end.isAfter(start))
                const Text('End date must be after the start date.'),
              if (widget.controller.error != null)
                Text(widget.controller.error!),
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
        child: Text(saving ? 'Saving…' : 'Save challenge'),
      ),
    ],
  );
}
