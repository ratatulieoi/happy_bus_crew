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

/// Reports keep only a plate, so the saved name is resolved when it is read.
/// Renaming a bus never rewrites the reports that used it.
String busNameForPlate(List<Bus> buses, String plate) {
  final clean = plate.trim().toUpperCase();
  for (final bus in buses) {
    if (bus.plate.trim().toUpperCase() == clean) return bus.name;
  }
  return '';
}
