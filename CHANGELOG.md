## 2.0.0-rc.8

- Name the migration table: `TablesBase({String migrationTableName})`,
  e.g. `MyTables() : super(migrationTableName: 'my_migration');`. The
  default stays `authpass_migration` (`TablesBase.defaultMigrationTableName`),
  so existing databases are unchanged.
- `prepareDatabase()` throws a `StateError` instead of re-running every
  migration when the configured migration table is empty but
  `authpass_migration` holds history. Switching an existing database to a new
  name needs `ALTER TABLE authpass_migration RENAME TO <name>` first.
- **Breaking:** `DatabaseConfig.fromJson` / `fromEnvironment` require
  `databaseName`, `username` and `password` (which may be `null`). They no
  longer default to `'authpass'` / `'authpass'` / `'blubb'`, and
  `DatabaseConfig.defaults` is removed.

## 2.0.0-rc.7

- Fix `execute()` failing on parameterized statements: use the extended query
  protocol when values are present (like `query()` already does). This also
  fixes `executeUpdate()`, which passes values without the override.
- Fix `dispose()` throwing when no connection was opened.

## 2.0.0-rc.6

- Require `postgres` ^3.5.0; remove the `postgres/src` implementation import.
- Remove `CustomTypeBind`; `CustomBind` no longer takes a `type`.
- Replace the discontinued `pedantic` lint set with `lints` recommended.
- Add a dockerized smoke test (`test/smoke_test.dart`).

## 2.0.0-rc.5

- Migrate to `postgres` v3.
- Add `concatColumns` to `OnConflictActionDoUpdate` for allowing incremental updates in `upset`.

## 1.0.0

- Initial version.
