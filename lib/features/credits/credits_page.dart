import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:drift/drift.dart' as drift;
import 'package:uuid/uuid.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/toast_utils.dart';
import '../../data/database/app_database.dart';
import '../../services/auth_service.dart';
import 'credit_detail_page.dart';

class CreditsPage extends StatefulWidget {
  const CreditsPage({super.key});

  @override
  State<CreditsPage> createState() => _CreditsPageState();
}

class _CreditsPageState extends State<CreditsPage> {
  final _searchController = TextEditingController();
  final _uuid = const Uuid();
  List<_CreditSummary> _credits = [];
  List<_CreditSummary> _filteredCredits = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCredits();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCredits() async {
    setState(() => _isLoading = true);
    final authService = Provider.of<AuthService>(context, listen: false);

    if (!authService.hasPermission('canProcessSales')) {
      setState(() {
        _credits = [];
        _filteredCredits = [];
        _isLoading = false;
      });
      return;
    }

    final db = Provider.of<AppDatabase>(context, listen: false);
    final locationIds = authService.allowedLocationIds;

    if (locationIds.isEmpty) {
      setState(() {
        _credits = [];
        _filteredCredits = [];
        _isLoading = false;
      });
      return;
    }

    final category = authService.currentCategory ?? AppConstants.categoryFillingStation;
    // Use ALL credits (including settled) so totalOwed and amountPaid
    // are cumulative lifetime values that only ever go up.
    final credits = await db.getAllCreditsByLocationAndCategory(locationIds.first, category);
    final customers = await db.getCustomersByLocation(locationIds.first);
    final customersById = {for (final c in customers) c.id: c};

    final summaries = <String, _CreditSummary>{};
    for (final credit in credits) {
      final customer = customersById[credit.customerId];
      if (customer == null) continue;
      final existing = summaries[customer.id];
      if (existing == null) {
        summaries[customer.id] = _CreditSummary(
          customer: customer,
          totalOwed: credit.totalOwed,
          amountPaid: credit.amountPaid,
          balance: credit.balance,
        );
      } else {
        summaries[customer.id] = existing.copyWith(
          totalOwed: existing.totalOwed + credit.totalOwed,
          amountPaid: existing.amountPaid + credit.amountPaid,
          balance: existing.balance + credit.balance,
        );
      }
    }

    // Only show customers who still have an outstanding balance
    final list = summaries.values
        .where((s) => s.balance > 0)
        .toList()
      ..sort((a, b) => b.balance.compareTo(a.balance));

    setState(() {
      _credits = list;
      _filteredCredits = list;
      _isLoading = false;
    });
  }

  void _filterCredits(String query) {
    setState(() {
      if (query.trim().isEmpty) {
        _filteredCredits = _credits;
      } else {
        _filteredCredits = _credits.where((credit) {
          final name = '${credit.customer.firstName} ${credit.customer.lastName}'.toLowerCase();
          return name.contains(query.toLowerCase()) ||
              credit.customer.phone.contains(query);
        }).toList();
      }
    });
  }

  Future<void> _showPaymentDialog(_CreditSummary summary) async {
    final amountController = TextEditingController();
    final result = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.payment, color: AppTheme.primaryOrange),
            SizedBox(width: 8),
            Text('Record Payment'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.lightGray,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.person, size: 16, color: AppTheme.darkGray),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${summary.customer.firstName} ${summary.customer.lastName}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Outstanding Balance:',
                          style: TextStyle(
                            color: AppTheme.darkGray,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          'KES ${summary.balance.toStringAsFixed(0)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: AppTheme.error,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: amountController,
                decoration: const InputDecoration(
                  labelText: 'Amount Paid (KES)',
                  prefixIcon: Icon(Icons.money),
                  border: OutlineInputBorder(),
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                autofocus: true,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              final amount = double.tryParse(amountController.text.trim()) ?? 0;
              if (amount <= 0) {
                ToastUtils.showError('Enter a valid amount.');
                return;
              }
              if (amount > summary.balance) {
                ToastUtils.showError('Amount cannot exceed balance.');
                return;
              }
              Navigator.pop(context, amount);
            },
            icon: const Icon(Icons.check, size: 18),
            label: const Text('Save Payment'),
          ),
        ],
      ),
    );

    if (result != null) {
      await _applyPayment(summary.customer, result);
    }
  }

  Future<void> _applyPayment(Customer customer, double amount) async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final db = Provider.of<AppDatabase>(context, listen: false);
    final category = authService.currentCategory ?? AppConstants.categoryFillingStation;
    final credits = await db.getCreditsByCustomerAndCategory(customer.id, category);
    if (credits.isEmpty) {
      ToastUtils.showError('No outstanding credit found.');
      return;
    }

    double remaining = amount;
    final now = DateTime.now();

    for (final credit in credits) {
      if (remaining <= 0) break;
      final applied = remaining >= credit.balance ? credit.balance : remaining;
      final updated = CreditsCompanion(
        id: drift.Value(credit.id),
        customerId: drift.Value(credit.customerId),
        saleId: drift.Value(credit.saleId),
        locationId: drift.Value(credit.locationId),
        category: drift.Value(credit.category),
        totalOwed: drift.Value(credit.totalOwed),
        amountPaid: drift.Value(credit.amountPaid + applied),
        balance: drift.Value(credit.balance - applied),
        createdAt: drift.Value(credit.createdAt),
        lastPaymentAt: drift.Value(now),
        syncedAt: const drift.Value(null),
      );

      await db.updateCredit(updated);
      await db.insertCreditPayment(
        CreditPaymentsCompanion(
          id: drift.Value(_uuid.v4()),
          creditId: drift.Value(credit.id),
          amount: drift.Value(applied),
          paidAt: drift.Value(now),
        ),
      );

      remaining -= applied;
    }

    ToastUtils.showSuccess('Payment recorded');
    await _loadCredits();
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth <= 600;

    if (!authService.hasPermission('canProcessSales')) {
      return const Scaffold(
        body: Center(
          child: Text('You do not have permission to manage credits.'),
        ),
      );
    }

    return Scaffold(
      body: Column(
        children: [
          Container(
            color: Colors.white,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.credit_card, size: 28, color: AppTheme.primaryOrange),
                        const SizedBox(width: 12),
                        Text(
                          'Credits',
                          style: TextStyle(
                            fontSize: isMobile ? 24 : 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: () {
                            // TODO: Handle notification tap
                          },
                          icon: const Icon(Icons.notifications_none_outlined,
                              color: AppTheme.darkGray),
                        ),
                      ],
                    ),
                    if (_credits.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryOrange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: AppTheme.primaryOrange.withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildStat(
                              'Customers',
                              _credits.length.toString(),
                              Icons.people,
                            ),
                            Container(
                              width: 1,
                              height: 30,
                              color: AppTheme.mediumGray,
                            ),
                            _buildStat(
                              'Total Balance',
                              'KES ${_credits.fold<double>(0, (sum, c) => sum + c.balance).toStringAsFixed(0)}',
                              Icons.account_balance_wallet,
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: _searchController,
                      decoration: const InputDecoration(
                        hintText: 'Search by customer name or phone',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: _filterCredits,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadCredits,
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredCredits.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.credit_card_off,
                                size: 64,
                                color: AppTheme.mediumGray.withOpacity(0.5),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _searchController.text.isNotEmpty
                                    ? 'No matching credits found'
                                    : 'No outstanding credits',
                                style: const TextStyle(
                                  color: AppTheme.darkGray,
                                  fontSize: 16,
                                ),
                              ),
                              if (_searchController.text.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                TextButton.icon(
                                  onPressed: () {
                                    _searchController.clear();
                                    _filterCredits('');
                                  },
                                  icon: const Icon(Icons.clear),
                                  label: const Text('Clear search'),
                                ),
                              ],
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _filteredCredits.length,
                          itemBuilder: (context, index) {
                            final credit = _filteredCredits[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              elevation: 2,
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Customer Info Header
                                    Row(
                                      children: [
                                        CircleAvatar(
                                          backgroundColor: AppTheme.primaryOrange,
                                          radius: 20,
                                          child: Text(
                                            credit.customer.firstName.isNotEmpty
                                                ? credit.customer.firstName[0].toUpperCase()
                                                : 'C',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 18,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                '${credit.customer.firstName} ${credit.customer.lastName}',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 16,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Row(
                                                children: [
                                                  const Icon(Icons.phone, size: 14, color: AppTheme.darkGray),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    credit.customer.phone,
                                                    style: const TextStyle(
                                                      color: AppTheme.darkGray,
                                                      fontSize: 13,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        // Balance Badge
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppTheme.error.withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(20),
                                            border: Border.all(
                                              color: AppTheme.error.withOpacity(0.3),
                                            ),
                                          ),
                                          child: Column(
                                            children: [
                                              const Text(
                                                'Balance',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  color: AppTheme.darkGray,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                              Text(
                                                'KES ${credit.balance.toStringAsFixed(0)}',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 14,
                                                  color: AppTheme.error,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    const Divider(height: 1),
                                    const SizedBox(height: 12),
                                    // Payment Details Grid
                                    Row(
                                      children: [
                                        Expanded(
                                          child: _buildInfoTile(
                                            icon: Icons.receipt_long_outlined,
                                            label: 'Total Owed',
                                            value: 'KES ${credit.totalOwed.toStringAsFixed(0)}',
                                            color: AppTheme.primaryOrange,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: _buildInfoTile(
                                            icon: Icons.payment,
                                            label: 'Paid',
                                            value: 'KES ${credit.amountPaid.toStringAsFixed(0)}',
                                            color: AppTheme.success,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    // Action Buttons
                                    Row(
                                      children: [
                                        Expanded(
                                          child: OutlinedButton.icon(
                                            onPressed: () async {
                                              await Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (context) => CreditDetailPage(customer: credit.customer),
                                                ),
                                              );
                                              _loadCredits();
                                            },
                                            icon: const Icon(Icons.history, size: 18),
                                            label: const Text('History'),
                                            style: OutlinedButton.styleFrom(
                                              padding: const EdgeInsets.symmetric(vertical: 12),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: ElevatedButton.icon(
                                            onPressed: () => _showPaymentDialog(credit),
                                            icon: const Icon(Icons.add_card, size: 18),
                                            label: const Text('Record Payment'),
                                            style: ElevatedButton.styleFrom(
                                              padding: const EdgeInsets.symmetric(vertical: 12),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStat(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppTheme.primaryOrange),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: AppTheme.darkGray,
              ),
            ),
            Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildInfoTile({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: color.withOpacity(0.8),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _CreditSummary {
  final Customer customer;
  final double totalOwed;
  final double amountPaid;
  final double balance;

  const _CreditSummary({
    required this.customer,
    required this.totalOwed,
    required this.amountPaid,
    required this.balance,
  });

  _CreditSummary copyWith({
    double? totalOwed,
    double? amountPaid,
    double? balance,
  }) {
    return _CreditSummary(
      customer: customer,
      totalOwed: totalOwed ?? this.totalOwed,
      amountPaid: amountPaid ?? this.amountPaid,
      balance: balance ?? this.balance,
    );
  }
}
