class SaleAuditLog {
  final String id;
  final String action; // 'DELETE' or 'EDIT'
  final String saleId; // human-readable receipt ID (e.g. RCP-00123)
  final String performedBy; // employee name
  final DateTime performedAt;
  final String? locationId;
  final String? category;
  final Map<String, dynamic> snapshot; // full sale + items at time of action

  SaleAuditLog({
    required this.id,
    required this.action,
    required this.saleId,
    required this.performedBy,
    required this.performedAt,
    this.locationId,
    this.category,
    required this.snapshot,
  });

  factory SaleAuditLog.fromJson(Map<String, dynamic> json) {
    return SaleAuditLog(
      id: json['id'],
      action: json['action'],
      saleId: json['sale_id'],
      performedBy: json['performed_by'],
      performedAt: DateTime.parse(json['performed_at']),
      locationId: json['location_id'],
      category: json['category'],
      snapshot: Map<String, dynamic>.from(json['snapshot'] ?? {}),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'action': action,
      'sale_id': saleId,
      'performed_by': performedBy,
      'performed_at': performedAt.toIso8601String(),
      'location_id': locationId,
      'category': category,
      'snapshot': snapshot,
    };
  }
}
