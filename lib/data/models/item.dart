class Item {
  final String id;
  final String locationId;
  final String category;
  final String name;
  final String? barcode;
  final double buyingPrice;
  final double sellingPrice;
  final double wholesalePrice;
  final double quantity;
  final double reorderLevel;
  final String createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  Item({
    required this.id,
    required this.locationId,
    required this.category,
    required this.name,
    this.barcode,
    required this.buyingPrice,
    required this.sellingPrice,
    required this.wholesalePrice,
    required this.quantity,
    required this.reorderLevel,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  Item copyWith({
    String? id,
    String? locationId,
    String? category,
    String? name,
    String? barcode,
    double? buyingPrice,
    double? sellingPrice,
    double? wholesalePrice,
    double? quantity,
    double? reorderLevel,
    String? createdBy,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Item(
      id: id ?? this.id,
      locationId: locationId ?? this.locationId,
      category: category ?? this.category,
      name: name ?? this.name,
      barcode: barcode ?? this.barcode,
      buyingPrice: buyingPrice ?? this.buyingPrice,
      sellingPrice: sellingPrice ?? this.sellingPrice,
      wholesalePrice: wholesalePrice ?? this.wholesalePrice,
      quantity: quantity ?? this.quantity,
      reorderLevel: reorderLevel ?? this.reorderLevel,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory Item.fromJson(Map<String, dynamic> json) {
    return Item(
      id: json['id'],
      locationId: json['location_id'],
      category: json['category'],
      name: json['name'],
      barcode: json['barcode'],
      buyingPrice: (json['buying_price'] as num).toDouble(),
      sellingPrice: (json['selling_price'] as num).toDouble(),
      wholesalePrice: (json['wholesale_price'] as num).toDouble(),
      quantity: (json['quantity'] as num).toDouble(),
      reorderLevel: (json['reorder_level'] as num?)?.toDouble() ?? 0.0,
      createdBy: json['created_by'],
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'location_id': locationId,
      'category': category,
      'name': name,
      'barcode': barcode,
      'buying_price': buyingPrice,
      'selling_price': sellingPrice,
      'wholesale_price': wholesalePrice,
      'quantity': quantity,
      'reorder_level': reorderLevel,
      'created_by': createdBy,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}
