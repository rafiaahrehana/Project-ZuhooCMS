import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuhoo/core/storage/json_cache.dart';

void main() {
  Future<JsonCache> cacheWith(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    final prefs = await SharedPreferences.getInstance();
    return JsonCache(prefs);
  }

  group('JsonCache', () {
    test('a key that was never written reads as null', () async {
      final cache = await cacheWith({});
      expect(cache.read('nope'), isNull);
      expect(cache.writtenAt('nope'), isNull);
    });

    test('round-trips a list of maps', () async {
      final cache = await cacheWith({});
      final value = [
        {'id': 1, 'name': 'First'},
        {'id': 2, 'name': 'Second'},
      ];

      await cache.write('items', value);
      final read = cache.read('items');

      expect(read, isA<List>());
      expect((read as List).length, 2);
      expect(read.first, {'id': 1, 'name': 'First'});
    });

    test('records when it was written', () async {
      final cache = await cacheWith({});
      final before = DateTime.now();

      await cache.write('items', const []);
      final writtenAt = cache.writtenAt('items');

      expect(writtenAt, isNotNull);
      expect(writtenAt!.isBefore(before.add(const Duration(seconds: 2))), isTrue);
      expect(writtenAt.isAfter(before.subtract(const Duration(seconds: 2))), isTrue);
    });

    test('overwriting a key replaces both the value and the timestamp', () async {
      final cache = await cacheWith({});

      await cache.write('items', const ['old']);
      final firstStamp = cache.writtenAt('items');

      await Future<void>.delayed(const Duration(milliseconds: 5));
      await cache.write('items', const ['new']);

      expect(cache.read('items'), ['new']);
      expect(cache.writtenAt('items')!.isAfter(firstStamp!), isTrue);
    });

    test('a corrupted stored value reads as null rather than throwing', () async {
      final cache = await cacheWith({'cache.broken': 'not json {'});
      expect(cache.read('broken'), isNull);
    });

    test('different keys do not collide', () async {
      final cache = await cacheWith({});
      await cache.write('a', const {'x': 1});
      await cache.write('b', const {'x': 2});

      expect(cache.read('a'), {'x': 1});
      expect(cache.read('b'), {'x': 2});
    });
  });
}
