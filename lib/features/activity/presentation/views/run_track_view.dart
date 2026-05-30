import 'dart:math';
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:run_track_app/features/activity/presentation/view_models/run_track_view_model.dart';
import 'package:run_track_app/data/repositories/time_range_toggle.dart';
import 'package:run_track_app/core/widgets/layout_gaps.dart';
import 'package:run_track_app/core/widgets/premium_card.dart';
import 'package:run_track_app/core/widgets/entry_animation.dart';
import 'package:run_track_app/core/widgets/athlete_avatar.dart';
import 'package:run_track_app/core/theme/club_theme_config.dart';
import 'package:run_track_app/core/theme/premium_typography.dart';

class RunTrackView extends StatelessWidget {
  const RunTrackView({
    required this.viewModel,
    required this.dailyMessage,
    super.key,
  });

  final RunTrackViewModel viewModel;
  final String dailyMessage;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) {
        if (viewModel.isLoading) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }
        if (viewModel.state == null) {
          return const Center(child: Text("No activities found."));
        }

        return _RunTrackLayout(
          state: viewModel.state!,
          viewModel: viewModel,
          dailyMessage: dailyMessage,
        );
      },
    );
  }
}

class _RunTrackLayout extends StatelessWidget {
  const _RunTrackLayout({
    required this.state,
    required this.viewModel,
    required this.dailyMessage,
  });

  final RunTrackFeedState state;
  final RunTrackViewModel viewModel;
  final String dailyMessage;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: ListView.builder(
        // cacheExtent pre-builds items off-screen.
        // 2000 pixels is enough for ~15 cards on most screens.
        scrollCacheExtent: ScrollCacheExtent.pixels(2000),
        physics: const BouncingScrollPhysics(
          decelerationRate: ScrollDecelerationRate.fast,
        ),
        padding: context.spacingTokens.pageInsets,
        itemCount: state.activities.isEmpty ? 4 : state.activities.length + 3,
        itemBuilder: (context, index) {
          if (index == 0) {
            return EntryAnimation(
              delay: 0,
              child: _SyncPanel(summary: state.syncSummary),
            );
          }
          if (index == 1) return const VerticalGap();
          if (index == 2) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: TimeRangeToggle(
                selected: viewModel.selectedRange,
                onSelectionChanged: viewModel.updateTimeRange,
              ),
            );
          }

          if (state.activities.isEmpty) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: EntryAnimation(
                delay: 250,
                child: PremiumCard(
                  child: Text(
                    dailyMessage,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontStyle: FontStyle.italic,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            );
          }

          final activityIndex = index - 3;
          return Padding(
            padding: const EdgeInsets.only(bottom: 16.0),
            child: EntryAnimation(
              delay: activityIndex < 5 ? (activityIndex * 100) : 0,
              child: _ActivityCard(activity: state.activities[activityIndex]),
            ),
          );
        },
      ),
    );
  }
}

class _SyncPanel extends StatelessWidget {
  const _SyncPanel({required this.summary});

  final String summary;

  @override
  Widget build(BuildContext context) {
    return PremiumCard(
      child: Row(
        children: [
          Icon(Icons.sync, color: Theme.of(context).colorScheme.primary),
          const HorizontalGap(),
          Expanded(
            child: Text(summary, style: Theme.of(context).textTheme.bodyLarge),
          ),
        ],
      ),
    );
  }
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.activity});

  final ActivityFeedItem activity;

  @override
  Widget build(BuildContext context) {
    final tokens = ClubThemeTokens.of(context);

    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Timeline aesthetic
            Column(
              children: [
                AthleteAvatar(
                  initials: activity.athleteInitials,
                  imageUrl: activity.athleteImageUrl,
                ),
                const VerticalGap(),
                // Dashed timeline line
                Column(
                  children: List.generate(
                    12,
                    (index) => Container(
                      width: 1,
                      height: 8,
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      color: tokens.subtleStrokeColor,
                    ),
                  ),
                ),
              ],
            ),
            const HorizontalGap(),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              activity.title,
                              style: Theme.of(
                                context,
                              ).textTheme.serifSectionTitle,
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                            Text(
                              '${activity.athleteName} • ${activity.subtitle}',
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      _SourcePill(label: activity.source),
                    ],
                  ),
                  SizedBox(height: context.spacingTokens.page),
                  // The "Wow" Factor: Bento Layout for Activity Stats
                  Row(
                    children: [
                      // Route Shape Preview (Technical Abstraction)
                      _ActivityRoutePreview(
                        polyline: activity.polyline,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const HorizontalGap(),
                      // Stats Grid
                      Expanded(
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: _StatBlock(
                                    label: 'DIST',
                                    value: activity.distance,
                                  ),
                                ),
                                const HorizontalGap(),
                                Expanded(
                                  child: _StatBlock(
                                    label: 'PACE',
                                    value: activity.pace,
                                  ),
                                ),
                              ],
                            ),
                            const VerticalGap(),
                            Row(
                              children: [
                                Expanded(
                                  child: _StatBlock(
                                    label: 'HR',
                                    value: activity.heartRate,
                                  ),
                                ),
                                const HorizontalGap(),
                                Expanded(
                                  child: activity.verifiedClubRun
                                      ? const _VerifiedBadge()
                                      : _StatBlock(
                                          label: 'CLUSTER',
                                          value: activity.clusterLabel,
                                        ),
                                ),
                              ],
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
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _ActivityRoutePreview extends StatelessWidget {
  const _ActivityRoutePreview({this.polyline, required this.color});
  final String? polyline;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.5),
        border: Border.all(
          color: ClubThemeTokens.of(context).subtleStrokeColor,
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: CustomPaint(
        painter: _MiniPathPainter(polyline: polyline ?? '', color: color),
      ),
    );
  }
}

/// Draws a small, stylized, and unique version of the run path for the activity card
class _MiniPathPainter extends CustomPainter {
  _MiniPathPainter({required this.polyline, required this.color});
  final String polyline;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Add a technical grid dots
    final dotPaint = Paint()..color = color.withValues(alpha: 0.1);
    for (double i = 0; i < size.width; i += 10) {
      for (double j = 0; j < size.height; j += 10) {
        canvas.drawCircle(Offset(i, j), 0.5, dotPaint);
      }
    }

    if (polyline.isEmpty) return;

    final points = _decodePolyline(polyline);
    if (points.isEmpty) return;

    // Find bounding box to scale the path into the 80x80 box
    double minX = double.infinity, maxX = double.negativeInfinity;
    double minY = double.infinity, maxY = double.negativeInfinity;

    for (final p in points) {
      if (p.x < minX) minX = p.x;
      if (p.x > maxX) maxX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.y > maxY) maxY = p.y;
    }

    final rangeX = maxX - minX;
    final rangeY = maxY - minY;
    final maxRange = max(rangeX, rangeY);

    // Prevent division by zero for point-like activities
    if (maxRange == 0) return;

    final scale = (size.width - 24) / maxRange;
    final offsetX = (size.width - rangeX * scale) / 2;
    final offsetY = (size.height - rangeY * scale) / 2;

    final paint = Paint()
      ..color = color.withValues(alpha: 0.9)
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();
    for (int i = 0; i < points.length; i++) {
      // Note: Lat is X, Lng is Y in our math.Point
      final px = offsetX + (points[i].y - minY) * scale;
      final py = offsetY + (maxY - points[i].x) * scale;

      if (i == 0) {
        path.moveTo(px, py);
      } else {
        path.lineTo(px, py);
      }
    }

    canvas.drawPath(path, paint);
  }

  List<Point<double>> _decodePolyline(String encoded) {
    List<Point<double>> points = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        if (index >= len) return points;
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat = (lat + dlat).toSigned(32);

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng = (lng + dlng).toSigned(32);

      points.add(Point(lat.toDouble() / 1e5, lng.toDouble() / 1e5));
    }
    return points;
  }

  @override
  bool shouldRepaint(covariant _MiniPathPainter oldDelegate) {
    return oldDelegate.polyline != polyline || oldDelegate.color != color;
  }
}

class _SourcePill extends StatelessWidget {
  const _SourcePill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.primary, // Use brand color for impact
        borderRadius: BorderRadius.circular(4), // Technical radius
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.onPrimary,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              label.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colorScheme.onPrimary,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatBlock extends StatelessWidget {
  const _StatBlock({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 9,
            letterSpacing: 1.1,
          ),
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w900,
            height: 1.2,
          ),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
      ],
    );
  }
}

class _VerifiedBadge extends StatelessWidget {
  const _VerifiedBadge();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.1),
        border: Border.all(color: colorScheme.primary, width: 1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Text(
          'VERIFIED',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: colorScheme.primary,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.0,
          ),
        ),
      ),
    );
  }
}
