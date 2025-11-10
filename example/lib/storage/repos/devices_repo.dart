import 'package:sqflite/sqflite.dart';

class DevicesRepo {
  final Database db;
  DevicesRepo(this.db);

  Future<void> upsertDevice({
    required String deviceId,
    String? platform,
    String? model,
    String? osVersion,
  }) async {
    await db.insert(
      'dim_devices',
      {
        'device_id': deviceId,
        'platform': platform,
        'model': model,
        'os_version': osVersion,
        'created_datetime': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<List<Map<String, Object?>>> getUnregisteredDevices() async {
    return await db.query(
      'dim_devices',
      where: 'registered_to_cloud = 0',
    );
  }

  Future<void> markDeviceRegistered({
    required String deviceId,
  }) async {
    await db.update(
      'dim_devices',
      {
        'registered_to_cloud': 1,
        'registered_at': DateTime.now().toUtc().toIso8601String(),
        'last_register_error': null,
      },
      where: 'device_id = ?',
      whereArgs: [deviceId],
    );
  }

  Future<void> recordRegisterFailure({
    required String deviceId,
    required String error,
  }) async {
    // get current attempts
    final cur = await db.query(
      'dim_devices',
      columns: ['register_attempts'],
      where: 'device_id = ?',
      whereArgs: [deviceId],
      limit: 1,
    );
    final attempts = (cur.first['register_attempts'] as int?) ?? 0;
    await db.update(
      'dim_devices',
      {
        'register_attempts': attempts + 1,
        'last_register_error': error,
      },
      where: 'device_id = ?',
      whereArgs: [deviceId],
    );
  }
}
