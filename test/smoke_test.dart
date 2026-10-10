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
  _SmokeAccess({required super.config, _SmokeTables? tables})
      : super(
          connectionSettings:
              const ConnectionSettings(sslMode: SslMode.disable),
          tables: tables ?? _SmokeTables(),
          migrations: _SmokeMigrations(),
        );

  @override
  _SmokeTransaction createDatabaseTransaction(
      TxSession conn, _SmokeTables tables) {
    return _SmokeTransaction(conn, tables);
  }
}

class _SmokeTables extends TablesBase {
  _SmokeTables({super.migrationTableName});

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

  group('migration table name', () {
    const customName = 'smoke_custom_migration';

    // Drops everything these tests create, whichever migration table name
    // the access under test uses.
    Future<void> dropAll() async {
      final access = _SmokeAccess(config: _testConfig());
      addTearDown(access.dispose);
      await access.run((db) => db.execute('DROP TABLE IF EXISTS '
          'authpass_migration, $customName, smoke_note, smoke_payload '
          'CASCADE'));
    }

    // Builds the state a database migrated by 2.0.0-rc.7 is in: history in
    // `authpass_migration`, using the DDL rc.7 hard-coded, and both
    // migrations applied, with a row of user data.
    Future<void> seedRc7Database() async {
      final access = _SmokeAccess(config: _testConfig());
      addTearDown(access.dispose);
      await access.run((db) async {
        await db.execute('''
          CREATE TABLE authpass_migration (
            id SERIAL PRIMARY KEY,
            applied_at TIMESTAMP WITHOUT TIME ZONE NOT NULL,
            version INT NOT NULL,
            version_code VARCHAR NOT NULL
          )''');
        await db.execute('''
          INSERT INTO authpass_migration (applied_at, version, version_code)
          VALUES ('2026-10-01', 1, 'a'), ('2026-10-01', 2, 'a')''');
        await db.tables.note.createTable(db);
        await db.tables.payload.createTable(db);
        await db.tables.note.insertNote(db, 'kept');
      });
    }

    Future<List<int>> versions(String table) async {
      final access = _SmokeAccess(config: _testConfig());
      addTearDown(access.dispose);
      final rows = await access
          .run((db) => db.query('SELECT version FROM $table ORDER BY version'));
      return rows.map((row) => row[0]! as int).toList();
    }

    Future<bool> tableExists(String table) async {
      final access = _SmokeAccess(config: _testConfig());
      addTearDown(access.dispose);
      final rows = await access
          .run((db) => db.query("SELECT to_regclass('$table') IS NOT NULL"));
      return rows.single[0]! as bool;
    }

    setUp(dropAll);

    test('upgrade keeps reading authpass_migration and runs nothing', () async {
      await seedRc7Database();
      final access = _SmokeAccess(config: _testConfig());
      addTearDown(access.dispose);
      // Re-running migration 1 would fail on CREATE TABLE smoke_note.
      await access.prepareDatabase();
      expect(await versions('authpass_migration'), [1, 2]);
      final rows =
          await access.run((db) => db.query('SELECT body FROM smoke_note'));
      expect(rows.single[0], 'kept');
    });

    test('custom name refuses to start over authpass_migration history',
        () async {
      await seedRc7Database();
      final access = _SmokeAccess(
        config: _testConfig(),
        tables: _SmokeTables(migrationTableName: customName),
      );
      addTearDown(access.dispose);
      await expectLater(
        access.prepareDatabase(),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('ALTER TABLE authpass_migration RENAME TO $customName'),
        )),
      );
      expect(await tableExists(customName), isFalse);
      expect(await versions('authpass_migration'), [1, 2]);
    });

    test('custom name after renaming authpass_migration runs nothing',
        () async {
      await seedRc7Database();
      final rename = _SmokeAccess(config: _testConfig());
      addTearDown(rename.dispose);
      await rename.run((db) =>
          db.execute('ALTER TABLE authpass_migration RENAME TO $customName'));
      final access = _SmokeAccess(
        config: _testConfig(),
        tables: _SmokeTables(migrationTableName: customName),
      );
      addTearDown(access.dispose);
      await access.prepareDatabase();
      expect(await versions(customName), [1, 2]);
      expect(await tableExists('authpass_migration'), isFalse);
    });

    test('custom name on an empty database creates only its own table',
        () async {
      final access = _SmokeAccess(
        config: _testConfig(),
        tables: _SmokeTables(migrationTableName: customName),
      );
      addTearDown(access.dispose);
      await access.prepareDatabase();
      expect(await versions(customName), [1, 2]);
      expect(await tableExists('authpass_migration'), isFalse);
    });

    test('rejects a name that is not a plain identifier', () {
      expect(() => _SmokeTables(migrationTableName: 'x; DROP TABLE y'),
          throwsArgumentError);
    });
  });
}
