String formatDurationSeconds(int totalSeconds) {
  if (totalSeconds < 60) return '$totalSeconds s';

  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;

  if (hours > 0) return '${hours}h ${minutes}m ${seconds}s';
  return '${minutes}m ${seconds}s';
}

String formatCallDateOrTime({
  required String fecha,
  required String hora,
  required int timestamp,
}) {
  if (timestamp <= 0) return hora.isNotEmpty ? hora : fecha;

  final dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
  final now = DateTime.now();
  final isToday = dateTime.year == now.year &&
      dateTime.month == now.month &&
      dateTime.day == now.day;

  if (isToday) return _formatSpanishAmPm(dateTime);

  final difference = DateTime(now.year, now.month, now.day)
      .difference(DateTime(dateTime.year, dateTime.month, dateTime.day))
      .inDays;

  if (difference >= 0 && difference <= 6) {
    const weekdays = <String>[
      'MONDAY',
      'TUESDAY',
      'WEDNESDAY',
      'THURSDAY',
      'FRIDAY',
      'SATURDAY',
      'SUNDAY',
    ];
    return weekdays[dateTime.weekday - 1];
  }

  if (fecha.isNotEmpty) return fecha;
  return '${dateTime.day.toString().padLeft(2, '0')}/'
      '${dateTime.month.toString().padLeft(2, '0')}/'
      '${dateTime.year}';
}

String _formatSpanishAmPm(DateTime value) {
  final hour12 = value.hour % 12 == 0 ? 12 : value.hour % 12;
  final minute = value.minute.toString().padLeft(2, '0');
  final suffix = value.hour < 12 ? 'a.m.' : 'p.m.';
  return '$hour12:$minute $suffix';
}
