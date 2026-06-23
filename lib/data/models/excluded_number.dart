enum ExclusionType {
  exacto,
  prefijo;

  String get databaseValue => switch (this) {
        ExclusionType.exacto => 'exacto',
        ExclusionType.prefijo => 'prefijo',
      };

  String get label => switch (this) {
        ExclusionType.exacto => 'Exacto',
        ExclusionType.prefijo => 'Prefijo',
      };

  static ExclusionType fromDatabaseValue(String value) {
    return value.toLowerCase().trim() == 'prefijo'
        ? ExclusionType.prefijo
        : ExclusionType.exacto;
  }
}

class ExcludedNumber {
  const ExcludedNumber({
    this.id,
    required this.numero,
    required this.tipo,
  });

  final int? id;
  final String numero;
  final ExclusionType tipo;

  factory ExcludedNumber.fromMap(Map<String, Object?> map) {
    return ExcludedNumber(
      id: map['id'] as int?,
      numero: (map['numero'] as String?) ?? '',
      tipo: ExclusionType.fromDatabaseValue((map['tipo'] as String?) ?? ''),
    );
  }

  Map<String, Object?> toMap() {
    return {
      if (id != null) 'id': id,
      'numero': numero,
      'tipo': tipo.databaseValue,
    };
  }
}
