import 'package:flutter/material.dart';
import 'package:run_track_app/core/extensions/extensions.dart';
import 'package:run_track_app/core/theme/premium_typography.dart';
import 'package:run_track_app/core/widgets/athlete_avatar.dart';
import 'package:run_track_app/core/widgets/premium_card.dart';
import 'package:run_track_app/domain/run_track_snapshot.dart';
import 'package:run_track_app/features/profile/domain/models/you_models.dart';
import 'package:run_track_app/features/shared/feature_widgets.dart';

class YouTabScreen extends StatelessWidget {
  const YouTabScreen({
    required this.data,
    required this.onConnectHealth,
    required this.onAccount,
    super.key,
  });
  final RunTrackSnapshot data;
  final VoidCallback onConnectHealth;
  final VoidCallback onAccount;
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final summary = TrainingSummary.calculate(data.activities, now);
    final recent =
        data.activities
            .where((a) => a.isRunning && !a.endedAt.isAfter(now))
            .toList()
          ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return FeaturePage(
      children: [
        Row(
          children: [
            AthleteAvatar(
              initials: data.profile.displayName.initials(),
              size: 48,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: FeatureTitle(
                data.profile.displayName.isEmpty
                    ? 'Your running space'
                    : 'Hello, ${data.profile.displayName.split(' ').first}',
                subtitle:
                    data.membership?.clubName ??
                    'Your next chapter starts here.',
              ),
            ),
            IconButton(
              tooltip: 'Account settings',
              onPressed: onAccount,
              icon: const Icon(Icons.manage_accounts_outlined),
            ),
          ],
        ),
        if (summary.totalRuns == 0)
          EmptyFeature(
            icon: Icons.directions_run,
            title: 'No runs recorded yet',
            message:
                'Connect your running data to see your training history. Your first real run will start your story here.',
            actionLabel: 'Connect your running data',
            onAction: onConnectHealth,
          ),
        if (summary.totalRuns > 0)
          PremiumCard(
            children: [
              Text(
                'Your training',
                style: Theme.of(context).textTheme.serifSectionTitle,
              ),
              const SizedBox(height: 12),
              MetricPair('This week', distanceLabel(summary.weekDistanceM)),
              MetricPair(
                'Last week',
                distanceLabel(summary.previousWeekDistanceM),
              ),
              MetricPair('This month', distanceLabel(summary.monthDistanceM)),
              MetricPair('Recorded runs', '${summary.totalRuns}'),
              MetricPair(
                'Active weeks in the last four',
                '${summary.activeWeeks} / 4',
              ),
              const SizedBox(height: 12),
              const Text(
                'Calendar weeks start on Monday. Dates use your device timezone. Totals include only known distances.',
              ),
            ],
          ),
        PremiumCard(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Running data',
                    style: Theme.of(context).textTheme.serifSectionTitle,
                  ),
                ),
                IconButton(
                  tooltip: 'Manage running data',
                  onPressed: onConnectHealth,
                  icon: const Icon(Icons.settings_outlined),
                ),
              ],
            ),
            if (data.connections.isEmpty) ...[
              const Text('No activity provider connected.'),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: onConnectHealth,
                child: const Text('Connect your running data'),
              ),
            ],
            for (final connection in data.connections) ...[
              MetricPair(
                connection.provider.replaceAll('_', ' '),
                switch (connection.status) {
                  'connected' => 'Connected',
                  'setup_required' => 'Setup required',
                  'revoked' => 'Permission revoked',
                  'error' => 'Connection needs attention',
                  _ => 'Disconnected',
                },
              ),
              Text(
                connection.lastSuccessfulSyncAt == null
                    ? 'No successful sync yet.'
                    : 'Last successful sync: ${dateTimeLabel(connection.lastSuccessfulSyncAt!)}',
              ),
            ],
          ],
        ),
        if (summary.personalBests.isNotEmpty)
          PremiumCard(
            children: [
              Text(
                'Personal best workouts',
                style: Theme.of(context).textTheme.serifSectionTitle,
              ),
              const SizedBox(height: 10),
              for (final best in summary.personalBests)
                MetricPair(
                  distanceLabel(best.distanceM),
                  durationLabel(best.activity.elapsedDurationS),
                ),
              const SizedBox(height: 10),
              const Text(
                'Fastest whole workouts within 1% above each distance, using elapsed time. These are workout benchmarks, not verified race results.',
              ),
            ],
          ),
        if (recent.isNotEmpty)
          PremiumCard(
            children: [
              Text(
                'Recent runs',
                style: Theme.of(context).textTheme.serifSectionTitle,
              ),
              const SizedBox(height: 8),
              for (final run in recent.take(3)) ...[
                MetricPair(
                  dateLabel(run.startedAt),
                  distanceLabel(run.distanceM),
                ),
                Text(
                  '${durationLabel(run.activeDurationS)} active · ${paceLabel(run.paceSecondsPerKm)}',
                ),
                const SizedBox(height: 12),
              ],
            ],
          ),
      ],
    );
  }
}
