import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../data/database/app_database.dart';
import '../../services/auth_service.dart';
import '../credits/credit_detail_page.dart';

class AlertsPage extends StatefulWidget {
  const AlertsPage({super.key});

  @override
  State<AlertsPage> createState() => _AlertsPageState();
}

class _AlertsPageState extends State<AlertsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;

  List<Item> _lowStockItems = [];
  List<_OverdueCredit> _overdueCredits = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadAlerts();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAlerts() async {
    setState(() => _isLoading = true);
    final authService = Provider.of<AuthService>(context, listen: false);
    final db = Provider.of<AppDatabase>(context, listen: false);

    final locationIds = authService.allowedLocationIds;
    if (locationIds.isEmpty) {
      setState(() => _isLoading = false);
      return;
    }

    final category =
        authService.currentCategory ?? AppConstants.categoryFillingStation;

    // Load low-stock items
    List<Item> allItems = [];
    for (final locId in locationIds) {
      final items =
          await db.getItemsByLocationAndCategory(locId, category);
      allItems.addAll(items);
    }
    final lowStock = allItems
        .where((item) =>
            item.reorderLevel > 0 && item.quantity <= item.reorderLevel)
        .toList()
      ..sort((a, b) => (a.quantity - a.reorderLevel)
          .compareTo(b.quantity - b.reorderLevel));

    // Load overdue credits
    List<Credit> allCredits = [];
    for (final locId in locationIds) {
      final credits =
          await db.getCreditsByLocationAndCategory(locId, category);
      allCredits.addAll(credits);
    }

    final now = DateTime.now();
    final overdueCredits = <_OverdueCredit>[];
    for (final credit in allCredits) {
      final threshold =
          credit.category == AppConstants.categoryFillingStation
              ? const Duration(days: 3)
              : const Duration(days: 7);
      if (now.difference(credit.createdAt) > threshold) {
        final customer = await db.getCustomer(credit.customerId);
        if (customer != null) {
          overdueCredits.add(_OverdueCredit(
            credit: credit,
            customer: customer,
            daysOverdue: now.difference(credit.createdAt).inDays,
          ));
        }
      }
    }

    // Group overdue credits by customer
    final grouped = <String, _OverdueCredit>{};
    for (final oc in overdueCredits) {
      final existing = grouped[oc.customer.id];
      if (existing == null) {
        grouped[oc.customer.id] = oc;
      } else {
        grouped[oc.customer.id] = _OverdueCredit(
          credit: existing.credit,
          customer: existing.customer,
          daysOverdue: oc.daysOverdue > existing.daysOverdue
              ? oc.daysOverdue
              : existing.daysOverdue,
          totalBalance:
              existing.totalBalance + oc.credit.balance,
          creditCount: existing.creditCount + 1,
        );
      }
    }

    final sortedCredits = grouped.values.toList()
      ..sort((a, b) => b.daysOverdue.compareTo(a.daysOverdue));

    setState(() {
      _lowStockItems = lowStock;
      _overdueCredits = sortedCredits;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Alerts & Notifications'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.inventory_2_outlined, size: 18),
                  const SizedBox(width: 6),
                  const Text('Low Stock'),
                  if (_lowStockItems.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    _buildBadge(_lowStockItems.length, AppTheme.error),
                  ],
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.credit_card_off, size: 18),
                  const SizedBox(width: 6),
                  const Text('Overdue Credits'),
                  if (_overdueCredits.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    _buildBadge(_overdueCredits.length, AppTheme.warning),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildLowStockTab(),
                _buildOverdueCreditsTab(),
              ],
            ),
    );
  }

  Widget _buildBadge(int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$count',
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    );
  }

  // ── Low Stock Tab ──────────────────────────────────────────────────────

  Widget _buildLowStockTab() {
    if (_lowStockItems.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline, size: 64, color: AppTheme.success),
            SizedBox(height: 12),
            Text(
              'All items are above reorder level',
              style: TextStyle(color: AppTheme.darkGray, fontSize: 16),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAlerts,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.error.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.error.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber, color: AppTheme.error),
                const SizedBox(width: 8),
                Text(
                  '${_lowStockItems.length} item${_lowStockItems.length == 1 ? '' : 's'} need restocking',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppTheme.error,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ..._lowStockItems.map(_buildLowStockItem),
        ],
      ),
    );
  }

  Widget _buildLowStockItem(Item item) {
    final isOutOfStock = item.quantity <= 0;
    final deficit = item.reorderLevel - item.quantity;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isOutOfStock
                    ? AppTheme.error.withOpacity(0.1)
                    : AppTheme.primaryOrange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                isOutOfStock ? Icons.error_outline : Icons.warning_amber,
                color:
                    isOutOfStock ? AppTheme.error : AppTheme.primaryOrange,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        'Stock: ${item.quantity.toStringAsFixed(0)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: isOutOfStock
                              ? AppTheme.error
                              : AppTheme.darkGray,
                          fontWeight: isOutOfStock
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Reorder: ${item.reorderLevel.toStringAsFixed(0)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.darkGray,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: isOutOfStock ? AppTheme.error : AppTheme.warning,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                isOutOfStock
                    ? 'OUT'
                    : 'Need ${deficit.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Overdue Credits Tab ────────────────────────────────────────────────

  Widget _buildOverdueCreditsTab() {
    if (_overdueCredits.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline, size: 64, color: AppTheme.success),
            SizedBox(height: 12),
            Text(
              'No overdue credits',
              style: TextStyle(color: AppTheme.darkGray, fontSize: 16),
            ),
          ],
        ),
      );
    }

    final totalBalance = _overdueCredits.fold<double>(
      0,
      (sum, c) => sum + c.totalBalance,
    );

    return RefreshIndicator(
      onRefresh: _loadAlerts,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.warning.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.warning.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber, color: AppTheme.warning),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_overdueCredits.length} customer${_overdueCredits.length == 1 ? '' : 's'} with overdue credits',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppTheme.warning,
                        ),
                      ),
                      Text(
                        'Total: KES ${totalBalance.toStringAsFixed(0)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.warning.withOpacity(0.8),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ..._overdueCredits.map(_buildOverdueCreditItem),
        ],
      ),
    );
  }

  Widget _buildOverdueCreditItem(_OverdueCredit item) {
    final name =
        '${item.customer.firstName} ${item.customer.lastName}'.trim();
    final dateStr =
        DateFormat('dd MMM yyyy').format(item.credit.createdAt);
    final isFillingStation =
        item.credit.category == AppConstants.categoryFillingStation;
    final threshold = isFillingStation ? 3 : 7;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) =>
                  CreditDetailPage(customer: item.customer),
            ),
          );
          _loadAlerts();
        },
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: AppTheme.error.withOpacity(0.15),
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : 'C',
                  style: const TextStyle(
                    color: AppTheme.error,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.isEmpty ? 'Unnamed' : name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
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
                        if (item.creditCount > 1) ...[
                          const SizedBox(width: 8),
                          Text(
                            '${item.creditCount} debts',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.darkGray,
                            ),
                          ),
                        ],
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
                      fontSize: 14,
                      color: AppTheme.error,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
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
              const Icon(Icons.chevron_right,
                  size: 18, color: AppTheme.darkGray),
            ],
          ),
        ),
      ),
    );
  }
}

class _OverdueCredit {
  final Credit credit;
  final Customer customer;
  final int daysOverdue;
  final double totalBalance;
  final int creditCount;

  _OverdueCredit({
    required this.credit,
    required this.customer,
    required this.daysOverdue,
    double? totalBalance,
    this.creditCount = 1,
  }) : totalBalance = totalBalance ?? credit.balance;
}
