import 'package:flutter_test/flutter_test.dart';
import 'package:makaw_mobile/core/domain/value_objects/url.dart';

void main() {
  group('Url value object', () {
    test('creates from valid http URL', () {
      final url = Url('http://example.com');
      expect(url.value, 'http://example.com');
    });

    test('creates from valid https URL', () {
      final url = Url('https://example.com/path?q=1');
      expect(url.scheme, 'https');
      expect(url.host, 'example.com');
      expect(url.path, '/path');
    });

    test('tryParse returns Url for valid input', () {
      final result = Url.tryParse('https://flutter.dev');
      expect(result, isNotNull);
      expect(result!.host, 'flutter.dev');
    });

    test('tryParse returns null for empty string', () {
      expect(Url.tryParse(''), isNull);
    });

    test('tryParse returns null for missing scheme', () {
      expect(Url.tryParse('not-a-url'), isNull);
    });

    test('tryParse returns null for non-http scheme', () {
      expect(Url.tryParse('ftp://example.com'), isNull);
    });

    test('throws ArgumentError for invalid URL', () {
      expect(() => Url('invalid'), throwsArgumentError);
    });

    test('equality', () {
      final a = Url('https://example.com');
      final b = Url('https://example.com');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('inequality', () {
      final a = Url('https://example.com');
      final b = Url('https://other.com');
      expect(a, isNot(b));
    });

    test('toString', () {
      final url = Url('https://example.com');
      expect(url.toString(), contains('https://example.com'));
    });
  });
}
