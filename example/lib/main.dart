import 'package:logging/logging.dart';
import 'package:logging_appenders/logging_appenders.dart';
import 'package:postgres/postgres.dart';
import 'package:postgres_utils/postgres_utils.dart';
import 'package:uuid/data.dart';
import 'package:uuid/rng.dart';
import 'package:uuid/uuid.dart';

final _logger = Logger('main');

final Uuid _uuid = Uuid(goptions: GlobalOptions(CryptoRNG()));

class DatabaseTransaction extends DatabaseTransactionBase<MyTables> {
  DatabaseTransaction(TxSession conn, MyTables tables) : super(conn, tables);
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
      TxSession conn, MyTables tables) {
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

  static const TABLE_USER = 'example_user';

  @override
  List<String> get tables => [
        TABLE_USER,
      ];

  Future<void> createTables(DatabaseTransaction db) async {
    await db.execute('''
    CREATE TABLE $TABLE_USER (id uuid primary key, username varchar)
    ''');
  }

  Future<void> createUser(DatabaseTransactionBase db, String userName) async {
    await db.executeInsert(TABLE_USER, {
      'id': _uuid.v4(),
      'username': userName,
    });
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

Future<void> main() async {
  PrintAppender.setupLogging();
  const dbName = 'example_tmp';
  final config = DatabaseConfig.fromEnvironment();
  await _createDb(dbName, config);

  final access = DatabaseAccess(config: config.copyWith(databaseName: dbName));
  await access.prepareDatabase();
  await access.run((db) async {
    await db.tables.user.createUser(db, 'foo');
    _logger.info('Successfully created user.');
  });
  await access.dispose();
}

Future<void> _createDb(String dbName, DatabaseConfig config) async {
  final tmp = DatabaseAccess(
    config: config,
  );
  // ignore: invalid_use_of_visible_for_testing_member
  await tmp.forTestDropDatabase(dbName, ifExists: true);
  // ignore: invalid_use_of_visible_for_testing_member
  await tmp.forTestCreateDatabase(dbName);
  await tmp.dispose();
}
