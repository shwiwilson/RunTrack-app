import 'package:flutter/material.dart';
import 'club_theme_config.dart';

/// Neutral product theme used before a runner has selected a real club.
ThemeData runTrackTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  return ClubThemeConfig.fromJson({
    'name': 'RunTrack',
    'colors': {
      'primary': dark ? '#B5ED75' : '#315A18',
      'onPrimary': dark ? '#153000' : '#FFFFFF',
      'primaryContainer': dark ? '#294719' : '#D6F4BB',
      'onPrimaryContainer': dark ? '#D6F4BB' : '#153000',
      'secondary': dark ? '#C1CBB6' : '#57634D',
      'background': dark ? '#10140F' : '#F5F7F2',
      'onBackground': dark ? '#EDF1E7' : '#20261C',
      'surface': dark ? '#191E17' : '#FFFFFF',
      'onSurface': dark ? '#EDF1E7' : '#20261C',
      'surfaceVariant': dark ? '#30382B' : '#E8EDE1',
      'onSurfaceVariant': dark ? '#BCC6B4' : '#526047',
      'outline': dark ? '#809075' : '#839176',
      'outlineVariant': dark ? '#394331' : '#DBE3D4',
      'error': dark ? '#FFB4AB' : '#A62620',
    },
    'shape': {'borderRadius': 20.0},
    'spacing': {'edgePadding': 24.0},
    'buttons': {
      for (final type in ['text', 'outlined', 'icon'])
        type: {'foregroundColor': dark ? '#B5ED75' : '#315A18'},
      'elevated': {
        'backgroundColor': dark ? '#294719' : '#D6F4BB',
        'foregroundColor': dark ? '#D6F4BB' : '#153000',
      },
      'filled': {
        'backgroundColor': dark ? '#B5ED75' : '#315A18',
        'foregroundColor': dark ? '#153000' : '#FFFFFF',
      },
    },
  }).toThemeData();
}
