import 'package:flutter/material.dart';

extension PremiumTypography on TextTheme {
  TextStyle get serifTitle {
    return (headlineSmall ?? const TextStyle()).copyWith(
      fontFamily: 'Georgia',
      fontFamilyFallback: const ['Times New Roman', 'serif'],
      fontWeight: FontWeight.w700,
      letterSpacing: 0,
      height: 1.05,
    );
  }

  TextStyle get serifSectionTitle {
    return (titleLarge ?? const TextStyle()).copyWith(
      fontFamily: 'Georgia',
      fontFamilyFallback: const ['Times New Roman', 'serif'],
      fontWeight: FontWeight.w700,
      letterSpacing: 0,
      height: 1.08,
    );
  }
}
