import 'package:sqflite/sqflite.dart';

Future<void> apply(DatabaseExecutor db) async {
  // Add sync status columns to sessions table
  await db.execute('''
    ALTER TABLE dim_App_Session 
    ADD COLUMN synced_to_cloud INTEGER NOT NULL DEFAULT 0
  ''');

  await db.execute('''
    ALTER TABLE dim_App_Session 
    ADD COLUMN sync_attempts INTEGER NOT NULL DEFAULT 0
  ''');

  await db.execute('''
    ALTER TABLE dim_App_Session 
    ADD COLUMN last_sync_attempt TEXT
  ''');

  await db.execute('''
    ALTER TABLE dim_App_Session 
    ADD COLUMN last_sync_error TEXT
  ''');

  await db.execute('''
    ALTER TABLE dim_App_Session 
    ADD COLUMN synced_at TEXT
  ''');

  // Add hrv_rmssd column to biosignals table
  await db.execute('''
    ALTER TABLE dim_App_biosignals 
    ADD COLUMN hrv_rmssd REAL
  ''');

  // Add index for faster unsynced queries
  await db.execute('''
    CREATE INDEX IF NOT EXISTS idx_session_synced 
    ON dim_App_Session(synced_to_cloud, started_at)
  ''');

  await db.execute('UPDATE schema_version SET version = 2, applied_at = datetime("now") WHERE version = 1');
  await db.execute('INSERT OR IGNORE INTO schema_version(version, applied_at) VALUES (2, datetime("now"))');
}

