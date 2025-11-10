import 'package:sqflite/sqflite.dart';

Future<void> apply(DatabaseExecutor db) async {
  await db.execute('''
    ALTER TABLE dim_App_biosignals
    ADD COLUMN synced_to_cloud INTEGER NOT NULL DEFAULT 0
  ''');

  await db.execute('''
    ALTER TABLE dim_App_biosignals
    ADD COLUMN synced_at TEXT
  ''');

  await db.execute('''
    CREATE INDEX IF NOT EXISTS idx_biosignals_synced
    ON dim_App_biosignals(synced_to_cloud, app_session_id)
  ''');
}

