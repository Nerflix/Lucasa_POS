import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/constants/app_constants.dart';
import '../core/theme/app_theme.dart';
import '../data/database/app_database.dart';
import '../data/models/location.dart';

/// Professional receipt template for printing
/// Maintains app theme: Orange, Black, White
class ReceiptTemplate extends StatelessWidget {
  final Location location;
  final String receiptType; // 'SALE' or 'RECEIVING'
  final String receiptId;
  final DateTime timestamp;
  final String employeeName;
  final List<ReceiptItem> items;
  final String? paymentMethod;
  final double totalAmount;
  final double? amountPaid;
  final double? changeGiven;
  final double? outstandingBalance;
  final String? notes;

  const ReceiptTemplate({
    super.key,
    required this.location,
    required this.receiptType,
    required this.receiptId,
    required this.timestamp,
    required this.employeeName,
    required this.items,
    this.paymentMethod,
    required this.totalAmount,
    this.amountPaid,
    this.changeGiven,
    this.outstandingBalance,
    this.notes,
  });

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd MMM yyyy, hh:mm a');

    return Container(
      width: 380, // 80mm thermal printer width
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Header with orange accent
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AppTheme.primaryOrange, width: 2),
              ),
            ),
            child: Column(
              children: [
                // Logo placeholder (if available)
                if (location.logoUrl != null && location.logoUrl!.isNotEmpty)
                  Container(
                    height: 60,
                    width: 60,
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: AppTheme.primaryOrange,
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.network(
                        location.logoUrl!,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) =>
                            const Icon(
                              Icons.store,
                              size: 40,
                              color: AppTheme.primaryOrange,
                            ),
                      ),
                    ),
                  ),

                // Shop name
                Text(
                  location.name,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryBlack,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 4),

                // Address
                if (location.address != null && location.address!.isNotEmpty)
                  Text(
                    location.address!,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.darkGray,
                    ),
                    textAlign: TextAlign.center,
                  ),

                // Contact info
                if (location.phone != null && location.phone!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'Tel: ${location.phone}',
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppTheme.darkGray,
                      ),
                    ),
                  ),

                if (location.email != null && location.email!.isNotEmpty)
                  Text(
                    location.email!,
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppTheme.darkGray,
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Receipt type badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.primaryOrange,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              receiptType,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 1.2,
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Receipt details
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.lightGray,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Column(
              children: [
                _buildDetailRow('Receipt No:', receiptId),
                _buildDetailRow('Date:', dateFormat.format(timestamp)),
                _buildDetailRow('Cashier:', employeeName),
                if (paymentMethod != null)
                  _buildDetailRow('Payment:', paymentMethod!),
                if (paymentMethod == AppConstants.paymentCredit)
                  _buildDetailRow('Sale Type:', 'Credit'),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Divider
          Container(height: 1, color: AppTheme.primaryBlack),

          const SizedBox(height: 8),

          // Items header
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                const Expanded(
                  flex: 3,
                  child: Text(
                    'ITEM',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryBlack,
                    ),
                  ),
                ),
                const Expanded(
                  flex: 1,
                  child: Text(
                    'QTY',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryBlack,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const Expanded(
                  flex: 2,
                  child: Text(
                    'PRICE',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryBlack,
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
                const SizedBox(width: 4),
                const Expanded(
                  flex: 2,
                  child: Text(
                    'TOTAL',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryBlack,
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          ),

          Container(height: 1, color: AppTheme.mediumGray),

          const SizedBox(height: 4),

          // Items list
          ...items
              .map(
                (item) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: Text(
                          item.name,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppTheme.primaryBlack,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 1,
                        child: Text(
                          item.quantity.toStringAsFixed(
                            item.quantity.truncateToDouble() == item.quantity
                                ? 0
                                : 2,
                          ),
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppTheme.primaryBlack,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          'KES ${item.price.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppTheme.primaryBlack,
                          ),
                          textAlign: TextAlign.right,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        flex: 2,
                        child: Text(
                          'KES ${item.total.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.primaryBlack,
                          ),
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),

          const SizedBox(height: 8),

          // Divider
          Container(height: 1, color: AppTheme.primaryBlack),

          const SizedBox(height: 8),

          // Total section
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.primaryBlack,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'TOTAL AMOUNT:',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      'KES ${totalAmount.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryOrange,
                      ),
                    ),
                  ],
                ),

                if (amountPaid != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Amount Paid:',
                        style: TextStyle(fontSize: 12, color: Colors.white),
                      ),
                      Text(
                        'KES ${amountPaid!.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ],

                if (outstandingBalance != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Outstanding:',
                        style: TextStyle(fontSize: 12, color: Colors.white),
                      ),
                      Text(
                        'KES ${outstandingBalance!.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryOrange,
                        ),
                      ),
                    ],
                  ),
                ],

                if (changeGiven != null && changeGiven! > 0) ...[
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Change:',
                        style: TextStyle(fontSize: 12, color: Colors.white),
                      ),
                      Text(
                        'KES ${changeGiven!.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryOrange,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),

          // Payment info
          if (location.tillNumber != null && location.tillNumber!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  border: Border.all(color: AppTheme.primaryOrange),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Column(
                  children: [
                    const Text(
                      'MPESA PAYMENT',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryBlack,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Till Number: ${location.tillNumber}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.darkGray,
                      ),
                    ),
                    if (location.paybillNumber != null &&
                        location.paybillNumber!.isNotEmpty)
                      Text(
                        'Paybill: ${location.paybillNumber}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.darkGray,
                        ),
                      ),
                  ],
                ),
              ),
            ),

          // Notes
          if (notes != null && notes!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.lightGray,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  notes!,
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppTheme.darkGray,
                    fontStyle: FontStyle.italic,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),

          const SizedBox(height: 16),

          // Footer
          Column(
            children: [
              Container(height: 1, color: AppTheme.mediumGray),
              const SizedBox(height: 8),
              const Text(
                'THANK YOU FOR YOUR BUSINESS',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryBlack,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Visit us again!',
                style: TextStyle(fontSize: 10, color: AppTheme.darkGray),
              ),
              const SizedBox(height: 8),
              Container(height: 1, color: AppTheme.primaryOrange),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                color: AppTheme.darkGray,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 10,
                color: AppTheme.primaryBlack,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Receipt item data model
class ReceiptItem {
  final String name;
  final double quantity;
  final double price;
  final double total;

  ReceiptItem({
    required this.name,
    required this.quantity,
    required this.price,
    required this.total,
  });
}
