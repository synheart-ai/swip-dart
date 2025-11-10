import 'package:sqflite/sqflite.dart';

class UsersRepo {
  final Database db;
  UsersRepo(this.db);

  Future<void> upsertUser(
      {required String userId, required String createdAt}) async {
    await db.insert(
      'dim_swip_users',
      {
        'user_id': userId,
        'created_datetime': createdAt,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }
}
