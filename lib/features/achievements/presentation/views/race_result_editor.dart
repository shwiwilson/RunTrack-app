import 'package:flutter/material.dart';
import 'package:run_track_app/features/application/run_track_controller.dart';
import 'package:run_track_app/features/shared/feature_widgets.dart';

class RaceResultEditor extends StatefulWidget {
  const RaceResultEditor({required this.controller, super.key});
  final RunTrackController controller;
  @override
  State<RaceResultEditor> createState() => _RaceResultEditorState();
}

class _RaceResultEditorState extends State<RaceResultEditor> {
  final form = GlobalKey<FormState>();
  final event = TextEditingController();
  final distance = TextEditingController();
  final duration = TextEditingController();
  final evidence = TextEditingController();
  DateTime date = DateTime.now();
  bool saving = false;
  @override
  void dispose() {
    event.dispose();
    distance.dispose();
    duration.dispose();
    evidence.dispose();
    super.dispose();
  }

  double? get seconds {
    final parts = duration.text.trim().split(':');
    if (parts.length != 3) return null;
    final values = parts.map(int.tryParse).toList();
    if (values.any((v) => v == null || v < 0) ||
        values[1]! >= 60 ||
        values[2]! >= 60) {
      return null;
    }
    final total = (values[0]! * 3600 + values[1]! * 60 + values[2]!).toDouble();
    return total > 0 ? total : null;
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    setState(() => saving = true);
    final success = await widget.controller.mutate(
      () => widget.controller.repository.addRaceResult(
        eventName: event.text,
        eventDate: date,
        distanceM: double.parse(distance.text) * 1000,
        durationS: seconds!,
        evidenceUrl: evidence.text.trim().isEmpty ? null : evidence.text.trim(),
      ),
    );
    if (!mounted) return;
    if (success) {
      Navigator.pop(context);
    } else {
      setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add race result'),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'This result stays private and unverified. Adding an evidence link does not automatically verify it.',
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: event,
                maxLength: 160,
                decoration: const InputDecoration(labelText: 'Event name'),
                validator: (v) =>
                    v!.trim().isEmpty ? 'Enter the event name.' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: distance,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Distance in kilometres',
                ),
                validator: (v) {
                  final n = double.tryParse(v ?? '');
                  return n == null || !n.isFinite || n <= 0
                      ? 'Enter a positive distance.'
                      : null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: duration,
                decoration: const InputDecoration(
                  labelText: 'Finish time (hh:mm:ss)',
                  hintText: '00:25:30',
                ),
                validator: (_) =>
                    seconds == null ? 'Enter a time as hh:mm:ss.' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: evidence,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'Official result link (optional)',
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return null;
                  final uri = Uri.tryParse(v.trim());
                  return uri?.scheme == 'https' && uri!.host.isNotEmpty
                      ? null
                      : 'Use an https link.';
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Event date'),
                subtitle: Text(dateLabel(date)),
                trailing: const Icon(Icons.edit_calendar_outlined),
                onTap: saving
                    ? null
                    : () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: date,
                          firstDate: DateTime(1900),
                          lastDate: DateTime.now(),
                        );
                        if (picked != null && mounted) {
                          setState(() => date = picked);
                        }
                      },
              ),
              if (widget.controller.error != null)
                Text(widget.controller.error!),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: saving ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: saving ? null : save,
        child: Text(saving ? 'Saving…' : 'Save result'),
      ),
    ],
  );
}
