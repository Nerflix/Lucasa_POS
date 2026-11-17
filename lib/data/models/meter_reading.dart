class MeterReading {
  final String id;
  final String locationId;
  final String employeeId;
  final String readingType;
  final String category;
  final String pumpType;
  final int pumpNumber;
  final double valueA;
  final double valueL;
  final double valueT;
  final DateTime timestamp;

  MeterReading({
    required this.id,
    required this.locationId,
    required this.employeeId,
    required this.readingType,
    required this.category,
    required this.pumpType,
    required this.pumpNumber,
    required this.valueA,
    required this.valueL,
    required this.valueT,
    required this.timestamp,
  });

  factory MeterReading.fromJson(Map<String, dynamic> json) {
    return MeterReading(
      id: json['id'],
      locationId: json['location_id'],
      employeeId: json['employee_id'],
      readingType: json['reading_type'],
      category: json['category'],
      pumpType: json['pump_type'],
      pumpNumber: json['pump_number'],
      valueA: (json['value_a'] as num).toDouble(),
      valueL: (json['value_l'] as num).toDouble(),
      valueT: (json['value_t'] as num).toDouble(),
      timestamp: DateTime.parse(json['timestamp']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'location_id': locationId,
      'employee_id': employeeId,
      'reading_type': readingType,
      'category': category,
      'pump_type': pumpType,
      'pump_number': pumpNumber,
      'value_a': valueA,
      'value_l': valueL,
      'value_t': valueT,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  MeterReading copyWith({
    String? id,
    String? locationId,
    String? employeeId,
    String? readingType,
    String? category,
    String? pumpType,
    int? pumpNumber,
    double? valueA,
    double? valueL,
    double? valueT,
    DateTime? timestamp,
  }) {
    return MeterReading(
      id: id ?? this.id,
      locationId: locationId ?? this.locationId,
      employeeId: employeeId ?? this.employeeId,
      readingType: readingType ?? this.readingType,
      category: category ?? this.category,
      pumpType: pumpType ?? this.pumpType,
      pumpNumber: pumpNumber ?? this.pumpNumber,
      valueA: valueA ?? this.valueA,
      valueL: valueL ?? this.valueL,
      valueT: valueT ?? this.valueT,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}
