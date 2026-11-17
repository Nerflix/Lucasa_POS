class Customer {
  final String id;
  final String locationId;
  final String category;
  final String firstName;
  final String lastName;
  final String phone;
  final DateTime createdAt;

  Customer({
    required this.id,
    required this.locationId,
    required this.category,
    required this.firstName,
    required this.lastName,
    required this.phone,
    required this.createdAt,
  });

  factory Customer.fromJson(Map<String, dynamic> json) {
    return Customer(
      id: json['id'],
      locationId: json['location_id'],
      category: json['category'],
      firstName: json['first_name'],
      lastName: json['last_name'],
      phone: json['phone'],
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'location_id': locationId,
      'category': category,
      'first_name': firstName,
      'last_name': lastName,
      'phone': phone,
      'created_at': createdAt.toIso8601String(),
    };
  }

  Customer copyWith({
    String? id,
    String? locationId,
    String? category,
    String? firstName,
    String? lastName,
    String? phone,
    DateTime? createdAt,
  }) {
    return Customer(
      id: id ?? this.id,
      locationId: locationId ?? this.locationId,
      category: category ?? this.category,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      phone: phone ?? this.phone,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

class Credit {
  final String id;
  final String customerId;
  final String saleId;
  final String locationId;
  final String category;
  final double totalOwed;
  final double amountPaid;
  final double balance;
  final DateTime createdAt;
  final DateTime? lastPaymentAt;

  Credit({
    required this.id,
    required this.customerId,
    required this.saleId,
    required this.locationId,
    required this.category,
    required this.totalOwed,
    required this.amountPaid,
    required this.balance,
    required this.createdAt,
    this.lastPaymentAt,
  });

  factory Credit.fromJson(Map<String, dynamic> json) {
    return Credit(
      id: json['id'],
      customerId: json['customer_id'],
      saleId: json['sale_id'],
      locationId: json['location_id'],
      category: json['category'],
      totalOwed: (json['total_owed'] as num).toDouble(),
      amountPaid: (json['amount_paid'] as num).toDouble(),
      balance: (json['balance'] as num).toDouble(),
      createdAt: DateTime.parse(json['created_at']),
      lastPaymentAt: json['last_payment_at'] != null
          ? DateTime.parse(json['last_payment_at'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'customer_id': customerId,
      'sale_id': saleId,
      'location_id': locationId,
      'category': category,
      'total_owed': totalOwed,
      'amount_paid': amountPaid,
      'balance': balance,
      'created_at': createdAt.toIso8601String(),
      'last_payment_at': lastPaymentAt?.toIso8601String(),
    };
  }
}

class CreditPayment {
  final String id;
  final String creditId;
  final double amount;
  final DateTime paidAt;

  CreditPayment({
    required this.id,
    required this.creditId,
    required this.amount,
    required this.paidAt,
  });

  factory CreditPayment.fromJson(Map<String, dynamic> json) {
    return CreditPayment(
      id: json['id'],
      creditId: json['credit_id'],
      amount: (json['amount'] as num).toDouble(),
      paidAt: DateTime.parse(json['paid_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'credit_id': creditId,
      'amount': amount,
      'paid_at': paidAt.toIso8601String(),
    };
  }
}
