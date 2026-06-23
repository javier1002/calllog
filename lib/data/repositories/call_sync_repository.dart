import '../../core/platform/call_log_channel.dart';
import '../../utils/text_normalizer.dart';
import '../models/outgoing_call.dart';
import 'calls_repository.dart';
import 'exclusions_repository.dart';

class CallSyncResult {
  const CallSyncResult({
    required this.totalRead,
    required this.inserted,
    required this.skippedExcluded,
    required this.skippedDuplicated,
  });

  final int totalRead;
  final int inserted;
  final int skippedExcluded;
  final int skippedDuplicated;
}

class CallSyncRepository {
  CallSyncRepository({
    CallLogChannel? callLogChannel,
    CallsRepository? callsRepository,
    ExclusionsRepository? exclusionsRepository,
  })  : _callLogChannel = callLogChannel ?? CallLogChannel(),
        _callsRepository = callsRepository ?? CallsRepository(),
        _exclusionsRepository = exclusionsRepository ?? ExclusionsRepository();

  final CallLogChannel _callLogChannel;
  final CallsRepository _callsRepository;
  final ExclusionsRepository _exclusionsRepository;

  Future<CallSyncResult> syncTodayOutgoingCalls() async {
    final granted = await _callLogChannel.requestCallPermissions();

    if (!granted) {
      throw Exception('Permisos de llamadas y contactos no concedidos.');
    }

    final now = DateTime.now();
    final startOfDay = DateTime(
      now.year,
      now.month,
      now.day,
    );

    final nativeCalls = await _callLogChannel.getOutgoingCalls(
      from: startOfDay,
      to: now,
    );

    var inserted = 0;
    var skippedExcluded = 0;
    var skippedDuplicated = 0;

    for (final call in nativeCalls) {
      final cleanNumber = normalizeSpaces(call.numero);

      if (cleanNumber.isEmpty) continue;

      final isExcluded = await _exclusionsRepository.isNumberExcluded(
        cleanNumber,
      );

      if (isExcluded) {
        skippedExcluded++;
        continue;
      }

      final exists = await _callsRepository.existsByTimestampAndNumber(
        timestamp: call.timestamp,
        numero: cleanNumber,
      );

      if (exists) {
        skippedDuplicated++;
        continue;
      }

      final cleanCall = OutgoingCall(
        fecha: call.fecha,
        hora: call.hora,
        numero: cleanNumber,
        nombreContacto: normalizeSpaces(call.nombreContacto),
        duracion: call.duracion,
        estado: call.estado,
        timestamp: call.timestamp,
      );

      final id = await _callsRepository.insert(cleanCall);

      if (id > 0) {
        inserted++;
      } else {
        skippedDuplicated++;
      }
    }

    return CallSyncResult(
      totalRead: nativeCalls.length,
      inserted: inserted,
      skippedExcluded: skippedExcluded,
      skippedDuplicated: skippedDuplicated,
    );
  }
}
