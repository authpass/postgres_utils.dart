import 'dart:async';

import 'package:postgres/postgres.dart';

abstract class TableBase {
  List<String> get tables;
  List<String> get types => const [];
}

abstract class TableConstants {
  final columnId = 'id';
  String get specColumnIdPrimaryKey => '$columnId uuid primary key';

  final typeTimestamp = 'TIMESTAMP WITHOUT TIME ZONE';

  final columnCreatedAt = 'created_at';

  final columnDeletedAt = 'deleted_at';

  String get typeTimestampNotNull => '$typeTimestamp NOT NULL';

  String get specColumnCreatedAt => '$columnCreatedAt $typeTimestampNotNull '
      'DEFAULT CURRENT_TIMESTAMP';
}

extension FuturePostgreSQL on Future<PostgreSQLResult> {
  Future<T?> singleOrNull<T>(
          FutureOr<T?> Function(PostgreSQLResultRow row) cb) =>
      then((value) => value.singleOrNull<FutureOr<T?>>(cb));
  Future<PostgreSQLResultRow> get single => then((value) => value.single);
}

extension PostgreSQLResultExt on PostgreSQLResult {
  T? singleOrNull<T>(T Function(PostgreSQLResultRow row) cb) {
    if (isEmpty) {
      return null;
    }
    return cb(single);
  }
}
