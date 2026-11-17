class Location {
  final String id;
  final String name;
  final String? address;
  final String? phone;
  final String? email;
  final String? tillNumber;
  final String? paybillNumber;
  final String? logoUrl;
  final String? logoLocalPath;
  final int agoPumps;
  final int pmsPumps;
  final bool isActive;
  final DateTime createdAt;

  Location({
    required this.id,
    required this.name,
    this.address,
    this.phone,
    this.email,
    this.tillNumber,
    this.paybillNumber,
    this.logoUrl,
    this.logoLocalPath,
    required this.agoPumps,
    required this.pmsPumps,
    required this.isActive,
    required this.createdAt,
  });

  factory Location.fromJson(Map<String, dynamic> json) {
    return Location(
      id: json['id'],
      name: json['name'],
      address: json['address'],
      phone: json['phone'],
      email: json['email'],
      tillNumber: json['till_number'],
      paybillNumber: json['paybill_number'],
      logoUrl: json['logo_url'],
      logoLocalPath: json['logo_local_path'],
      agoPumps: json['ago_pumps'] ?? 0,
      pmsPumps: json['pms_pumps'] ?? 0,
      isActive: json['is_active'] ?? true,
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'address': address,
      'phone': phone,
      'email': email,
      'till_number': tillNumber,
      'paybill_number': paybillNumber,
      'logo_url': logoUrl,
      'logo_local_path': logoLocalPath,
      'ago_pumps': agoPumps,
      'pms_pumps': pmsPumps,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
    };
  }

  Location copyWith({
    String? id,
    String? name,
    String? address,
    String? phone,
    String? email,
    String? tillNumber,
    String? paybillNumber,
    String? logoUrl,
    String? logoLocalPath,
    int? agoPumps,
    int? pmsPumps,
    bool? isActive,
    DateTime? createdAt,
  }) {
    return Location(
      id: id ?? this.id,
      name: name ?? this.name,
      address: address ?? this.address,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      tillNumber: tillNumber ?? this.tillNumber,
      paybillNumber: paybillNumber ?? this.paybillNumber,
      logoUrl: logoUrl ?? this.logoUrl,
      logoLocalPath: logoLocalPath ?? this.logoLocalPath,
      agoPumps: agoPumps ?? this.agoPumps,
      pmsPumps: pmsPumps ?? this.pmsPumps,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
