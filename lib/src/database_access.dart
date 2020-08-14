import 'package:clock/clock.dart';
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';
import 'package:postgres/postgres.dart';
import 'package:postgres_utils/src/config.dart';
import 'package:postgres_utils/src/tables/base_tables.dart';
import 'package:postgres_utils/src/tables/migration_tables.dart';
import 'package:quiver/check.dart';
import 'package:quiver/core.dart';

final _logger = Logger('database_access');

class DatabaseTransactionBase<TABLES extends TablesBase> {
  DatabaseTransactionBase(this._conn, this.tables);

  final PostgreSQLExecutionContext _conn;
  final TABLES tables;
  static final columnNamePattern = RegExp(r'^[a-z_]+$');

  void _assertColumnNames(Map<String, Object> values) {
    assert((() {
      for (final key in values.keys) {
        if (!columnNamePattern.hasMatch(key)) {
          throw ArgumentError.value(key, 'values', 'Invalid column name.');
        }
      }
      return true;
    })());
  }

  Future<int> executeInsert(String table, Map<String, Object> values) async {
    _assertColumnNames(values);
    final entries = values.entries.toList();
    final columnList = entries.map((e) => e.key).join(',');
    final bindList = entries.map((e) => _bindForEntry(e)).join(',');
    return await execute('INSERT INTO $table ($columnList) VALUES ($bindList)',
        values: values.map((key, value) =>
            MapEntry(key, value is CustomBind ? value.value : value)),
        expectedResultCount: 1);
  }

  String _bindForEntry(MapEntry<String, Object> entry) {
    final value = entry.value;
    if (value is CustomBind) {
      return value.bind;
    }
    return '@${entry.key}';
  }

  Future<int> executeUpdate(
    String table, {
    @required Map<String, Object> set,
    @required Map<String, Object> where,
    bool setContainsOptional = false,
  }) async {
    assert(set != null);
    assert(where != null);
    _assertColumnNames(set);
    _assertColumnNames(where);
    assert(!where.keys.any((key) => set.containsKey(key)));
    assert(!where.values.contains(null), 'where values must not be null.');
    assert(!setContainsOptional || set.values.whereType<Optional>().isEmpty);
    if (setContainsOptional) {
      set = flattenOptionals(set);
    }
    final setStatement =
        set.entries.map((e) => '${e.key} = @${e.key}').join(',');
    final whereStatement =
        where.entries.map((e) => '${e.key} = @${e.key}').join(' AND ');
    return await execute(
        'UPDATE $table SET $setStatement WHERE $whereStatement',
        values: {
          ...set,
          ...where,
        },
        expectedResultCount: 1);
  }

  /// Removes entries in [values] which have a `null` value, and replaces
  /// all [Optional] values with their actual value.
  Map<String, Object> flattenOptionals(Map<String, Object> values) {
    Object unwrap(Object value) => value is Optional ? value.orNull : value;
    return Map.fromEntries(values.entries
        .where((element) => element != null)
        .map((e) => MapEntry(e.key, unwrap(e.value))));
  }

  bool _assertCorrectValues(Map<String, Object> values) {
    if (values == null) {
      return true;
    }
    for (final entry in values.entries) {
      final value = entry.value;
      if (value is DateTime) {
        if (!value.isUtc) {
          throw ArgumentError.value(
              entry, 'Value for ${entry.key} is a non-UTC DateTime.');
        }
      }
    }
    return true;
  }

  Future<int> execute(
    String fmtString, {
    Map<String, Object> values,
    int timeoutInSeconds,
    int expectedResultCount,
  }) async {
    try {
      assert(_assertCorrectValues(values));
      _logger.finest('Executing query: $fmtString with values: $values');
      final result = await _conn.execute(fmtString,
          substitutionValues: values, timeoutInSeconds: timeoutInSeconds);
      if (expectedResultCount != null && result != expectedResultCount) {
        throw StateError(
            'Expected result: $expectedResultCount but got $result. '
            'for query: $fmtString');
      }
      return result;
    } catch (e, stackTrace) {
      _logger.warning(
          'Error while running statement $fmtString', e, stackTrace);
      rethrow;
    }
  }

  Future<PostgreSQLResult> query(String fmtString,
      {Map<String, Object> values,
      bool allowReuse,
      int timeoutInSeconds}) async {
    assert(_assertCorrectValues(values));
    return _conn.query(fmtString,
        substitutionValues: values,
        allowReuse: allowReuse,
        timeoutInSeconds: timeoutInSeconds);
  }
}

class CustomBind {
  CustomBind(this.bind, this.value);
  final String bind;
  final Object value;
}

abstract class DatabaseAccessBase<TX extends DatabaseTransactionBase<TABLES>,
    TABLES extends TablesBase> {
  DatabaseAccessBase({
    @required this.config,
    @required this.tables,
    @required this.migrations,
  })  : assert(config != null),
        assert(tables != null),
        assert(migrations != null);

  final TABLES tables;
  final DatabaseConfig config;
  final MigrationsProvider<TX, TABLES> migrations;

  PostgreSQLConnection _conn;

  Future<PostgreSQLConnection> _connection() async {
    if (_conn != null) {
      return _conn;
    }
    final conn = PostgreSQLConnection(
      config.host,
      config.port,
      config.databaseName,
      username: config.username,
      password: config.password,
    );
    await conn.open();
    return _conn = conn;
  }

  @visibleForTesting
  Future<void> forTestCreateDatabase(String name) async {
    await (await _connection()).execute('CREATE DATABASE $name');
  }

  @visibleForTesting
  Future<void> forTestDropDatabase(String databaseName) async {
    await (await _connection()).execute('DROP DATABASE $databaseName');
  }

  Future<void> dispose() async {
    await _conn.close();
    _conn = null;
  }

  Future<T> run<T>(Future<T> Function(TX db) block) async =>
      _transaction((conn) async {
        return await block(createDatabaseTransaction(conn, tables));
      });

  Future<T> _transaction<T>(
      Future<T> Function(PostgreSQLExecutionContext conn) queryBlock) async {
    final conn = await _connection();
    final dynamic result = await conn.transaction(queryBlock);
    if (result is T) {
      return result;
    }
    throw Exception(
        'Error running in transaction, $result (${result.runtimeType})'
        ' is not ${T.runtimeType}');
  }

  Future<void> prepareDatabase() async {
    _logger.finest('Initializing database.');
//    await clean();
    final lastMigration = await run((connection) async {
      try {
        await tables.migration.createTable(connection);
        return await tables.migration.queryLastVersion(connection);
      } catch (e, stackTrace) {
        _logger.severe('Error during migration', e, stackTrace);
        rethrow;
      }
    });
    _logger.fine('Last migration: $lastMigration');
    if (lastMigration > 0 && lastMigration < 3) {
      _logger.warning('Recreating database.');
      await clean();
      await run((conn) async {
        await tables.migration.createTable(conn);
      });
    }

    final migrationRun = clock.now().toUtc();
    await run((conn) async {
      final migrations = this.migrations.migrations;
      for (final migration in migrations) {
        if (migration.id > lastMigration) {
          _logger.fine('Running migration ${migration.id} '
              '(${migration.versionCode})');
          await migration.up(conn);
          await tables.migration.insertMigrationRun(
              conn, migrationRun, migration.id, migration.versionCode);
        }
      }
    });

//    _database = config.database();
//    final client = _database.sqlClient;
//    _logger.finest('Running migration.');
//    await client.runInTransaction((t) async {
//      final result = await client.run(
//        SqlSourceBuilder()
//          ..write('CREATE TABLE IF NOT EXISTS ')
//          ..identifier(_TABLE_MIGRATE)
//          ..write(' (')
//          ..identifier(_COLUMN_ID)
//          ..write(' id PRIMARY KEY SERIAL, ')
//          ..identifier(_TABLE_MIGRATE_APPLIED_AT)
//          ..write(' timestamp without time zone')
//          ..identifier(_TABLE_MIGRATE_VERSION)
//          ..write('INT NOT NULL)'),
//      );
//    });
//    final table = _database.sqlClient.table('authpass_migration');
//    _database.collection(_TABLE_MIGRATE).document('1');
  }

  Future<void> clean() async {
    _logger.warning('Clearing database.');
    final tableNames = tables._allTables.expand((e) => e.tables);
    final typeNames = tables._allTables.expand((e) => e.types);
    await run((connection) async {
      final tables = tableNames.join(', ');
      final result =
          await connection.execute('DROP TABLE IF EXISTS $tables CASCADE');
      _logger.fine('Dropped $tables ($result)');
      if (typeNames.isNotEmpty) {
        await connection.execute('DROP TYPE IF EXISTS ${typeNames.join(', ')}');
      }

//      for (final tableName in tableNames) {
//        final result =
//            await connection.execute('DROP TABLE IF EXISTS $tableName');
//        _logger.fine('Dropped $tableName ($result)');
//      }
    });
  }

  @protected
  TX createDatabaseTransaction(PostgreSQLExecutionContext conn, TABLES tables);
}

//extension on SqlClientBase {
//  Future<SqlStatementResult> run(SqlSourceBuilder builder) async {
//    final stmt = builder.build();
//    _logger.finest('Running SQL ${stmt.value}');
//    return execute(stmt.value, stmt.arguments);
//  }
//}

abstract class TablesBase {
  final migration = MigrationTable();

  @protected
  List<TableBase> get tables;

  List<TableBase> get _allTables => [
        migration,
        ...tables,
      ];
}

abstract class MigrationsProvider<TX extends DatabaseTransactionBase<TABLES>,
    TABLES extends TablesBase> {
  List<Migrations<TX, TABLES>> get migrations;
}

class Migrations<TX extends DatabaseTransactionBase<TABLES>,
    TABLES extends TablesBase> {
  Migrations({
    @required this.id,
    this.versionCode = 'a',
    @required this.up,
  })  : assert(id != null),
        assert(up != null);

  final int id;
  final String versionCode;
  final Future<void> Function(TX tx) up;
}

class SimpleWhere {
  SimpleWhere(this.conditions, {bool filterNullValues = false})
      : assert(filterNullValues || !conditions.values.contains(null),
            'where values must not be null.') {
    if (filterNullValues) {
      conditions.removeWhere((key, value) => value == null);
    }
    checkState(conditions.isNotEmpty);
  }

  final Map<String, Object> conditions;

  String sql() =>
      conditions.entries.map((e) => '${e.key} = @${e.key}').join(' AND ');
}
