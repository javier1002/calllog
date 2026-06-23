import 'package:flutter/services.dart';

import '../../data/models/outgoing_call.dart';
import '../../utils/text_normalizer.dart';

class CallLogChannel {
  static const MethodChannel _channel = MethodChannel(
    'registro_llamadas/call_log',
  );

  Future<bool> requestCallPermissions() async {
    final granted = await _channel.invokeMethod<bool>(
      'requestCallPermissions',
    );

    return granted ?? false;
  }

  Future<List<OutgoingCall>> getOutgoingCalls({
    required DateTime from,
    required DateTime to,
  }) async {
    final result = await _channel.invokeMethod<List<dynamic>>(
      'getOutgoingCalls',
      {
        'from': from.millisecondsSinceEpoch,
        'to': to.millisecondsSinceEpoch,
      },
    );

    final rows = result ?? [];

    return rows.map((item) {
      final map = Map<String, dynamic>.from(item as Map);

      return OutgoingCall(
        fecha: (map['fecha'] as String?) ?? '',
        hora: (map['hora'] as String?) ?? '',
        numero: normalizeSpaces((map['numero'] as String?) ?? ''),
        nombreContacto: normalizeSpaces(
          (map['nombre_contacto'] as String?) ?? '',
        ),
        duracion: (map['duracion'] as num?)?.toInt() ?? 0,
        estado: (map['estado'] as String?) ?? 'Desconocida',
        timestamp: (map['timestamp'] as num?)?.toInt() ?? 0,
      );
    }).toList();
  }
}
