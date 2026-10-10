// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'config.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

DatabaseConfig _$DatabaseConfigFromJson(Map json) => $checkedCreate(
      'DatabaseConfig',
      json,
      ($checkedConvert) {
        $checkKeys(
          json,
          requiredKeys: const ['databaseName', 'username', 'password'],
        );
        final val = DatabaseConfig(
          host: $checkedConvert('host', (v) => v as String? ?? 'localhost'),
          port: $checkedConvert('port', (v) => (v as num?)?.toInt() ?? 5432),
          databaseName: $checkedConvert('databaseName', (v) => v as String),
          username: $checkedConvert('username', (v) => v as String),
          password: $checkedConvert('password', (v) => v as String?),
        );
        return val;
      },
    );

Map<String, dynamic> _$DatabaseConfigToJson(DatabaseConfig instance) =>
    <String, dynamic>{
      'host': instance.host,
      'port': instance.port,
      'databaseName': instance.databaseName,
      'username': instance.username,
      'password': instance.password,
    };
