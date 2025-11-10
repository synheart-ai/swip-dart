import 'package:sqflite/sqflite.dart';

Future<void> apply(DatabaseExecutor db) async {
  await db.execute('''
    ALTER TABLE dim_devices
    ADD COLUMN registered_to_cloud INTEGER NOT NULL DEFAULT 0
  ''');

  await db.execute('''
    ALTER TABLE dim_devices
    ADD COLUMN registered_at TEXT
  ''');

  await db.execute('''
    ALTER TABLE dim_devices
    ADD COLUMN register_attempts INTEGER NOT NULL DEFAULT 0
  ''');

  await db.execute('''
    ALTER TABLE dim_devices
    ADD COLUMN last_register_error TEXT
  ''');

  await db.execute('''
    CREATE INDEX IF NOT EXISTS idx_devices_registered
    ON dim_devices(registered_to_cloud)
  ''');
}
