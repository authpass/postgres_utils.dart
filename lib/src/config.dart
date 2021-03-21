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

  factory DatabaseConfig.fromEnvironment({DatabaseConfig? defaults}) =>
      DatabaseConfig.fromJson(_jsonFromEnvironment(defaults));

  static final defaults = DatabaseConfig.fromJson(<String, dynamic>{});

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
