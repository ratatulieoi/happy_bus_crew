/// Stable expense keys, independent of display labels or extra row positions.
enum ExpenseType {
  officeBbm('office_bbm'),
  officeMeal('office_meal'),
  officeExtra('office_extra'),
  discovaTol('discova_tol'),
  discovaCrossing('discova_crossing'),
  discovaParking('discova_parking'),
  discovaExtra('discova_extra');

  final String value;
  const ExpenseType(this.value);

  bool get isExtra =>
      this == ExpenseType.officeExtra || this == ExpenseType.discovaExtra;
}

class ExpenseOwner {
  final ExpenseType type;
  final String? extraId;

  const ExpenseOwner(this.type, {this.extraId})
      : assert((type == ExpenseType.officeExtra ||
                type == ExpenseType.discovaExtra)
            ? extraId != null && extraId != ''
            : extraId == null);

  @override
  bool operator ==(Object other) =>
      other is ExpenseOwner && type == other.type && extraId == other.extraId;

  @override
  int get hashCode => Object.hash(type, extraId);
}

/// A draft or saved photo. Unowned photos from older reports stay unassigned.
/// Removing a draft entry never deletes the file at [filePath].
class ReportAttachment {
  final String filePath;
  final ExpenseOwner? owner;

  const ReportAttachment({required this.filePath, this.owner});

  ReportAttachment withPath(String path) =>
      ReportAttachment(filePath: path, owner: owner);

  Map<String, Object?> toMap() => {
        'file_path': filePath,
        'expense_type': owner?.type.value,
        'extra_id': owner?.extraId,
      };

  factory ReportAttachment.fromMap(Map<String, Object?> map) {
    final value = map['expense_type'];
    ExpenseOwner? owner;
    if (value != null) {
      final type = ExpenseType.values.firstWhere((type) => type.value == value,
          orElse: () => throw const FormatException('Invalid expense type'));
      final extraId = map['extra_id'];
      if (type.isExtra
          ? extraId is! String || extraId.isEmpty
          : extraId != null) {
        throw const FormatException('Invalid expense identity');
      }
      owner = ExpenseOwner(type, extraId: extraId as String?);
    }
    return ReportAttachment(filePath: map['file_path'] as String, owner: owner);
  }

  @override
  bool operator ==(Object other) =>
      other is ReportAttachment &&
      filePath == other.filePath &&
      owner == other.owner;

  @override
  int get hashCode => Object.hash(filePath, owner);
}
