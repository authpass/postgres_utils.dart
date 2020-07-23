import 'dart:convert';
import 'dart:io';

import 'package:json_annotation/json_annotation.dart';
import 'package:meta/meta.dart';

part 'config.g.dart';

@JsonSerializable(anyMap: true, checked: true)
class DatabaseConfig {
  DatabaseConfig({
    @required this.host,
    @required this.port,
    @required this.databaseName,
    @required this.username,
    this.password,
  })  : assert(host != null),
        assert(port != null),
        assert(databaseName != null),
        assert(username != null);

  factory DatabaseConfig.fromJson(Map<String, dynamic> json) =>
      _$DatabaseConfigFromJson(json);

  factory DatabaseConfig.defaults() =>
      DatabaseConfig.fromJson(_jsonFromEnvironment());
  Map<String, dynamic> toJson() => _$DatabaseConfigToJson(this);

  @JsonKey(defaultValue: 'localhost')
  final String host;
  @JsonKey(defaultValue: 5432)
  final int port;

  @JsonKey(defaultValue: 'authpass')
  final String databaseName;
  @JsonKey(defaultValue: 'authpass')
  final String username;
  @JsonKey(defaultValue: 'blubb')
  final String password;

  DatabaseConfig copyWith({String databaseName}) => DatabaseConfig(
        host: host,
        port: port,
        databaseName: databaseName ?? this.databaseName,
        username: username,
        password: password,
      );
}

Map<String, dynamic> _jsonFromEnvironment() {
  final dbConfig = Platform.environment['DBCONFIG'];
  if (dbConfig != null) {
    return json.decode(dbConfig) as Map<String, dynamic>;
  }
  return <String, dynamic>{};
}
