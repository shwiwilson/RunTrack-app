import 'package:flutter/material.dart';
import 'package:run_track_app/core/theme/club_theme_config.dart';

class AthleteAvatar extends StatelessWidget {
  const AthleteAvatar({
    required this.initials,
    this.imageUrl,
    this.size = 36,
    super.key,
  });

  final String initials;
  final String? imageUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = ClubThemeTokens.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colorScheme.onSurface.withValues(alpha: isDark ? 0.05 : 0.1),
        border: Border.all(
          color: colorScheme.onSurface.withValues(alpha: isDark ? 0.1 : 0.2),
          width: 0.5,
        ),
        borderRadius: BorderRadius.circular(tokens.borderRadius / 2),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              initials,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: size * 0.38,
              ),
            ),
          ),
          if (imageUrl != null)
            Image.network(
              imageUrl!,
              fit: BoxFit.cover,
              width: size,
              height: size,
              frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                if (wasSynchronouslyLoaded) return child;
                return AnimatedOpacity(
                  opacity: frame == null ? 0 : 1,
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeOut,
                  child: child,
                );
              },
              errorBuilder: (context, error, stackTrace) =>
                  const SizedBox.shrink(),
            ),
        ],
      ),
    );
  }
}
