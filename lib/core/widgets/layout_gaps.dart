import 'package:flutter/material.dart';
import 'package:run_track_app/core/theme/club_theme_config.dart';

@immutable
class SpacingTokens {
  const SpacingTokens({
    required this.page,
    required this.card,
    required this.gap,
    required this.tight,
  });

  final double page;
  final double card;
  final double gap;
  final double tight;

  EdgeInsets get pageInsets => EdgeInsets.all(page);
  EdgeInsets get cardInsets => EdgeInsets.all(card);
  EdgeInsets get tightInsets => EdgeInsets.all(tight);
}

extension SpacingTokensExtension on BuildContext {
  SpacingTokens get spacingTokens {
    final tokens = ClubThemeTokens.of(this);

    return SpacingTokens(
      page: tokens.edgePadding,
      card: tokens.edgePadding,
      gap: tokens.edgePadding / 2,
      tight: tokens.edgePadding / 3,
    );
  }
}

class VerticalGap extends StatelessWidget {
  const VerticalGap({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(height: context.spacingTokens.gap);
  }
}

class HorizontalGap extends StatelessWidget {
  const HorizontalGap({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(width: context.spacingTokens.gap);
  }
}
