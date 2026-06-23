import 'package:sqflite/sqflite.dart';

import '../../core/database/app_database.dart';
import '../../utils/text_normalizer.dart';
import '../models/outgoing_call.dart';

class CallsRepository {
  Future<List<OutgoingCall>> getAll() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'llamadas_salientes',
      orderBy: 'timestamp DESC, id DESC',
    );
    return rows.map(OutgoingCall.fromMap).toList();
  }

  Future<List<OutgoingCall>> search(String query) async {
    final cleanQuery = normalizeSearch(query);
    if (cleanQuery.isEmpty) return getAll();

    final calls = await getAll();

    return calls.where((call) {
      final searchableText = [
        call.nombreContacto,
        call.numero,
        call.estado,
        call.fecha,
        call.hora,
        call.duracion.toString(),
      ].map(normalizeSearch).join(' ');

      return searchableText.contains(cleanQuery) ||
          phoneMatchesIgnoringColombianCode(
            storedNumber: call.numero,
            query: query,
          );
    }).toList();
  }

  Future<bool> existsByTimestampAndNumber({
    required int timestamp,
    required String numero,
  }) async {
    final db = await AppDatabase.instance.database;
    final cleanNumber = normalizeSpaces(numero);

    final rows = await db.query(
      'llamadas_salientes',
      columns: ['id'],
      where: 'timestamp = ? AND numero = ?',
      whereArgs: [timestamp, cleanNumber],
      limit: 1,
    );

    return rows.isNotEmpty;
  }

  Future<int> insert(OutgoingCall call) async {
    final db = await AppDatabase.instance.database;
    return db.insert(
      'llamadas_salientes',
      call.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<int> deleteById(int id) async {
    final db = await AppDatabase.instance.database;
    return db.delete(
      'llamadas_salientes',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteByNumber(String numero) async {
    final db = await AppDatabase.instance.database;
    return db.delete(
      'llamadas_salientes',
      where: 'numero = ?',
      whereArgs: [numero],
    );
  }

  Future<int> countByNumber(String numero) async {
    final db = await AppDatabase.instance.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS total FROM llamadas_salientes WHERE numero = ?',
      [numero],
    );
    return (result.first['total'] as int?) ?? 0;
  }

  Future<int> clear() async {
    final db = await AppDatabase.instance.database;
    return db.delete('llamadas_salientes');
  }
}
