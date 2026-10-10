import 'dart:convert';
import 'dart:io';

import 'package:json_annotation/json_annotation.dart';

part 'config.g.dart';

@JsonSerializable(anyMap: true, checked: true)
class DatabaseConfig {
  DatabaseConfig({
    required this.host,
    required this.port,
    required this.databaseName,
    required this.username,
    this.password,
  });

  factory DatabaseConfig.fromJson(Map<String, dynamic> json) =>
      _$DatabaseConfigFromJson(json);

  /// load database configuration from the `DBCONFIG` environment variables.
  /// this environment variable must be a json.
  factory DatabaseConfig.fromEnvironment({DatabaseConfig? defaults}) =>
      DatabaseConfig.fromJson(_jsonFromEnvironment(defaults));

  Map<String, dynamic> toJson() => _$DatabaseConfigToJson(this);

  @JsonKey(defaultValue: 'localhost')
  final String host;
  @JsonKey(defaultValue: 5432)
  final int port;

  @JsonKey(required: true)
  final String databaseName;
  @JsonKey(required: true)
  final String username;

  /// Must be present in json; `null` connects without a password.
  @JsonKey(required: true)
  final String? password;

  DatabaseConfig copyWith({
    String? host,
    int? port,
    String? databaseName,
  }) =>
      DatabaseConfig(
        host: host ?? this.host,
        port: port ?? this.port,
        databaseName: databaseName ?? this.databaseName,
        username: username,
        password: password,
      );
}

Map<String, dynamic> _jsonFromEnvironment(DatabaseConfig? defaults) {
  final defaultJson = defaults?.toJson() ?? <String, dynamic>{};
  final dbConfig = Platform.environment['DBCONFIG'];
  if (dbConfig != null) {
    return <String, dynamic>{
      ...defaultJson,
      ...(json.decode(dbConfig) as Map<String, dynamic>),
    };
  }
  return defaultJson;
}
