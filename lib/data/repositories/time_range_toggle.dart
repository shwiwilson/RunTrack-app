import 'package:flutter/material.dart';

enum TimeRange { today, week, month }

class TimeRangeToggle extends StatelessWidget {
  final TimeRange selected;
  final ValueChanged<TimeRange> onSelectionChanged;

  const TimeRangeToggle({
    super.key,
    required this.selected,
    required this.onSelectionChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<TimeRange>(
        segments: const [
          ButtonSegment<TimeRange>(
            value: TimeRange.today,
            label: Text('Today'),
            icon: Icon(Icons.today_outlined),
          ),
          ButtonSegment<TimeRange>(
            value: TimeRange.week,
            label: Text('Week'),
            icon: Icon(Icons.view_week_outlined),
          ),
          ButtonSegment<TimeRange>(
            value: TimeRange.month,
            label: Text('Month'),
            icon: Icon(Icons.calendar_month_outlined),
          ),
        ],
        selected: {selected},
        onSelectionChanged: (Set<TimeRange> newSelection) {
          onSelectionChanged(newSelection.first);
        },
        showSelectedIcon: false,
        style: SegmentedButton.styleFrom(
          // Ensures the toggle looks sharp and matches your club theme
          visualDensity: VisualDensity.comfortable,
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }
}
