import 'package:flutter/material.dart';
import 'package:run_track_app/core/theme/premium_typography.dart';
import 'package:run_track_app/core/widgets/premium_card.dart';
import 'package:run_track_app/domain/run_track_snapshot.dart';
import 'package:run_track_app/features/activity/domain/models/activity_models.dart';
import 'package:run_track_app/features/application/run_track_controller.dart';
import 'package:run_track_app/features/shared/feature_widgets.dart';

class RunTrackView extends StatefulWidget {
  const RunTrackView({
    required this.data,
    required this.controller,
    required this.onConnectHealth,
    super.key,
  });
  final RunTrackSnapshot data;
  final RunTrackController controller;
  final VoidCallback onConnectHealth;
  @override
  State<RunTrackView> createState() => _RunTrackViewState();
}

class _RunTrackViewState extends State<RunTrackView> {
  bool club = false;
  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final activities = (club ? data.clubActivities : data.activities).toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return FeaturePage(
      children: [
        const FeatureTitle(
          'RunTrack',
          subtitle: 'Your real runs, in one place.',
        ),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(
              value: false,
              label: Text('Your activities'),
              icon: Icon(Icons.person_outline),
            ),
            ButtonSegment(
              value: true,
              label: Text('Club feed'),
              icon: Icon(Icons.groups_outlined),
            ),
          ],
          selected: {club},
          onSelectionChanged: (selection) =>
              setState(() => club = selection.first),
        ),
        if (club)
          const Text(
            'Only activities deliberately shared with this club appear here. Private heart-rate measurements stay private.',
          ),
        if (activities.isEmpty)
          EmptyFeature(
            icon: Icons.directions_run,
            title: club
                ? 'No shared club activities yet'
                : 'No runs recorded yet',
            message: club
                ? 'Members can choose to share a run with their club. Private activities stay on your own account.'
                : 'Connect your running data to see your training history.',
            actionLabel: club ? null : 'Connect your running data',
            onAction: club ? null : widget.onConnectHealth,
          ),
        for (final activity in activities)
          PremiumCard(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      activity.type.replaceAll('_', ' '),
                      style: Theme.of(context).textTheme.serifSectionTitle,
                    ),
                  ),
                  Icon(
                    activity.visibility == 'private'
                        ? Icons.lock_outline
                        : Icons.groups_outlined,
                    size: 20,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                club
                    ? (data.memberNames[activity.userId] ?? 'Club member')
                    : dateTimeLabel(activity.startedAt),
              ),
              if (club) Text(dateTimeLabel(activity.startedAt)),
              const SizedBox(height: 12),
              MetricPair('Distance', distanceLabel(activity.distanceM)),
              MetricPair(
                'Active time',
                durationLabel(activity.activeDurationS),
              ),
              MetricPair('Average pace', paceLabel(activity.paceSecondsPerKm)),
              const SizedBox(height: 8),
              Text('Source: ${activity.provider.replaceAll('_', ' ')}'),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (context) => _ActivityDetails(activity: activity),
                  ),
                  child: const Text('View activity details'),
                ),
              ),
              if (!club && activity.userId == data.profile.id)
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    activity.visibility == 'club' &&
                            activity.sharedClubId != data.membership?.clubId
                        ? 'Shared with a previous club'
                        : 'Share with your club',
                  ),
                  subtitle: Text(
                    data.membership == null
                        ? activity.visibility == 'club'
                              ? 'Turn off sharing to make this activity private.'
                              : 'Join a club to share this activity.'
                        : 'Share distance, duration, pace and date. Heart-rate details stay private.',
                  ),
                  value: activity.visibility == 'club',
                  onChanged:
                      (data.membership == null &&
                              activity.visibility != 'club') ||
                          widget.controller.saving
                      ? null
                      : (share) => widget.controller.mutate(
                          () => widget.controller.repository.shareActivity(
                            activity.id,
                            share ? data.membership!.clubId : null,
                          ),
                        ),
                ),
            ],
          ),
      ],
    );
  }
}

class _ActivityDetails extends StatelessWidget {
  const _ActivityDetails({required this.activity});
  final Activity activity;
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Activity details'),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MetricPair('Date', dateTimeLabel(activity.startedAt)),
            if (activity.timeZone != null)
              MetricPair('Source timezone', activity.timeZone!),
            MetricPair('Distance', distanceLabel(activity.distanceM)),
            MetricPair('Active time', durationLabel(activity.activeDurationS)),
            MetricPair(
              'Elapsed time',
              durationLabel(activity.elapsedDurationS),
            ),
            MetricPair('Pace', paceLabel(activity.paceSecondsPerKm)),
            if (activity.averageHeartRate != null)
              MetricPair(
                'Average heart rate',
                '${activity.averageHeartRate!.round()} bpm',
              ),
            if (activity.maximumHeartRate != null)
              MetricPair(
                'Maximum heart rate',
                '${activity.maximumHeartRate!.round()} bpm',
              ),
            if (activity.caloriesKcal != null)
              MetricPair('Calories', '${activity.caloriesKcal!.round()} kcal'),
            if (activity.elevationGainM != null)
              MetricPair(
                'Elevation gain',
                '${activity.elevationGainM!.round()} m',
              ),
            MetricPair('Source', activity.provider),
            MetricPair('Sync status', activity.syncStatus),
            if (activity.deviceInfo.isNotEmpty)
              MetricPair('Device', activity.deviceInfo.values.join(' · ')),
            for (final lap in activity.laps)
              MetricPair(
                'Lap ${lap.index}',
                '${distanceLabel(lap.distanceM)} · ${durationLabel(lap.durationS)}',
              ),
            const SizedBox(height: 10),
            const Text(
              'Unavailable measurements are never estimated. Pace uses active time and recorded distance.',
            ),
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
}
