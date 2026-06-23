class OutgoingCall {
  const OutgoingCall({
    this.id,
    required this.fecha,
    required this.hora,
    required this.numero,
    required this.nombreContacto,
    required this.duracion,
    required this.estado,
    required this.timestamp,
  });

  final int? id;
  final String fecha;
  final String hora;
  final String numero;
  final String nombreContacto;
  final int duracion;
  final String estado;
  final int timestamp;

  factory OutgoingCall.fromMap(Map<String, Object?> map) {
    return OutgoingCall(
      id: map['id'] as int?,
      fecha: (map['fecha'] as String?) ?? '',
      hora: (map['hora'] as String?) ?? '',
      numero: (map['numero'] as String?) ?? '',
      nombreContacto: (map['nombre_contacto'] as String?) ?? '',
      duracion: (map['duracion'] as int?) ?? 0,
      estado: (map['estado'] as String?) ?? '',
      timestamp: (map['timestamp'] as int?) ?? 0,
    );
  }

  Map<String, Object?> toMap() {
    return {
      if (id != null) 'id': id,
      'fecha': fecha,
      'hora': hora,
      'numero': numero,
      'nombre_contacto': nombreContacto,
      'duracion': duracion,
      'estado': estado,
      'timestamp': timestamp,
    };
  }
}
