import 'package:sqflite/sqflite.dart';

import '../../core/database/app_database.dart';
import '../../utils/text_normalizer.dart';
import '../models/excluded_number.dart';

class ExclusionsRepository {
  Future<List<ExcludedNumber>> getAll() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'numeros_excluidos',
      orderBy: 'id DESC',
    );
    return rows.map(ExcludedNumber.fromMap).toList();
  }

  Future<List<ExcludedNumber>> search(String query) async {
    final cleanQuery = normalizeSearch(query);
    if (cleanQuery.isEmpty) return getAll();

    final rules = await getAll();

    return rules.where((rule) {
      final searchableText = [
        rule.numero,
        rule.tipo.databaseValue,
        rule.tipo.label,
      ].map(normalizeSearch).join(' ');

      return searchableText.contains(cleanQuery) ||
          phoneMatchesIgnoringColombianCode(
            storedNumber: rule.numero,
            query: query,
          );
    }).toList();
  }

  Future<bool> exists({
    required String numero,
    required ExclusionType tipo,
  }) async {
    final db = await AppDatabase.instance.database;
    final cleanNumber = normalizeSpaces(numero);
    final rows = await db.query(
      'numeros_excluidos',
      columns: ['id'],
      where: 'numero = ? AND tipo = ?',
      whereArgs: [cleanNumber, tipo.databaseValue],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<bool> isNumberExcluded(String numero) async {
    final cleanNumber = phoneDigitsOnly(numero);
    final cleanNumberWithoutCode = normalizeColombianPhoneForSearch(numero);

    if (cleanNumber.isEmpty && cleanNumberWithoutCode.isEmpty) {
      return false;
    }

    final rules = await getAll();

    for (final rule in rules) {
      final ruleNumber = phoneDigitsOnly(rule.numero);
      final ruleNumberWithoutCode = normalizeColombianPhoneForSearch(rule.numero);

      if (ruleNumber.isEmpty && ruleNumberWithoutCode.isEmpty) {
        continue;
      }

      switch (rule.tipo) {
        case ExclusionType.exacto:
          if (cleanNumber == ruleNumber ||
              cleanNumberWithoutCode == ruleNumber ||
              cleanNumber == ruleNumberWithoutCode ||
              cleanNumberWithoutCode == ruleNumberWithoutCode) {
            return true;
          }
          break;

        case ExclusionType.prefijo:
          if (cleanNumber.startsWith(ruleNumber) ||
              cleanNumberWithoutCode.startsWith(ruleNumber) ||
              cleanNumber.startsWith(ruleNumberWithoutCode) ||
              cleanNumberWithoutCode.startsWith(ruleNumberWithoutCode)) {
            return true;
          }
          break;
      }
    }

    return false;
  }

  Future<int> insert({
    required String numero,
    required ExclusionType tipo,
  }) async {
    final db = await AppDatabase.instance.database;
    final cleanNumber = normalizeSpaces(numero);
    return db.insert(
      'numeros_excluidos',
      {
        'numero': cleanNumber,
        'tipo': tipo.databaseValue,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<int> deleteById(int id) async {
    final db = await AppDatabase.instance.database;
    return db.delete(
      'numeros_excluidos',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
