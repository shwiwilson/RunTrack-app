import 'package:flutter/material.dart';

@immutable
class YouTabState {
  const YouTabState({
    required this.athleteInitials,
    this.athleteImageUrl,
    required this.athleteName,
    required this.readinessScore,
    required this.readinessLabel,
    required this.coachInsight,
    required this.efficiencyLabel,
    required this.efficiencyValue,
    required this.efficiencyTrend,
    required this.metrics,
    required this.benchmarks,
  });

  final String athleteInitials;
  final String? athleteImageUrl;
  final String athleteName;
  final String readinessScore;
  final String readinessLabel;
  final String coachInsight;
  final String efficiencyLabel;
  final String efficiencyValue;
  final String efficiencyTrend;
  final List<BiometricMetric> metrics;
  final List<BenchmarkMetric> benchmarks;
}

@immutable
class BiometricMetric {
  const BiometricMetric({
    required this.label,
    required this.value,
    required this.trend,
    required this.status,
  });

  final String label;
  final String value;
  final String trend;
  final String status;

  factory BiometricMetric.fromJson(Map<String, dynamic> json) {
    return BiometricMetric(
      label: json['label'] as String,
      value: json['value'] as String,
      trend: json['trend'] as String,
      status: json['status'] as String,
    );
  }

  double get progress {
    final lowerLabel = label.toLowerCase();
    double numericValue = 0.0;

    if (value.contains('h')) {
      final parts = value.split('h');
      final hours = double.tryParse(parts[0].trim()) ?? 0.0;
      double minutes = 0.0;
      if (parts.length > 1 && parts[1].trim().isNotEmpty) {
        minutes = double.tryParse(parts[1].trim()) ?? 0.0;
      }
      numericValue = hours + (minutes / 60.0);
    } else {
      numericValue = double.tryParse(value.split(' ')[0]) ?? 0.0;
    }

    double calculatedProgress;

    if (lowerLabel.contains('hrv')) {
      calculatedProgress = (numericValue - 20) / 80;
    } else if (lowerLabel.contains('sleep')) {
      calculatedProgress = (numericValue - 4.0) / 4.0;
    } else if (lowerLabel.contains('rhr') ||
        lowerLabel.contains('heart rate') ||
        lowerLabel.contains('recovery')) {
      calculatedProgress = (100 - numericValue) / 60;
    } else if (lowerLabel.contains('load')) {
      calculatedProgress = numericValue / 1000;
    } else {
      calculatedProgress = (numericValue / 100);
    }

    return calculatedProgress.clamp(0.1, 1.0);
  }

  bool get isElite => progress >= 0.85;
  bool get isGood => progress >= 0.6;
  bool get isAverage => progress >= 0.4;
}

@immutable
class BenchmarkMetric {
  const BenchmarkMetric({required this.label, required this.value});

  final String label;
  final String value;

  factory BenchmarkMetric.fromJson(Map<String, dynamic> json) {
    return BenchmarkMetric(
      label: json['label'] as String,
      value: json['value'] as String,
    );
  }
}
