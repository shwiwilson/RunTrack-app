import 'package:flutter/material.dart';
import 'package:run_track_app/core/theme/club_theme_config.dart';

class PremiumCard extends StatelessWidget {
  const PremiumCard({
    super.key,
    this.child,
    this.children,
    this.padding,
    this.crossAxisAlignment = CrossAxisAlignment.stretch,
    this.mainAxisSize = MainAxisSize.min,
  }) : assert((child == null) != (children == null));

  final Widget? child;
  final List<Widget>? children;
  final EdgeInsetsGeometry? padding;
  final CrossAxisAlignment crossAxisAlignment;
  final MainAxisSize mainAxisSize;

  @override
  Widget build(BuildContext context) {
    final tokens = ClubThemeTokens.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: padding ?? EdgeInsets.all(tokens.edgePadding),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF121212) : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(tokens.borderRadius),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : tokens.strokeColor.withValues(alpha: 0.1),
          width: 0.5,
        ),
        boxShadow: isDark
            ? null
            : [
                // Sharp outer edge
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 1,
                  offset: const Offset(0, 1),
                ),
                // Soft spread
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Column(
        mainAxisSize: mainAxisSize,
        crossAxisAlignment: crossAxisAlignment,
        children: child == null ? children! : [child!],
      ),
    );
  }
}
