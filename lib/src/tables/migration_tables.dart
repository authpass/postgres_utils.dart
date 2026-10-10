import 'package:logging/logging.dart';
import 'package:postgres_utils/src/database_access.dart';
import 'package:postgres_utils/src/tables/base_tables.dart';

final _logger = Logger('migration_tables');

class MigrationTable extends TableBase with TableConstants {
  MigrationTable({this.tableName = legacyTableName}) {
    if (!_tableNamePattern.hasMatch(tableName)) {
      throw ArgumentError.value(
          tableName, 'tableName', 'Invalid migration table name.');
    }
  }

  /// The name every version before 2.0.0-rc.8 hard-coded, and still the
  /// default so existing databases keep their migration history.
  static const legacyTableName = 'authpass_migration';

  static final _tableNamePattern = RegExp(r'^[a-z_][a-z0-9_]*$');

  static const _TABLE_MIGRATE_VERSION = 'version';
  static const _TABLE_MIGRATE_VERSION_CODE = 'version_code';
  static const _TABLE_MIGRATE_APPLIED_AT = 'applied_at';

  /// Name of the table recording which migrations have run.
  final String tableName;

  @override
  List<String> get tables => [tableName];

  Future<void> createTable(DatabaseTransactionBase connection) async {
    _logger.finest('Creating table ...');
    final result = await connection.execute('''
      CREATE TABLE IF NOT EXISTS $tableName (
        $columnId SERIAL PRIMARY KEY,
        $_TABLE_MIGRATE_APPLIED_AT $typeTimestamp NOT NULL,
        $_TABLE_MIGRATE_VERSION INT NOT NULL,
        $_TABLE_MIGRATE_VERSION_CODE VARCHAR NOT NULL
      );
      ''');
    _logger.fine('Got result: $result');
    if (result > 0) {
      if (result > 1) {
        throw Exception('Expected at most 1 affected row $result');
      }
    }
  }

  Future<int> queryLastVersion(DatabaseTransactionBase connection) async {
    final result = await connection
        .query('SELECT MAX($_TABLE_MIGRATE_VERSION) FROM $tableName');
    final maxVersion = result.first[0] as int?;
    _logger.finer('Migration version: $maxVersion');
    return maxVersion ?? 0;
  }

  /// Throws a [StateError] when [legacyTableName] holds migration history
  /// although this table is named differently: starting from an empty
  /// history would run every migration again against the live schema.
  ///
  /// Call this only when this table holds no history.
  Future<void> checkLegacyHistory(DatabaseTransactionBase connection) async {
    if (tableName == legacyTableName) {
      return;
    }
    final exists = await connection
        .query("SELECT to_regclass('$legacyTableName') IS NOT NULL");
    if (exists.first[0] != true) {
      return;
    }
    final result = await connection
        .query('SELECT MAX($_TABLE_MIGRATE_VERSION) FROM $legacyTableName');
    final legacyVersion = result.first[0] as int?;
    if (legacyVersion == null) {
      return;
    }
    throw StateError(
        'Migration table $tableName is empty, but $legacyTableName holds '
        'migration history up to version $legacyVersion. Refusing to run '
        'migrations again from version 0. Rename the old table before '
        'starting (ALTER TABLE $legacyTableName RENAME TO $tableName, after '
        'dropping an empty $tableName if one exists), or keep the old name '
        "by passing migrationTableName: '$legacyTableName'.");
  }

  Future<void> insertMigrationRun(DatabaseTransactionBase db,
      DateTime appliedAt, int version, String versionCode) async {
    await db.executeInsert(tableName, {
      _TABLE_MIGRATE_APPLIED_AT: appliedAt,
      _TABLE_MIGRATE_VERSION: version,
      _TABLE_MIGRATE_VERSION_CODE: versionCode,
    });
  }
}

class MigrationEntity {
  MigrationEntity({
    required this.version,
    required this.versionCode,
    required this.appliedAt,
  });
  final int version;
  final String versionCode;
  final DateTime appliedAt;
}
