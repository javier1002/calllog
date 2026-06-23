import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

class CapsuleService {
  static String get _base => 'https://api.capsulecrm.com/api/v2';
  static String get _apiKey => dotenv.env['CAPSULE_API_KEY'] ?? '';

  static Map<String, String> get _headers => {
    'Authorization': 'Bearer $_apiKey',
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  /// Extrae los últimos 10 dígitos del número (sin código de país).
  static String _last10Digits(String phoneNumber) {
    final soloDigitos = phoneNumber.replaceAll(RegExp(r'[^0-9]'), '');
    if (soloDigitos.length <= 10) return soloDigitos;
    return soloDigitos.substring(soloDigitos.length - 10);
  }

  /// Busca un contacto EXISTENTE en Capsule por número de teléfono.
  static Future<Map<String, dynamic>?> findContactByPhone(String phoneNumber) async {
    try {
      final numeroLimpio = _last10Digits(phoneNumber);

      final uri = Uri.parse('$_base/parties/search')
          .replace(queryParameters: {'q': numeroLimpio});
      final res = await http.get(uri, headers: _headers);

      print('🔍 Buscando "$numeroLimpio" → status: ${res.statusCode}');

      if (res.statusCode != 200) {
        print('   Body: ${res.body}');
        return null;
      }

      final data = jsonDecode(res.body);
      final parties = data['parties'] as List? ?? [];
      print('   📋 Resultados: ${parties.length}');

      Map<String, dynamic>? match;
      for (final p in parties) {
        final phones = (p['phoneNumbers'] as List?) ?? [];
        for (final ph in phones) {
          final guardado = _last10Digits(ph['number'] as String? ?? '');
          if (guardado == numeroLimpio && numeroLimpio.isNotEmpty) {
            match = p as Map<String, dynamic>;
            break;
          }
        }
        if (match != null) break;
      }

      if (match == null) {
        print('   ⛔ No tiene ese número exacto en Capsule — se omite');
        return null;
      }

      final name = match['type'] == 'organisation'
          ? (match['name'] ?? '')
          : '${match['firstName'] ?? ''} ${match['lastName'] ?? ''}'.trim();

      print('   ✅ Encontrado: id ${match['id']}, $name');
      return {'id': match['id'], 'name': name};
    } catch (e) {
      print('❌ Error buscando contacto: $e');
      return null;
    }
  }

  /// Busca la oportunidad YA CREADA MANUALMENTE para este contacto.
  static Future<int?> findManualCallOpportunity(int partyId) async {
    try {
      print('   🔎 Buscando oportunidades para partyId: $partyId');
      final res = await http.get(
        Uri.parse('$_base/parties/$partyId/opportunities'),
        headers: _headers,
      );
      if (res.statusCode != 200) return null;

      final data = jsonDecode(res.body);
      final opportunities = data['opportunities'] as List? ?? [];
      print('   📋 Oportunidades encontradas: ${opportunities.length}');
      for (final o in opportunities) {
        print('      - id: ${o['id']}, name: ${o['name']}');
      }

      if (opportunities.isEmpty) {
        print('   ⛔ El contacto existe pero no tiene oportunidad creada manualmente — se omite');
        return null;
      }

      return opportunities.first['id'] as int?;
    } catch (e) {
      print('❌ Error buscando oportunidad: $e');
      return null;
    }
  }

  /// Agrega la llamada como nota dentro de la oportunidad ya existente.
  static Future<bool> addCallToOpportunity({
    required int opportunityId,
    required String phoneNumber,
    required String fecha,
    required String hora,
    required int duracion,
    required String estado,
  }) async {
    try {
      final durationText = duracion > 0
          ? '${duracion ~/ 60}m ${duracion % 60}s'
          : 'No respondida';

      final payload = {
        'entry': {
          'type': 'note',
          'content': ' Llamada saliente\n'
              ' $phoneNumber\n'
              ' $fecha   $hora\n'
              ' Duración: $durationText\n'
              ' Estado: $estado',
          'opportunity': {'id': opportunityId},
        }
      };

      final res = await http.post(
        Uri.parse('$_base/entries'),
        headers: _headers,
        body: jsonEncode(payload),
      );

      print('📝 Agregar nota a oportunidad $opportunityId → ${res.statusCode}');
      if (res.statusCode < 200 || res.statusCode >= 300) {
        print('❌ Error: ${res.body}');
      }
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (e) {
      print('❌ Exception: $e');
      return false;
    }
  }

  /// Flujo completo.
  static Future<bool> syncCallToOpportunity({
    required String phoneNumber,
    required String fecha,
    required String hora,
    required int duracion,
    required String estado,
  }) async {
    final contact = await findContactByPhone(phoneNumber);
    if (contact == null) return false;

    final partyId = contact['id'] as int;
    final opportunityId = await findManualCallOpportunity(partyId);
    if (opportunityId == null) return false;

    return addCallToOpportunity(
      opportunityId: opportunityId,
      phoneNumber: phoneNumber,
      fecha: fecha,
      hora: hora,
      duracion: duracion,
      estado: estado,
    );
  }
}