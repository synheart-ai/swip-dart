import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'migrations/m001_init.dart' as m001;
import 'migrations/m002_add_sync_columns.dart' as m002;
import 'migrations/m003_device_sync.dart' as m003;
import 'migrations/m004_biosignal_sync.dart' as m004;
import 'migrations/m005_emotion_sync.dart' as m005;

class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  Database? _db;
  String? _dbPath;
  static const int _currentVersion = 5;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'swip_example.db');
    _dbPath = path;

    return await openDatabase(
      path,
      version: _currentVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await db.transaction((txn) async {
          await m001.apply(txn);
          if (version >= 2) await m002.apply(txn);
          if (version >= 3) await m003.apply(txn);
          if (version >= 4) await m004.apply(txn);
          if (version >= 5) await m005.apply(txn);
        });
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        await db.transaction((txn) async {
          if (oldVersion < 2) {
            await m002.apply(txn);
          }
          if (oldVersion < 3) {
            await m003.apply(txn);
          }
          if (oldVersion < 4) await m004.apply(txn);
          if (oldVersion < 5) await m005.apply(txn);
        });
      },
    );
  }

  /// Get the database file path
  Future<String> getDatabasePath() async {
    if (_dbPath != null) return _dbPath!;
    final dbPath = await getDatabasesPath();
    return p.join(dbPath, 'swip_example.db');
  }

  /// Export database to a shareable location
  /// Returns the path to the exported file
  Future<String> exportDatabase() async {
    final dbPath = await getDatabasePath();
    final dbFile = File(dbPath);

    if (!await dbFile.exists()) {
      throw Exception('Database file not found');
    }

    // Get a temporary directory (for sharing)
    final tempDir = await getTemporaryDirectory();
    final timestamp =
        DateTime.now().toIso8601String().replaceAll(':', '-').split('.')[0];
    final exportPath = p.join(tempDir.path, 'swip_example_$timestamp.db');

    // Copy database to temporary directory
    final exportFile = await dbFile.copy(exportPath);
    return exportFile.path;
  }
}
