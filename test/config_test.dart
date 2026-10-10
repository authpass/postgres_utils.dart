import 'package:json_annotation/json_annotation.dart';
import 'package:postgres_utils/postgres_utils.dart';
import 'package:test/test.dart';

void main() {
  const complete = <String, dynamic>{
    'databaseName': 'app',
    'username': 'app',
    'password': 'secret',
  };

  test('fromJson applies only host and port defaults', () {
    final config = DatabaseConfig.fromJson(complete);
    expect(config.host, 'localhost');
    expect(config.port, 5432);
    expect(config.databaseName, 'app');
    expect(config.username, 'app');
    expect(config.password, 'secret');
  });

  for (final key in complete.keys) {
    test('fromJson rejects a missing $key', () {
      expect(
        () => DatabaseConfig.fromJson({...complete}..remove(key)),
        throwsA(isA<CheckedFromJsonException>()
            .having((e) => e.key, 'key', key)
            .having((e) => e.innerError, 'innerError',
                isA<MissingRequiredKeysException>())),
      );
    });
  }

  test('fromJson accepts an explicit null password', () {
    final config = DatabaseConfig.fromJson({...complete, 'password': null});
    expect(config.password, isNull);
  });
}
