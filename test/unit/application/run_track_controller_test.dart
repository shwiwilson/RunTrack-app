import 'package:flutter_test/flutter_test.dart';
import 'package:run_track_app/features/application/run_track_controller.dart';
import '../../helpers.dart';

void main() {
  test(
    'connection failure never becomes an empty successful dataset',
    () async {
      final repository = TestRepository()
        ..failure = Exception('network unavailable');
      final controller = RunTrackController(repository);
      await controller.refresh();
      expect(controller.snapshot, isNull);
      expect(controller.loading, isFalse);
      expect(controller.error, contains('Unable to load'));
      repository.failure = null;
      await controller.refresh();
      expect(controller.snapshot, isNotNull);
      expect(controller.snapshot!.activities, isEmpty);
      expect(controller.error, isNull);
      controller.dispose();
    },
  );
  test(
    'failed write reports failure and does not fake a refreshed success',
    () async {
      final repository = TestRepository();
      final controller = RunTrackController(repository);
      await controller.refresh();
      final saved = await controller.mutate(() async {
        throw Exception('denied');
      });
      expect(saved, isFalse);
      expect(controller.error, contains('could not be saved'));
      expect(repository.loads, 1);
      expect(controller.saving, isFalse);
      controller.dispose();
    },
  );
  test('successful write re-reads persisted source of truth', () async {
    final repository = TestRepository();
    final controller = RunTrackController(repository);
    await controller.refresh();
    var wrote = false;
    expect(
      await controller.mutate(() async {
        wrote = true;
      }),
      isTrue,
    );
    expect(wrote, isTrue);
    expect(repository.loads, 2);
    expect(controller.error, isNull);
    controller.dispose();
  });
  test(
    'confirmed write followed by reload failure does not invite a duplicate write',
    () async {
      final repository = TestRepository();
      final controller = RunTrackController(repository);
      await controller.refresh();
      final saved = await controller.mutate(() async {
        repository.failure = Exception('offline after write');
      });
      expect(saved, isTrue);
      expect(controller.error, contains('change was saved'));
      expect(controller.snapshot, isNotNull);
      expect(controller.saving, isFalse);
      controller.dispose();
    },
  );
}
