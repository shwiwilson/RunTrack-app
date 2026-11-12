import 'package:flutter/material.dart';
import 'package:run_track_app/core/widgets/premium_card.dart';
import 'package:run_track_app/core/theme/premium_typography.dart';

String distanceLabel(double? metres) =>
    metres == null ? 'Unavailable' : '${(metres / 1000).toStringAsFixed(2)} km';
String durationLabel(double? seconds) {
  if (seconds == null) return 'Unavailable';
  final total = seconds.round();
  final h = total ~/ 3600, m = (total % 3600) ~/ 60, s = total % 60;
  return h > 0
      ? '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}'
      : '$m:${s.toString().padLeft(2, '0')}';
}

String paceLabel(double? seconds) =>
    seconds == null ? 'Unavailable' : '${durationLabel(seconds)} /km';
String dateLabel(DateTime date) {
  final d = date.toLocal();
  return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

String dateTimeLabel(DateTime date) {
  final d = date.toLocal();
  return '${dateLabel(date)} · ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

class FeaturePage extends StatelessWidget {
  const FeaturePage({required this.children, super.key});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
    children: [
      for (final child in children)
        Padding(padding: const EdgeInsets.only(bottom: 20), child: child),
    ],
  );
}

class FeatureTitle extends StatelessWidget {
  const FeatureTitle(this.title, {this.subtitle, super.key});
  final String title;
  final String? subtitle;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: Theme.of(context).textTheme.serifTitle),
      if (subtitle != null) ...[
        const SizedBox(height: 8),
        Text(
          subtitle!,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ],
  );
}

class EmptyFeature extends StatelessWidget {
  const EmptyFeature({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    super.key,
  });
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => PremiumCard(
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Icon(
          icon,
          size: 44,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
      Text(
        title,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 10),
      Text(message, textAlign: TextAlign.center),
      if (onAction != null) ...[
        const SizedBox(height: 18),
        FilledButton(onPressed: onAction, child: Text(actionLabel!)),
      ],
    ],
  );
}

class MetricPair extends StatelessWidget {
  const MetricPair(this.label, this.value, {super.key});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
      ],
    ),
  );
}
