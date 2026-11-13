import 'package:flutter/material.dart';
import 'package:run_track_app/core/theme/club_theme_config.dart';
import 'package:run_track_app/features/club_hub/domain/models/club_models.dart';

const genericClubPrimary = '#315A18';
const genericClubSecondary = '#57634D';
const genericClubBackground = '#F5F7F2';

final _hex = RegExp(r'^#[0-9a-fA-F]{6}$');

bool isBrandColour(String value) => _hex.hasMatch(value);

String clubColour(ClubMembership club, String key, String fallback) {
  final colours = club.theme['colors'];
  final value = colours is Map ? colours[key] : null;
  return value is String && isBrandColour(value) ? value : fallback;
}

String? clubInstallPath(ClubMembership? club) {
  final slug = club?.installSlug;
  if (slug == null ||
      slug.length > 80 ||
      !RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$').hasMatch(slug)) {
    return null;
  }
  return '/club/$slug/install';
}

ThemeData clubBrandTheme(ClubMembership club) {
  final primary = clubColour(club, 'primary', genericClubPrimary);
  final secondary = clubColour(club, 'secondary', genericClubSecondary);
  final background = clubColour(club, 'background', genericClubBackground);
  final backgroundColor = _parse(background);
  final dark = backgroundColor.computeLuminance() < 0.18;
  final onBackground = _foreground(background);
  final surface = dark ? '#161616' : '#FFFFFF';
  final onSurface = _foreground(surface);
  final primaryAccent = _contrast(_parse(primary), _parse(surface)) >= 4.5
      ? primary
      : onSurface;
  final container = dark ? '#292929' : '#E8EBE6';
  return ClubThemeConfig.fromJson({
    'name': club.clubName,
    'colors': {
      'primary': primary,
      'onPrimary': _foreground(primary),
      'secondary': secondary,
      'onSecondary': _foreground(secondary),
      'primaryContainer': container,
      'onPrimaryContainer': onSurface,
      'secondaryContainer': container,
      'onSecondaryContainer': onSurface,
      'tertiary': primaryAccent,
      'onTertiary': _foreground(primaryAccent),
      'tertiaryContainer': container,
      'onTertiaryContainer': onSurface,
      'background': background,
      'onBackground': onBackground,
      'surface': surface,
      'onSurface': onSurface,
      'surfaceVariant': container,
      'onSurfaceVariant': dark ? '#CECECE' : '#465042',
      'outline': dark ? '#9D9D9D' : '#737C70',
      'outlineVariant': dark ? '#414141' : '#D9DED7',
      'error': dark ? '#FFB4AB' : '#A62620',
      'onError': dark ? '#48130F' : '#FFFFFF',
    },
    'shape': {'borderRadius': 20.0},
    'spacing': {'edgePadding': 24.0},
    'buttons': {
      for (final type in ['text', 'outlined', 'icon'])
        type: {'foregroundColor': primaryAccent},
      for (final type in ['filled', 'elevated'])
        type: {
          'backgroundColor': primary,
          'foregroundColor': _foreground(primary),
          'disabledBackgroundColor': container,
          'disabledForegroundColor': dark ? '#999999' : '#656565',
        },
    },
  }).toThemeData();
}

Color _parse(String value) =>
    Color(int.parse('FF${value.substring(1)}', radix: 16));

double _contrast(Color first, Color second) {
  final a = first.computeLuminance();
  final b = second.computeLuminance();
  return a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05);
}

String _foreground(String background) =>
    _contrast(_parse(background), Colors.black) >= 4.5 ? '#000000' : '#FFFFFF';
