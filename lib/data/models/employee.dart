import 'dart:convert';

class Employee {
  final String id;
  final String? locationId;
  final String role;
  final String firstName;
  final String? middleName;
  final String surname;
  final String phone;
  final String email;
  final String username;
  final String passwordHash;
  final String? permissions;
  final bool isActive;
  final DateTime createdAt;
  final DateTime? updatedAt;

  Employee({
    required this.id,
    this.locationId,
    required this.role,
    required this.firstName,
    this.middleName,
    required this.surname,
    required this.phone,
    required this.email,
    required this.username,
    required this.passwordHash,
    this.permissions,
    required this.isActive,
    required this.createdAt,
    this.updatedAt,
  });

  factory Employee.fromJson(Map<String, dynamic> json) {
    return Employee(
      id: json['id'],
      locationId: json['location_id'],
      role: json['role'],
      firstName: json['first_name'],
      middleName: json['middle_name'],
      surname: json['surname'],
      phone: json['phone'],
      email: json['email'],
      username: json['username'],
      passwordHash: json['password_hash'],
      permissions: json['permissions'] is Map
          ? jsonEncode(json['permissions'])
          : json['permissions'],
      isActive: json['is_active'] ?? true,
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'location_id': locationId,
      'role': role,
      'first_name': firstName,
      'middle_name': middleName,
      'surname': surname,
      'phone': phone,
      'email': email,
      'username': username,
      'password_hash': passwordHash,
      'permissions': permissions != null ? jsonDecode(permissions!) : null,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  Employee copyWith({
    String? id,
    String? locationId,
    String? role,
    String? firstName,
    String? middleName,
    String? surname,
    String? phone,
    String? email,
    String? username,
    String? passwordHash,
    String? permissions,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Employee(
      id: id ?? this.id,
      locationId: locationId ?? this.locationId,
      role: role ?? this.role,
      firstName: firstName ?? this.firstName,
      middleName: middleName ?? this.middleName,
      surname: surname ?? this.surname,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      username: username ?? this.username,
      passwordHash: passwordHash ?? this.passwordHash,
      permissions: permissions ?? this.permissions,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
