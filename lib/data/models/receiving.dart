class Receiving {
  final String id;
  final String receivingId;
  final String locationId;
  final String category;
  final String employeeId;
  final double totalAmount;
  final String? employeeName;
  final String? notes;
  final List<ReceivingItem>? items;
  final DateTime timestamp;

  Receiving({
    required this.id,
    required this.receivingId,
    required this.locationId,
    required this.category,
    required this.employeeId,
    required this.totalAmount,
    this.employeeName,
    this.notes,
    this.items,
    required this.timestamp,
  });

  factory Receiving.fromJson(Map<String, dynamic> json) {
    return Receiving(
      id: json['id'],
      receivingId: json['receiving_id'],
      locationId: json['location_id'],
      category: json['category'],
      employeeId: json['employee_id'],
      totalAmount: (json['total_amount'] as num).toDouble(),
      employeeName: json['employee_name'],
      notes: json['notes'],
      items: json['items'] != null
          ? (json['items'] as List)
                .map((i) => ReceivingItem.fromJson(i))
                .toList()
          : null,
      timestamp: DateTime.parse(json['timestamp']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'receiving_id': receivingId,
      'location_id': locationId,
      'category': category,
      'employee_id': employeeId,
      'total_amount': totalAmount,
      'employee_name': employeeName,
      'notes': notes,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}

class ReceivingItem {
  final String id;
  final String receivingId;
  final String itemId;
  final String itemName;
  final double quantity;
  final double buyingPrice;
  final double subtotal;

  ReceivingItem({
    required this.id,
    required this.receivingId,
    required this.itemId,
    required this.itemName,
    required this.quantity,
    required this.buyingPrice,
    required this.subtotal,
  });

  factory ReceivingItem.fromJson(Map<String, dynamic> json) {
    return ReceivingItem(
      id: json['id'],
      receivingId: json['receiving_id'],
      itemId: json['item_id'],
      itemName: json['item_name'],
      quantity: (json['quantity'] as num).toDouble(),
      buyingPrice: (json['buying_price'] as num).toDouble(),
      subtotal: (json['subtotal'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'receiving_id': receivingId,
      'item_id': itemId,
      'item_name': itemName,
      'quantity': quantity,
      'buying_price': buyingPrice,
      'subtotal': subtotal,
    };
  }
}
