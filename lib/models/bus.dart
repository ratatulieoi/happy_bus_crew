class Bus {
  final int id;
  final String name;
  final String plate;

  const Bus({required this.id, required this.name, required this.plate});

  factory Bus.fromMap(Map<String, Object?> map) => Bus(
        id: map['id'] as int,
        name: map['name'] as String,
        plate: map['plate'] as String,
      );
}
