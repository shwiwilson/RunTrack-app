import 'package:flutter/material.dart';
import 'package:run_track_app/features/profile/domain/models/you_models.dart';

extension BiometricMetricUI on BiometricMetric {
  Color getStatusColor(Color baseThemeColor) {
    final hsv = HSVColor.fromColor(baseThemeColor);
    // Logic: 0.0 (Red) to 120.0 (Green) based on progress
    final hue = (progress * 120.0).clamp(0.0, 120.0);
    return HSVColor.fromAHSV(1.0, hue, hsv.saturation, hsv.value).toColor();
  }
}
