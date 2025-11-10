import 'package:sqflite/sqflite.dart';

Future<void> apply(DatabaseExecutor db) async {
  // Schema version
  await db.execute('''
  CREATE TABLE IF NOT EXISTS schema_version (
    version INTEGER PRIMARY KEY,
    applied_at TEXT NOT NULL
  )
  ''');

  // Users
  await db.execute('''
  CREATE TABLE IF NOT EXISTS dim_swip_users (
    user_id TEXT PRIMARY KEY,
    created_datetime TEXT NOT NULL
  )
  ''');

  // Consents
  await db.execute('''
  CREATE TABLE IF NOT EXISTS dim_swip_users_consent (
    user_id TEXT NOT NULL,
    type TEXT NOT NULL,
    created_datetime TEXT NOT NULL,
    status TEXT NOT NULL,
    PRIMARY KEY (user_id, type, created_datetime),
    FOREIGN KEY (user_id) REFERENCES dim_swip_users(user_id) ON DELETE CASCADE
  )
  ''');

  // Devices
  await db.execute('''
  CREATE TABLE IF NOT EXISTS dim_devices (
    device_id TEXT PRIMARY KEY,
    platform TEXT,
    model TEXT,
    os_version TEXT,
    created_datetime TEXT
  )
  ''');

  // Apps
  await db.execute('''
  CREATE TABLE IF NOT EXISTS dim_app (
    app_id TEXT PRIMARY KEY,
    app_name TEXT,
    app_version TEXT,
    category TEXT,
    developer TEXT,
    app_avg_swip_score REAL
  )
  ''');

  // Sessions
  await db.execute('''
  CREATE TABLE IF NOT EXISTS dim_App_Session (
    app_session_id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    device_id TEXT,
    started_at TEXT NOT NULL,
    ended_at TEXT,
    app_id TEXT NOT NULL,
    data_on_cloud INTEGER NOT NULL DEFAULT 0,
    avg_swip_score REAL,
    FOREIGN KEY (user_id) REFERENCES dim_swip_users(user_id) ON DELETE CASCADE,
    FOREIGN KEY (device_id) REFERENCES dim_devices(device_id) ON DELETE SET NULL,
    FOREIGN KEY (app_id) REFERENCES dim_app(app_id) ON DELETE CASCADE
  )
  ''');

  // Failures
  await db.execute('''
  CREATE TABLE IF NOT EXISTS dim_App_failure (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    app_session_id TEXT NOT NULL,
    failure_name TEXT NOT NULL,
    created_datetime TEXT NOT NULL,
    FOREIGN KEY (app_session_id) REFERENCES dim_App_Session(app_session_id) ON DELETE CASCADE
  )
  ''');

  // Biosignals
  await db.execute('''
  CREATE TABLE IF NOT EXISTS dim_App_biosignals (
    app_biosignal_id TEXT PRIMARY KEY,
    app_session_id TEXT NOT NULL,
    timestamp TEXT NOT NULL,
    respiratory_rate REAL,
    hrv_sdnn REAL,
    heart_rate REAL,
    accelerometer REAL,
    temperature REAL,
    blood_oxygen_saturation REAL,
    ecg REAL,
    emg REAL,
    eda REAL,
    gyro REAL,
    ppg REAL,
    ibi REAL,
    FOREIGN KEY (app_session_id) REFERENCES dim_App_Session(app_session_id) ON DELETE CASCADE
  )
  ''');

  // Emotions
  await db.execute('''
  CREATE TABLE IF NOT EXISTS dim_emotions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    app_biosignal_id TEXT NOT NULL,
    swip_score REAL,
    phys_subscore REAL,
    emo_subscore REAL,
    confidence REAL,
    dominant_emotion TEXT,
    model_id TEXT,
    FOREIGN KEY (app_biosignal_id) REFERENCES dim_App_biosignals(app_biosignal_id) ON DELETE CASCADE
  )
  ''');

  // Indexes
  await db.execute('CREATE INDEX IF NOT EXISTS idx_consent_user ON dim_swip_users_consent(user_id)');
  await db.execute('CREATE INDEX IF NOT EXISTS idx_session_user ON dim_App_Session(user_id)');
  await db.execute('CREATE INDEX IF NOT EXISTS idx_session_device ON dim_App_Session(device_id)');
  await db.execute('CREATE INDEX IF NOT EXISTS idx_session_app ON dim_App_Session(app_id)');
  await db.execute('CREATE INDEX IF NOT EXISTS idx_bio_session_time ON dim_App_biosignals(app_session_id, timestamp)');
  await db.execute('CREATE INDEX IF NOT EXISTS idx_emotion_bio ON dim_emotions(app_biosignal_id)');

  await db.execute('INSERT OR REPLACE INTO schema_version(version, applied_at) VALUES (1, datetime("now"))');
}


