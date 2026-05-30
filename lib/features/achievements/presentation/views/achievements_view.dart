import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:run_track_app/features/achievements/presentation/view_models/achievements_view_model.dart';
import 'package:run_track_app/core/widgets/layout_gaps.dart';
import 'package:run_track_app/core/widgets/premium_card.dart';
import 'package:run_track_app/core/widgets/entry_animation.dart';
import 'package:run_track_app/core/widgets/athlete_avatar.dart';
import 'package:run_track_app/core/extensions/extensions.dart';
import 'package:run_track_app/core/theme/club_theme_config.dart';
import 'package:run_track_app/core/theme/premium_typography.dart';

class AchievementsView extends StatelessWidget {
  const AchievementsView({required this.viewModel, super.key});

  final AchievementsViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) {
        if (viewModel.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (viewModel.state == null) {
          return const Center(child: Text("No achievements found."));
        }

        return _AchievementsLayout(state: viewModel.state!);
      },
    );
  }
}

class _AchievementsLayout extends StatelessWidget {
  const _AchievementsLayout({required this.state});

  final AchievementsState state;

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
              delay: 75,
              child: _LeaderboardsSection(leaderboards: state.leaderboards),
            ),
            const VerticalGap(),
            EntryAnimation(
              delay: 150,
              child: _RaceResultsCard(results: state.raceResults),
            ),
            const VerticalGap(),
            EntryAnimation(
              delay: 300,
              child: _ChallengeFlagsCard(flags: state.challengeFlags),
            ),
            const VerticalGap(),
            EntryAnimation(
              delay: 450,
              child: _MapBingoCard(
                tiles: state.mapTiles,
                config: state.bingoConfig,
                polylines: state.recentPolylines,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RaceResultsCard extends StatelessWidget {
  const _RaceResultsCard({required this.results});

  final List<RaceResultItem> results;

  @override
  Widget build(BuildContext context) {
    return PremiumCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Verified race results',
            style: Theme.of(context).textTheme.serifSectionTitle,
          ),
          const VerticalGap(),
          for (final result in results) ...[
            _RaceResultRow(result: result),
            if (result != results.last) const _SoftDivider(),
          ],
        ],
      ),
    );
  }
}

class _RaceResultRow extends StatelessWidget {
  const _RaceResultRow({required this.result});

  final RaceResultItem result;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(result.event, overflow: TextOverflow.ellipsis),
              Text(
                result.result,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const HorizontalGap(),
        Flexible(
          child: Text(
            result.time,
            textAlign: TextAlign.right,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      ],
    );
  }
}

class _ChallengeFlagsCard extends StatelessWidget {
  const _ChallengeFlagsCard({required this.flags});

  final List<ChallengeFlag> flags;

  @override
  Widget build(BuildContext context) {
    return PremiumCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Fair-play engine',
            style: Theme.of(context).textTheme.serifSectionTitle,
          ),
          const VerticalGap(),
          for (final flag in flags) ...[
            _FlagRow(flag: flag),
            if (flag != flags.last) const _SoftDivider(),
          ],
        ],
      ),
    );
  }
}

class _FlagRow extends StatelessWidget {
  const _FlagRow({required this.flag});

  final ChallengeFlag flag;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(child: Text(flag.label)),
        const HorizontalGap(),
        Flexible(
          child: Text(
            flag.value,
            textAlign: TextAlign.right,
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
      ],
    );
  }
}

class _MapBingoCard extends StatelessWidget {
  const _MapBingoCard({
    required this.tiles,
    required this.config,
    required this.polylines,
  });

  final List<MapBingoTileState> tiles;
  final MapBingoConfig config;
  final List<String> polylines;

  @override
  Widget build(BuildContext context) {
    final spacingTokens = context.spacingTokens;
    final tokens = ClubThemeTokens.of(context);

    return PremiumCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Map bingo',
            style: Theme.of(context).textTheme.serifSectionTitle,
          ),
          Text(
            'Explore the local grid to unlock rewards',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const VerticalGap(),
          ClipRRect(
            borderRadius: BorderRadius.circular(tokens.borderRadius),
            child: AspectRatio(
              aspectRatio: 1,
              child: Stack(
                children: [
                  // Background Map: Fetched via Static API using the config coordinates.
                  // This mimics the admin-configured area and costs 0 database egress.
                  Positioned.fill(
                    child: Opacity(
                      opacity: 0.6,
                      child: Image.network(
                        'https://static-maps.yandex.ru/1.x/?ll=${config.centerLng},${config.centerLat}&z=${config.zoom.toInt()}&size=450,450&l=map&lang=en_US',
                        fit: BoxFit.cover,
                        errorBuilder: (context, _, _) =>
                            _TechnicalMapBackground(config: config),
                      ),
                    ),
                  ),
                  // The Bingo Grid: Semi-transparent to reveal the map underneath
                  GridView.count(
                    crossAxisCount: config.gridSize,
                    crossAxisSpacing: spacingTokens.gap,
                    mainAxisSpacing: spacingTokens.gap,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [for (final tile in tiles) _MapTile(tile: tile)],
                  ),
                  // The Actual GPS Paths: Drawn ON TOP of the grid with a glow
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _GPSPathPainter(
                        polylines: polylines,
                        config: config,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Standard Polyline Decoder + Mercator Projection Painter
class _GPSPathPainter extends CustomPainter {
  final List<String> polylines;
  final MapBingoConfig config;
  final Color color;

  _GPSPathPainter({
    required this.polylines,
    required this.config,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // High-visibility neon glow
    final shadowPaint = Paint()
      ..color = color.withValues(alpha: 0.5)
      ..strokeWidth = 6.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

    final paint = Paint()
      ..color = color.withValues(alpha: 1.0)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    for (final poly in polylines) {
      final points = _decodePolyline(poly);
      if (points.isEmpty) {
        debugPrint('--- BINGO GPS ERROR: Decoded polyline is empty ---');
        continue;
      }

      debugPrint('--- BINGO GPS DEBUG ---');
      debugPrint(
        'Polyline: ${poly.substring(0, math.min(8, poly.length))}... Points: ${points.length}',
      );

      final path = Path();
      for (int i = 0; i < points.length; i++) {
        final offset = _project(points[i], size);
        // Points are in Lng/Lat order in the Point object: x=lat, y=lng
        final isOffScreen =
            offset.dx < 0 ||
            offset.dx > size.width ||
            offset.dy < 0 ||
            offset.dy > size.height;

        debugPrint(
          '  Pt $i: [Lat: ${points[i].x.toStringAsFixed(4)}, Lng: ${points[i].y.toStringAsFixed(4)}] '
          '-> Screen: (${offset.dx.toStringAsFixed(1)}, ${offset.dy.toStringAsFixed(1)})'
          '${isOffScreen ? " [OFF-SCREEN]" : ""}',
        );
        if (i == 0) {
          path.moveTo(offset.dx, offset.dy);
        } else {
          path.lineTo(offset.dx, offset.dy);
        }
      }
      canvas.drawPath(path, shadowPaint);
      canvas.drawPath(path, paint);
    }
  }

  Offset _project(math.Point<double> point, Size size) {
    // Map scaling math for the 450x450 static image
    // Zoom level 14 centered on Quayside
    final double worldSize = 256.0 * math.pow(2, config.zoom);

    // Calculate the ratio between actual widget size and the requested map image size (450px)
    // This ensures lines scale correctly with the background image.
    final double scaleX = size.width / 450.0;
    final double scaleY = size.height / 450.0;

    double x(double lng) => (lng + 180.0) / 360.0 * worldSize;
    double y(double lat) {
      final double sinLat = math.sin(lat * math.pi / 180.0);
      return (0.5 -
              math.log((1.0 + sinLat) / (1.0 - sinLat)) / (4.0 * math.pi)) *
          worldSize;
    }

    final double mapCenterX = x(config.centerLng);
    final double mapCenterY = y(config.centerLat);

    // Lat is X, Lng is Y in our math.Point
    return Offset(
      size.width / 2 + (x(point.y) - mapCenterX) * scaleX,
      size.height / 2 + (y(point.x) - mapCenterY) * scaleY,
    );
  }

  /// Decodes an encoded polyline string into a list of Lat/Lng points.
  List<math.Point<double>> _decodePolyline(String encoded) {
    List<math.Point<double>> points = [];
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

      // Standard Polyline ZigZag decoding
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat = (lat + dlat).toSigned(32);

      shift = 0;
      result = 0;
      do {
        if (index >= len) return points;
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);

      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng = (lng + dlng).toSigned(32);

      // We use double explicitly to prevent integer wrap-around issues
      points.add(math.Point(lat.toDouble() / 1e5, lng.toDouble() / 1e5));
    }
    return points;
  }

  @override
  bool shouldRepaint(covariant _GPSPathPainter oldDelegate) => true;
}

/// Mimics a map background using lines and technical shapes
/// This provides the "look" of a map without any network usage.
class _TechnicalMapBackground extends StatelessWidget {
  const _TechnicalMapBackground({required this.config});
  final MapBingoConfig config;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return CustomPaint(
      painter: _MapGeometryPainter(color: color),
      size: Size.infinite,
    );
  }
}

class _MapGeometryPainter extends CustomPainter {
  _MapGeometryPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    // Draw some mock "Roads" and "Rivers"
    final path = Path()
      ..moveTo(0, size.height * 0.3)
      ..quadraticBezierTo(
        size.width * 0.5,
        size.height * 0.4,
        size.width,
        size.height * 0.2,
      )
      ..moveTo(size.width * 0.2, 0)
      ..lineTo(size.width * 0.8, size.height)
      ..moveTo(0, size.height * 0.8)
      ..lineTo(size.width, size.height * 0.7);

    canvas.drawPath(path, paint);

    // Draw some topography-style circles
    canvas.drawCircle(Offset(size.width * 0.7, size.height * 0.6), 40, paint);
    canvas.drawCircle(Offset(size.width * 0.7, size.height * 0.6), 25, paint);

    // Grid dots
    final dotPaint = Paint()..color = color.withValues(alpha: 0.3);
    for (double i = 0; i < size.width; i += 20) {
      for (double j = 0; j < size.height; j += 20) {
        canvas.drawCircle(Offset(i, j), 0.5, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MapGeometryPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _MapTile extends StatelessWidget {
  const _MapTile({required this.tile});

  final MapBingoTileState tile;

  @override
  Widget build(BuildContext context) {
    final tokens = ClubThemeTokens.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        // Semi-transparent "Glass" effect allows the map background to show through
        color: tile.visited
            ? colorScheme.primary.withValues(alpha: 0.6)
            : colorScheme.surface.withValues(alpha: 0.08),
        border: Border.all(
          color: tile.visited
              ? colorScheme.primary
              : tokens.strokeColor.withValues(alpha: 0.3),
          width: 0.5,
        ),
        borderRadius: BorderRadius.circular(4),
        boxShadow: tile.visited
            ? [
                BoxShadow(
                  color: colorScheme.primary.withValues(alpha: 0.2),
                  blurRadius: 8,
                  spreadRadius: -2,
                ),
              ]
            : null,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    tile.label,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: tile.visited
                          ? colorScheme.onPrimary
                          : colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (tile.visited)
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [Icon(Icons.check, color: colorScheme.onPrimary)],
              ),
            ),
        ],
      ),
    );
  }
}

class _LeaderboardsSection extends StatelessWidget {
  const _LeaderboardsSection({required this.leaderboards});
  final List<LeaderboardPillState> leaderboards;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Club leaderboards',
          style: Theme.of(context).textTheme.serifSectionTitle,
        ),
        const VerticalGap(),
        SizedBox(
          height: 110,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: leaderboards.length,
            separatorBuilder: (context, _) => const HorizontalGap(),
            itemBuilder: (context, index) =>
                _LeaderboardPill(state: leaderboards[index]),
          ),
        ),
      ],
    );
  }
}

class _LeaderboardPill extends StatelessWidget {
  const _LeaderboardPill({required this.state});
  final LeaderboardPillState state;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _showLeaderboardDetail(context, state),
      borderRadius: BorderRadius.circular(
        ClubThemeTokens.of(context).borderRadius,
      ),
      child: PremiumCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.max,
        child: Expanded(
          child: SizedBox(
            width: 145,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      _getIcon(state.iconName),
                      size: 14,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        state.title.toUpperCase(),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      '#${state.userRank}',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        '${state.userValue}${state.unit}',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showLeaderboardDetail(
    BuildContext context,
    LeaderboardPillState leaderboard,
  ) {
    final theme = Theme.of(context);
    final tokens = ClubThemeTokens.of(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(tokens.borderRadius),
        ),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: tokens.strokeColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    leaderboard.title,
                    style: theme.textTheme.serifSectionTitle,
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                controller: scrollController,
                padding: const EdgeInsets.all(16),
                itemCount: leaderboard.allEntries.length,
                separatorBuilder: (context, _) => const _SoftDivider(),
                itemBuilder: (context, index) {
                  final entry = leaderboard.allEntries[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 32,
                          child: Text(
                            '#${entry.rank}',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: entry.isCurrentUser
                                  ? theme.colorScheme.primary
                                  : null,
                            ),
                          ),
                        ),
                        AthleteAvatar(
                          initials: entry.name.initials(),
                          imageUrl: entry.imageUrl,
                          size: 32,
                        ),
                        const HorizontalGap(),
                        Expanded(
                          child: Text(
                            entry.name,
                            style: theme.textTheme.bodyLarge,
                          ),
                        ),
                        Text(
                          '${entry.value}${leaderboard.unit}',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getIcon(String name) {
    switch (name) {
      case 'verified_user':
        return Icons.verified_user;
      case 'timer':
        return Icons.timer;
      case 'bed':
        return Icons.bed;
      case 'terrain':
        return Icons.terrain;
      case 'wb_sunny':
        return Icons.wb_sunny;
      case 'groups':
        return Icons.groups;
      case 'bolt':
        return Icons.bolt;
      case 'whatshot':
        return Icons.whatshot;
      case 'map':
        return Icons.map;
      default:
        return Icons.emoji_events;
    }
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
