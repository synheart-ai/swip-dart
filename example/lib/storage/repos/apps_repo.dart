import 'package:sqflite/sqflite.dart';

class AppsRepo {
  final Database db;
  AppsRepo(this.db);

  Future<void> upsertApp({
    required String appId,
    String? appName,
    String? appVersion,
    String? category,
    String? developer,
  }) async {
    await db.insert(
      'dim_app',
      {
        'app_id': appId,
        'app_name': appName,
        'app_version': appVersion,
        'category': category,
        'developer': developer,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }
}

