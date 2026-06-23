import 'package:llamadas_salientes/core/database/app_database.dart';
import 'package:llamadas_salientes/services/capsule_service.dart';

class SyncResult {
  final String message;
  final int creadas;
  final int omitidas;
  final bool success;

  SyncResult({
    required this.message,
    this.creadas = 0,
    this.omitidas = 0,
    this.success = true,
  });

  @override
  String toString() => '$message (Creadas: $creadas, Omitidas: $omitidas)';
}

class CallSyncService {
  static Future<List<Map<String, dynamic>>> _getLocalCalls() async {
    final db = await AppDatabase.instance.database;
    return db.query(
      'llamadas_salientes',
      where: 'sincronizado = 0',
      orderBy: 'timestamp DESC',
    );
  }

  static Future<void> _markAsSynced(int callId) async {
    final db = await AppDatabase.instance.database;
    await db.update(
      'llamadas_salientes',
      {'sincronizado': 1},
      where: 'id = ?',
      whereArgs: [callId],
    );
  }

  static Future<SyncResult> syncCalls() async {
    print('\n🔵 INICIANDO SINCRONIZACIÓN DE LLAMADAS\n');

    try {
      final llamadas = await _getLocalCalls();
      print('📞 Sin sincronizar: ${llamadas.length}');

      if (llamadas.isEmpty) {
        return SyncResult(message: 'No hay llamadas nuevas');
      }

      int creadas = 0;
      int omitidas = 0;

      for (int i = 0; i < llamadas.length; i++) {
        final llamada = llamadas[i];
        final numero = (llamada['numero'] as String? ?? '').trim();
        final callId = llamada['id'] as int;

        print('\n📱 [${i + 1}/${llamadas.length}] $numero');

        if (numero.isEmpty) {
          omitidas++;
          continue;
        }

        try {
          final ok = await CapsuleService.syncCallToOpportunity(
            phoneNumber: numero,
            fecha: llamada['fecha'] as String? ?? '',
            hora: llamada['hora'] as String? ?? '',
            duracion: llamada['duracion'] as int? ?? 0,
            estado: llamada['estado'] as String? ?? '',
          );

          if (ok) {
            await _markAsSynced(callId);
            creadas++;
            print('   ✅ Llamada agregada');
          } else {
            // No marcamos como sincronizada si no existe el contacto,
            // por si luego lo crean en Capsule manualmente.
            omitidas++;
          }
        } catch (e) {
          print('   ❌ Exception: $e');
          omitidas++;
        }
      }

      final msg = '$creadas sincronizadas, $omitidas omitidas (no son contactos de Capsule)';
      print('\n🏁 $msg');
      return SyncResult(message: msg, creadas: creadas, omitidas: omitidas);
    } catch (e, stack) {
      print('❌ Error: $e\n$stack');
      return SyncResult(message: 'Error: $e', success: false);
    }
  }
}