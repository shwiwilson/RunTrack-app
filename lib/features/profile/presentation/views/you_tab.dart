import 'package:flutter/material.dart';
import 'package:run_track_app/features/profile/presentation/view_models/you_view_model.dart';
import 'package:run_track_app/core/widgets/layout_gaps.dart';
import 'package:run_track_app/core/widgets/premium_card.dart';
import 'package:run_track_app/core/widgets/entry_animation.dart';
import 'package:run_track_app/core/widgets/athlete_avatar.dart';
import 'package:run_track_app/core/theme/club_theme_config.dart';
import 'package:run_track_app/core/theme/premium_typography.dart';
import 'package:run_track_app/core/widgets/biometric_ring.dart';
import 'package:run_track_app/features/profile/domain/models/biometric_ui_extensions.dart';
import 'dart:math';

class YouTabScreen extends StatelessWidget {
  const YouTabScreen({
    required this.viewModel,
    required this.onLogout,
    super.key,
  });

  final YouViewModel viewModel;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) {
        if (viewModel.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (viewModel.state == null) {
          return const Center(child: Text("Initializing metrics..."));
        }

        return _YouTabLayout(state: viewModel.state!, onLogout: onLogout);
      },
    );
  }
}

class _YouTabLayout extends StatelessWidget {
  const _YouTabLayout({required this.state, required this.onLogout});

  final YouTabState state;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: context.spacingTokens.pageInsets,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            EntryAnimation(
              delay: 0,
              child: _GreetingCard(state: state, onLogout: onLogout),
            ),
            const VerticalGap(),
            EntryAnimation(delay: 100, child: _ReadinessHero(state: state)),
            const VerticalGap(),
            EntryAnimation(delay: 200, child: _EfficiencyCard(state: state)),
            const VerticalGap(),
            EntryAnimation(
              delay: 300,
              child: _BiometricMatrix(metrics: state.metrics),
            ),
            const VerticalGap(),
            EntryAnimation(
              delay: 500,
              child: _BenchmarkPanel(benchmarks: state.benchmarks),
            ),
          ],
        ),
      ),
    );
  }
}

class _GreetingCard extends StatelessWidget {
  const _GreetingCard({required this.state, required this.onLogout});
  final YouTabState state;
  final VoidCallback onLogout;

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    return PremiumCard(
      child: Row(
        children: [
          AthleteAvatar(
            initials: state.athleteInitials,
            imageUrl: state.athleteImageUrl,
            size: 32,
          ),
          const HorizontalGap(),
          Expanded(
            child: Text(
              '${_getGreeting()}, ${state.athleteName.split(' ').first}',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          IconButton(
            onPressed: onLogout,
            icon: const Icon(Icons.logout_rounded),
            iconSize: 20,
          ),
        ],
      ),
    );
  }
}

class _ReadinessHero extends StatelessWidget {
  const _ReadinessHero({required this.state});

  final YouTabState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return PremiumCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Morning readiness',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: colorScheme.primary,
                      ),
                    ),
                    const VerticalGap(),
                    Text(
                      state.readinessLabel,
                      style: Theme.of(context).textTheme.serifTitle,
                    ),
                  ],
                ),
              ),
              const HorizontalGap(),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        BiometricRing(
                          progress:
                              (double.tryParse(state.readinessScore) ?? 0) /
                              100,
                          color: colorScheme.primary,
                          strokeWidth: 8,
                          size: 90,
                          subtleStrokeColor: ClubThemeTokens.of(
                            context,
                          ).subtleStrokeColor,
                        ),
                        Text(
                          state.readinessScore,
                          style: theme.textTheme.displaySmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: -2,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const VerticalGap(),
          Divider(color: ClubThemeTokens.of(context).subtleStrokeColor),
          const VerticalGap(),
          Text(
            state.coachInsight,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ],
      ),
    );
  }
}

class _EfficiencyCard extends StatelessWidget {
  const _EfficiencyCard({required this.state});
  final YouTabState state;

  @override
  Widget build(BuildContext context) {
    return PremiumCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  state.efficiencyLabel,
                  style: Theme.of(context).textTheme.serifSectionTitle,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                const VerticalGap(),
                Text(state.efficiencyTrend),
              ],
            ),
          ),
          const HorizontalGap(),
          Flexible(
            child: Text(
              state.efficiencyValue,
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BiometricMatrix extends StatelessWidget {
  const _BiometricMatrix({required this.metrics});

  final List<BiometricMetric> metrics;

  @override
  Widget build(BuildContext context) {
    return PremiumCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionHeader('Biometric matrix'),
          const VerticalGap(),
          LayoutBuilder(
            builder: (context, constraints) {
              // Calculate dimensions based on available width
              final availableWidth = constraints.maxWidth;
              final chartSize = (availableWidth * 0.55).clamp(160.0, 260.0);

              // Increased step and stroke for a bolder look
              final ringStep = chartSize * 0.24;
              final strokeWidth = ringStep * 0.42;

              return Row(
                children: [
                  // Concentric Rings Stack
                  SizedBox(
                    width: chartSize,
                    height: chartSize,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        for (int i = 0; i < metrics.length; i++)
                          TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0.0, end: metrics[i].progress),
                            duration: Duration(milliseconds: 1200 + (i * 200)),
                            curve: Curves.easeOutQuart,
                            builder: (context, animatedProgress, _) {
                              return BiometricRing(
                                progress: animatedProgress,
                                color: metrics[i].getStatusColor(
                                  Theme.of(context).colorScheme.primary,
                                ),
                                size: chartSize - (i * ringStep),
                                strokeWidth: strokeWidth,
                                label: metrics[i].label.toUpperCase(),
                                labelAngleOffset: i * (pi / 2),
                                subtleStrokeColor: ClubThemeTokens.of(
                                  context,
                                ).subtleStrokeColor,
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                  const HorizontalGap(),
                  // Legend - Integrated directly with the ring colors
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (final metric in metrics)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2.0),
                            child: _MetricLegendItem(metric: metric),
                          ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _MetricLegendItem extends StatelessWidget {
  const _MetricLegendItem({required this.metric});

  final BiometricMetric metric;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = metric.getStatusColor(theme.colorScheme.primary);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: statusColor,
              borderRadius: BorderRadius.circular(2), // Square-ish LEDs
              boxShadow: [
                BoxShadow(
                  color: statusColor.withValues(alpha: 0.4),
                  blurRadius: 4,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          const HorizontalGap(),
          Expanded(
            child: Text(
              metric.label,
              style: theme.textTheme.labelMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                metric.value,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                metric.trend,
                style: theme.textTheme.labelSmall?.copyWith(color: statusColor),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BenchmarkPanel extends StatelessWidget {
  const _BenchmarkPanel({required this.benchmarks});

  final List<BenchmarkMetric> benchmarks;

  @override
  Widget build(BuildContext context) {
    return PremiumCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionHeader('90-day benchmark'),
          const VerticalGap(),
          for (final benchmark in benchmarks) ...[
            _BenchmarkRow(benchmark: benchmark),
            if (benchmark != benchmarks.last) const _SoftDivider(),
          ],
        ],
      ),
    );
  }
}

class _BenchmarkRow extends StatelessWidget {
  const _BenchmarkRow({required this.benchmark});

  final BenchmarkMetric benchmark;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(child: Text(benchmark.label, overflow: TextOverflow.ellipsis)),
        const HorizontalGap(),
        Flexible(
          child: Text(
            benchmark.value,
            textAlign: TextAlign.right,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(label, style: Theme.of(context).textTheme.serifSectionTitle);
  }
}

class _SoftDivider extends StatelessWidget {
  const _SoftDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: context.spacingTokens.gap),
      child: Divider(color: ClubThemeTokens.of(context).subtleStrokeColor),
    );
  }
}
