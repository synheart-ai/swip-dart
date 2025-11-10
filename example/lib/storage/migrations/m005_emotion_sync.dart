import 'package:sqflite/sqflite.dart';

Future<void> apply(DatabaseExecutor db) async {
  await db.execute('''
    ALTER TABLE dim_emotions
    ADD COLUMN synced_to_cloud INTEGER NOT NULL DEFAULT 0
  ''');

  await db.execute('''
    ALTER TABLE dim_emotions
    ADD COLUMN synced_at TEXT
  ''');

  await db.execute('''
    CREATE INDEX IF NOT EXISTS idx_emotions_synced
    ON dim_emotions(synced_to_cloud)
  ''');
}
