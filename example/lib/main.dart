import 'package:postgres/postgres.dart';
import 'package:postgres_utils/postgres_utils.dart';

class DatabaseTransaction extends DatabaseTransactionBase<MyTables> {
  DatabaseTransaction(PostgreSQLExecutionContext conn, MyTables tables)
      : super(conn, tables);
}

class DatabaseAccess extends DatabaseAccessBase<DatabaseTransaction, MyTables> {
  DatabaseAccess({
    required DatabaseConfig config,
  }) : super(
          config: config,
          tables: MyTables(),
          migrations: MyMigrationsProvider(),
        );

  @override
  DatabaseTransaction createDatabaseTransaction(
      PostgreSQLExecutionContext conn, MyTables tables) {
    return DatabaseTransaction(conn, tables);
  }
}

class MyTables extends TablesBase {
  MyTables();

  late final UserTable user = UserTable();
  @override
  List<TableBase> get tables => [
        user,
      ];
}

class UserTable extends TableBase {
  UserTable();

  static const TABLE_USER = 'user';

  @override
  List<String> get tables => [
        TABLE_USER,
      ];

  Future<void> createTables(DatabaseTransaction db) async {
    await db.execute('''
    CREATE TABLE $TABLE_USER (id uuid primary key, username varchar)
    ''');
  }
}

class MyMigrationsProvider
    extends MigrationsProvider<DatabaseTransaction, MyTables> {
  @override
  List<Migrations<DatabaseTransaction, MyTables>> get migrations {
    return [
      Migrations(
          id: 1,
          up: (conn) async {
            await conn.tables.user.createTables(conn);
          }),
    ];
  }
}
