import 'package:flutter_test/flutter_test.dart';
import 'package:run_track_app/utils/common_utils.dart';

void main() {
  group('CommonUtils', () {
    test('should join athlete names correctly', () {
      final names = <String>['John Doe', 'Jane Smith', 'Bob Wilson'];
      final result = CommonUtils.joinAthleteNames(names, '|');
      expect(result, equals('John Doe|Jane Smith|Bob Wilson'));
    });

    test('should handle single athlete name', () {
      final names = <String>['John Doe'];
      final result = CommonUtils.joinAthleteNames(names, '|');
      expect(result, equals('John Doe'));
    });

    test('should handle empty list', () {
      final names = <String>[];
      final result = CommonUtils.joinAthleteNames(names, '|');
      expect(result, equals(''));
    });

    test('should trim names and ignore blank entries', () {
      final names = <String>[' John Doe ', '', '  ', 'Jane Smith'];
      final result = CommonUtils.joinAthleteNames(names, ' | ');
      expect(result, equals('John Doe | Jane Smith'));
    });

    test('should handle case insensitive comparison', () {
      expect('RUNNING'.toLowerCase(), equals('running'));
      expect('Running'.toLowerCase(), equals('running'));
      expect('running'.toLowerCase(), equals('running'));
    });

    test('should get initials correctly', () {
      expect(CommonUtils.getInitials('John Doe'), equals('JD'));
      expect(CommonUtils.getInitials('Jane Smith'), equals('JS'));
      expect(CommonUtils.getInitials('Bob Wilson'), equals('BW'));
      expect(CommonUtils.getInitials('Doe'), equals('D'));
      expect(CommonUtils.getInitials('Smith'), equals('S'));
    });

    test('should handle null names gracefully', () {
      expect(() => CommonUtils.getInitials(null), returnsNormally);
      expect(CommonUtils.getInitials(null), equals(''));
    });

    test('should check if string is numeric', () {
      expect(CommonUtils.isNumeric('123'), isTrue);
      expect(CommonUtils.isNumeric('12.34'), isTrue);
      expect(CommonUtils.isNumeric('abc'), isFalse);
      expect(CommonUtils.isNumeric(''), isFalse);
      expect(CommonUtils.isNumeric(null), isFalse);
    });

    test('should check if string is empty', () {
      expect(CommonUtils.isEmpty(''), isTrue);
      expect(CommonUtils.isEmpty(null), isTrue);
      expect(CommonUtils.isEmpty(' '), isFalse);
      expect(CommonUtils.isEmpty('Hello'), isFalse);
    });
  });
}
