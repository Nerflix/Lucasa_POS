class Sale {
  final String id;
  final String saleId;
  final String locationId;
  final String category;
  final String employeeId;
  final String paymentMethod;
  final double totalAmount;
  final double amountPaid;
  final double changeGiven;
  final double profit;
  final bool isSuspended;
  final String? suspensionNotes;
  final String? employeeName;
  final String? notes;
  final DateTime timestamp;

  Sale({
    required this.id,
    required this.saleId,
    required this.locationId,
    required this.category,
    required this.employeeId,
    required this.paymentMethod,
    required this.totalAmount,
    required this.amountPaid,
    required this.changeGiven,
    required this.profit,
    required this.isSuspended,
    this.suspensionNotes,
    this.employeeName,
    this.notes,
    required this.timestamp,
  });

  factory Sale.fromJson(Map<String, dynamic> json) {
    return Sale(
      id: json['id'],
      saleId: json['sale_id'],
      locationId: json['location_id'],
      category: json['category'],
      employeeId: json['employee_id'],
      paymentMethod: json['payment_method'],
      totalAmount: (json['total_amount'] as num).toDouble(),
      amountPaid: (json['amount_paid'] as num).toDouble(),
      changeGiven: (json['change_given'] as num).toDouble(),
      profit: (json['profit'] as num).toDouble(),
      isSuspended: json['is_suspended'] ?? false,
      suspensionNotes: json['suspension_notes'],
      employeeName: json['employee_name'],
      notes: json['notes'],
      timestamp: DateTime.parse(json['timestamp']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sale_id': saleId,
      'location_id': locationId,
      'category': category,
      'employee_id': employeeId,
      'payment_method': paymentMethod,
      'total_amount': totalAmount,
      'amount_paid': amountPaid,
      'change_given': changeGiven,
      'profit': profit,
      'is_suspended': isSuspended,
      'suspension_notes': suspensionNotes,
      'employee_name': employeeName,
      'notes': notes,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}

class SaleItem {
  final String id;
  final String saleId;
  final String itemId;
  final String itemName;
  final double quantity;
  final double buyingPrice;
  final double sellingPrice;
  final String pricingType;
  final double subtotal;
  final double discount;

  SaleItem({
    required this.id,
    required this.saleId,
    required this.itemId,
    required this.itemName,
    required this.quantity,
    required this.buyingPrice,
    required this.sellingPrice,
    required this.pricingType,
    required this.subtotal,
    this.discount = 0,
  });

  factory SaleItem.fromJson(Map<String, dynamic> json) {
    return SaleItem(
      id: json['id'],
      saleId: json['sale_id'],
      itemId: json['item_id'],
      itemName: json['item_name'],
      quantity: (json['quantity'] as num).toDouble(),
      buyingPrice: (json['buying_price'] as num).toDouble(),
      sellingPrice: (json['selling_price'] as num).toDouble(),
      pricingType: json['pricing_type'],
      subtotal: (json['subtotal'] as num).toDouble(),
      discount: (json['discount'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sale_id': saleId,
      'item_id': itemId,
      'item_name': itemName,
      'quantity': quantity,
      'buying_price': buyingPrice,
      'selling_price': sellingPrice,
      'pricing_type': pricingType,
      'subtotal': subtotal,
      'discount': discount,
    };
  }

  SaleItem copyWith({
    String? id,
    String? saleId,
    String? itemId,
    String? itemName,
    double? quantity,
    double? buyingPrice,
    double? sellingPrice,
    String? pricingType,
    double? subtotal,
    double? discount,
  }) {
    return SaleItem(
      id: id ?? this.id,
      saleId: saleId ?? this.saleId,
      itemId: itemId ?? this.itemId,
      itemName: itemName ?? this.itemName,
      quantity: quantity ?? this.quantity,
      buyingPrice: buyingPrice ?? this.buyingPrice,
      sellingPrice: sellingPrice ?? this.sellingPrice,
      pricingType: pricingType ?? this.pricingType,
      subtotal: subtotal ?? this.subtotal,
      discount: discount ?? this.discount,
    );
  }
}
