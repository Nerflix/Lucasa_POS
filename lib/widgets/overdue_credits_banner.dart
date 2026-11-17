import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../core/constants/app_constants.dart';
import '../core/theme/app_theme.dart';
import '../data/database/app_database.dart';
import '../features/credits/credit_detail_page.dart';
import '../services/auth_service.dart';

/// A banner that shows overdue credit notifications.
///
/// - Filling Station: credits older than 3 days
/// - Car Sale: credits older than 7 days
///
/// Works for both admin and employee views.
class OverdueCreditsBanner extends StatefulWidget {
  /// If null, shows overdue credits for ALL categories (admin view).
  /// If set, filters to that category only (employee view).
  final String? category;

  /// If set, filters credits to these location IDs only.
  final List<String>? locationIds;

  const OverdueCreditsBanner({
    super.key,
    this.category,
    this.locationIds,
  });

  @override
  State<OverdueCreditsBanner> createState() => _OverdueCreditsBannerState();
}

class _OverdueCreditsBannerState extends State<OverdueCreditsBanner> {
  List<_OverdueCustomer> _overdueCustomers = [];
  bool _isLoading = true;
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    _loadOverdueCredits();
  }

  @override
  void didUpdateWidget(covariant OverdueCreditsBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.category != widget.category) {
      _loadOverdueCredits();
    }
  }

  Future<void> _loadOverdueCredits() async {
    final db = Provider.of<AppDatabase>(context, listen: false);
    final now = DateTime.now();

    List<Credit> allCredits;

    if (widget.locationIds != null && widget.locationIds!.isNotEmpty) {
      // Employee or scoped admin — load for specific locations
      final futures = <Future<List<Credit>>>[];
      for (final locId in widget.locationIds!) {
        if (widget.category != null) {
          futures.add(db.getCreditsByLocationAndCategory(locId, widget.category!));
        } else {
          futures.add(db.getCreditsByLocation(locId));
        }
      }
      final results = await Future.wait(futures);
      allCredits = results.expand((list) => list).toList();
    } else {
      // Admin — load all outstanding credits
      allCredits = await db.getAllOutstandingCredits();
      if (widget.category != null) {
        allCredits = allCredits
            .where((c) => c.category == widget.category)
            .toList();
      }
    }

    // Filter to overdue only
    final overdueCredits = allCredits.where((credit) {
      final threshold = credit.category == AppConstants.categoryFillingStation
          ? const Duration(days: 3)
          : const Duration(days: 7);
      return now.difference(credit.createdAt) > threshold;
    }).toList();

    if (overdueCredits.isEmpty) {
      setState(() {
        _overdueCustomers = [];
        _isLoading = false;
      });
      return;
    }

    // Group by customer
    final customerIds = overdueCredits.map((c) => c.customerId).toSet();
    final customerMap = <String, Customer>{};
    for (final cid in customerIds) {
      final customer = await db.getCustomer(cid);
      if (customer != null) {
        customerMap[cid] = customer;
      }
    }

    final grouped = <String, _OverdueCustomer>{};
    for (final credit in overdueCredits) {
      final customer = customerMap[credit.customerId];
      if (customer == null) continue;

      final daysOverdue = now.difference(credit.createdAt).inDays;
      final existing = grouped[customer.id];
      if (existing == null) {
        grouped[customer.id] = _OverdueCustomer(
          customer: customer,
          totalBalance: credit.balance,
          oldestCreditDate: credit.createdAt,
          daysOverdue: daysOverdue,
          category: credit.category,
          creditCount: 1,
        );
      } else {
        grouped[customer.id] = existing.copyWith(
          totalBalance: existing.totalBalance + credit.balance,
          oldestCreditDate: credit.createdAt.isBefore(existing.oldestCreditDate)
              ? credit.createdAt
              : existing.oldestCreditDate,
          daysOverdue: daysOverdue > existing.daysOverdue
              ? daysOverdue
              : existing.daysOverdue,
          creditCount: existing.creditCount + 1,
        );
      }
    }

    final sorted = grouped.values.toList()
      ..sort((a, b) => b.daysOverdue.compareTo(a.daysOverdue));

    setState(() {
      _overdueCustomers = sorted;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _overdueCustomers.isEmpty) {
      return const SizedBox.shrink();
    }

    final totalBalance = _overdueCustomers.fold<double>(
      0,
      (sum, c) => sum + c.totalBalance,
    );

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.error.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.error.withOpacity(0.3),
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          // Header — always visible
          InkWell(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.error.withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.warning_amber_rounded,
                      color: AppTheme.error,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Overdue Credits (${_overdueCustomers.length})',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: AppTheme.error,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'KES ${totalBalance.toStringAsFixed(0)} outstanding',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.error.withOpacity(0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _isExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: AppTheme.error,
                  ),
                ],
              ),
            ),
          ),
          // Expanded list of overdue customers
          if (_isExpanded) ...[
            const Divider(height: 1, color: AppTheme.error),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: _overdueCustomers.length,
              separatorBuilder: (_, __) =>
                  Divider(height: 1, color: AppTheme.error.withOpacity(0.15)),
              itemBuilder: (context, index) {
                final item = _overdueCustomers[index];
                return _buildOverdueItem(item);
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOverdueItem(_OverdueCustomer item) {
    final name =
        '${item.customer.firstName} ${item.customer.lastName}'.trim();
    final dateStr = DateFormat('dd MMM yyyy').format(item.oldestCreditDate);
    final isFillingStation =
        item.category == AppConstants.categoryFillingStation;
    final threshold = isFillingStation ? 3 : 7;

    return InkWell(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                CreditDetailPage(customer: item.customer),
          ),
        );
        _loadOverdueCredits();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: AppTheme.error.withOpacity(0.15),
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : 'C',
                style: const TextStyle(
                  color: AppTheme.error,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name.isEmpty ? 'Unnamed' : name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(
                        isFillingStation
                            ? Icons.local_gas_station
                            : Icons.shopping_cart,
                        size: 12,
                        color: AppTheme.darkGray,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Since $dateStr',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.darkGray,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'KES ${item.totalBalance.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: AppTheme.error,
                  ),
                ),
                Container(
                  margin: const EdgeInsets.only(top: 2),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: item.daysOverdue > threshold * 2
                        ? AppTheme.error
                        : AppTheme.warning,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${item.daysOverdue}d overdue',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 18, color: AppTheme.darkGray),
          ],
        ),
      ),
    );
  }
}

class _OverdueCustomer {
  final Customer customer;
  final double totalBalance;
  final DateTime oldestCreditDate;
  final int daysOverdue;
  final String category;
  final int creditCount;

  const _OverdueCustomer({
    required this.customer,
    required this.totalBalance,
    required this.oldestCreditDate,
    required this.daysOverdue,
    required this.category,
    required this.creditCount,
  });

  _OverdueCustomer copyWith({
    double? totalBalance,
    DateTime? oldestCreditDate,
    int? daysOverdue,
    int? creditCount,
  }) {
    return _OverdueCustomer(
      customer: customer,
      totalBalance: totalBalance ?? this.totalBalance,
      oldestCreditDate: oldestCreditDate ?? this.oldestCreditDate,
      daysOverdue: daysOverdue ?? this.daysOverdue,
      category: category,
      creditCount: creditCount ?? this.creditCount,
    );
  }
}
