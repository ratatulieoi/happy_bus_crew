class Bus {
  final String name;
  final String plate;

  const Bus({required this.name, required this.plate});
}

const busCatalog = [
  Bus(name: 'HG 2', plate: 'AB 7317 BK'),
  Bus(name: 'HG 3', plate: 'AB 7402 BK'),
  Bus(name: 'HG 4', plate: 'AB 7403 BK'),
  Bus(name: 'HG 5', plate: 'AB 7454 BK'),
  Bus(name: 'HG 6', plate: 'AB 7497 BK'),
];

/// Reports store the plate; names always come from the fixed catalog.
String busNameForPlate(String plate) =>
    busCatalog.firstWhere((bus) => bus.plate == plate).name;
