class Bus {
  final String name;
  final String plate;

  const Bus({required this.name, required this.plate});
}

const busCatalog = [
  Bus(name: 'HG2', plate: 'AB 7317 BK'),
  Bus(name: 'HG3', plate: 'AB 7402 BK'),
  Bus(name: 'HG4', plate: 'AB 7403 BK'),
  Bus(name: 'HG5', plate: 'AB 7454 BK'),
  Bus(name: 'HG6', plate: 'AB 7497 BK'),
  Bus(name: 'HC1', plate: 'AB 1669 SV'),
  Bus(name: 'HC2', plate: 'AB 1779 KP'),
  Bus(name: 'HC3', plate: 'AB 1097 DF'),
];

/// Reports store the plate; names always come from the fixed catalog.
String busNameForPlate(String plate) {
  for (final bus in busCatalog) {
    if (bus.plate == plate) return bus.name;
  }
  return plate;
}
