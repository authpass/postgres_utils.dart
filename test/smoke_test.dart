// Smoke test: runs the migration runner against stock postgres in docker,
// inserts rows (including a jsonb payload), updates one, and queries back.
//
// Prerequisite: a reachable postgres. Start one with:
//
//   docker run --name postgres-utils-smoke \
//     -e POSTGRES_USER=smoke -e POSTGRES_PASSWORD=smoke \
//     -e POSTGRES_DB=smoke -p 5544:5432 -d postgres:17
//
// Then run this file (DBCONFIG json overrides the defaults below):
//
//   dart test test/smoke_test.dart
//
// Cleanup:
//
//   docker rm -f postgres-utils-smoke
//
// The test wipes its own tables before running; point it at a scratch
// database only.

import 'package:postgres/postgres.dart';
import 'package:postgres_utils/postgres_utils.dart';
import 'package:test/test.dart';

class _SmokeTransaction extends DatabaseTransactionBase<_SmokeTables> {
  // ignore: use_super_parameters, the matching super parameter is private.
  _SmokeTransaction(TxSession conn, _SmokeTables tables) : super(conn, tables);
}

class _SmokeAccess extends DatabaseAccessBase<_SmokeTransaction, _SmokeTables> {
  _SmokeAccess({required super.config})
      : super(
          connectionSettings:
              const ConnectionSettings(sslMode: SslMode.disable),
          tables: _SmokeTables(),
          migrations: _SmokeMigrations(),
        );

  @override
  _SmokeTransaction createDatabaseTransaction(
      TxSession conn, _SmokeTables tables) {
    return _SmokeTransaction(conn, tables);
  }
}

class _SmokeTables extends TablesBase {
  final note = _NoteTable();
  final payload = _PayloadTable();

  @override
  List<TableBase> get tables => [
        note,
        payload,
      ];
}

class _NoteTable extends TableBase {
  static const tableName = 'smoke_note';

  @override
  List<String> get tables => [
        tableName,
      ];

  Future<void> createTable(_SmokeTransaction db) async {
    await db.execute(
        'CREATE TABLE $tableName (id serial primary key, body varchar)');
  }

  Future<void> insertNote(_SmokeTransaction db, String body) async {
    await db.executeInsert(tableName, {
      'body': body,
    });
  }
}

class _PayloadTable extends TableBase {
  static const tableName = 'smoke_payload';

  @override
  List<String> get tables => [
        tableName,
      ];

  Future<void> createTable(_SmokeTransaction db) async {
    await db
        .execute('CREATE TABLE $tableName (id serial primary key, body jsonb)');
  }

  Future<void> insertPayload(
      _SmokeTransaction db, Map<String, Object?> payload) async {
    await db.executeInsert(tableName, {
      'body': payload,
    });
  }
}

class _SmokeMigrations
    extends MigrationsProvider<_SmokeTransaction, _SmokeTables> {
  @override
  List<Migrations<_SmokeTransaction, _SmokeTables>> get migrations => [
        Migrations(
          id: 1,
          up: (conn) async {
            await conn.tables.note.createTable(conn);
          },
        ),
        Migrations(
          id: 2,
          up: (conn) async {
            await conn.tables.payload.createTable(conn);
          },
        ),
      ];
}

DatabaseConfig _testConfig() => DatabaseConfig.fromEnvironment(
      defaults: DatabaseConfig(
        host: 'localhost',
        port: 5544,
        databaseName: 'smoke',
        username: 'smoke',
        password: 'smoke',
      ),
    );

void main() {
  test('migrate, insert, query back', () async {
    final access = _SmokeAccess(config: _testConfig());
    addTearDown(access.dispose);
    await access.clean();
    await access.prepareDatabase();
    const body = 'hello smoke';
    await access.run((db) async {
      await db.tables.note.insertNote(db, body);
    });
    final rows =
        await access.run((db) => db.query('SELECT body FROM smoke_note'));
    expect(rows.single[0], body);
  });

  test('insert and query jsonb', () async {
    final access = _SmokeAccess(config: _testConfig());
    addTearDown(access.dispose);
    await access.clean();
    await access.prepareDatabase();
    final payload = <String, Object?>{
      'level': 'debug',
      'count': 3,
      'tags': ['a', 'b'],
      'meta': {'x': true},
    };
    await access.run((db) async {
      await db.tables.payload.insertPayload(db, payload);
    });
    final rows =
        await access.run((db) => db.query('SELECT body FROM smoke_payload'));
    expect(rows.single[0], payload);
  });

  test('update with binds through executeUpdate', () async {
    final access = _SmokeAccess(config: _testConfig());
    addTearDown(access.dispose);
    await access.clean();
    await access.prepareDatabase();
    const before = 'before';
    const after = 'after';
    await access.run((db) async {
      await db.tables.note.insertNote(db, before);
    });
    final updated = await access.run((db) => db.executeUpdate(
          'smoke_note',
          set: {'body': after},
          where: {'body': before},
        ));
    expect(updated, 1);
    final rows =
        await access.run((db) => db.query('SELECT body FROM smoke_note'));
    expect(rows.single[0], after);
  });
}
