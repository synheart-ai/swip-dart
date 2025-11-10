import 'package:sqflite/sqflite.dart';

class ConsentsRepo {
  final Database db;
  ConsentsRepo(this.db);

  Future<void> upsertConsent({
    required String userId,
    required String type,
    required String status,
  }) async {
    await db.insert(
      'dim_swip_users_consent',
      {
        'user_id': userId,
        'type': type,
        'created_datetime': DateTime.now().toUtc().toIso8601String(),
        'status': status,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> getConsentStatus({
    required String userId,
    required String type,
  }) async {
    final result = await db.query(
      'dim_swip_users_consent',
      where: 'user_id = ? AND type = ?',
      whereArgs: [userId, type],
      orderBy: 'created_datetime DESC',
      limit: 1,
    );

    if (result.isEmpty) return null;
    return result.first['status'] as String?;
  }
}

