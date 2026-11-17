import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../data/database/app_database.dart';
import '../../services/auth_service.dart';

/// Shows the full credit history for a single customer:
/// every credit (debt) they took and every payment they made, in
/// chronological order.
class CreditDetailPage extends StatefulWidget {
  final Customer customer;

  const CreditDetailPage({super.key, required this.customer});

  @override
  State<CreditDetailPage> createState() => _CreditDetailPageState();
}

class _CreditDetailPageState extends State<CreditDetailPage> {
  bool _isLoading = true;
  List<_TimelineEntry> _timeline = [];
  double _totalOwed = 0;
  double _totalPaid = 0;
  double _totalBalance = 0;

  final _dateFormat = DateFormat('dd MMM yyyy');
  final _timeFormat = DateFormat('hh:mm a');

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    final authService = Provider.of<AuthService>(context, listen: false);
    final db = Provider.of<AppDatabase>(context, listen: false);
    final category =
        authService.currentCategory ?? AppConstants.categoryFillingStation;

    // Get ALL credits (including fully paid ones)
    final credits =
        await db.getAllCreditsByCustomerAndCategory(widget.customer.id, category);

    if (credits.isEmpty) {
      setState(() {
        _timeline = [];
        _isLoading = false;
      });
      return;
    }

    // Get all payments for those credits
    final creditIds = credits.map((c) => c.id).toList();
    final payments = await db.getCreditPaymentsByCreditIds(creditIds);

    // Build a unified timeline
    final entries = <_TimelineEntry>[];

    // Aggregate totals
    double totalOwed = 0;
    double totalPaid = 0;

    for (final credit in credits) {
      totalOwed += credit.totalOwed;
      totalPaid += credit.amountPaid;

      // The credit itself (the debt was created)
      entries.add(_TimelineEntry(
        type: _EntryType.credit,
        dateTime: credit.createdAt,
        amount: credit.totalOwed,
        initialPayment: credit.totalOwed - credit.balance -
            // Sum of external payments for this credit
            payments
                .where((p) => p.creditId == credit.id)
                .fold(0.0, (sum, p) => sum + p.amount),
        creditId: credit.id,
        saleId: credit.saleId,
        creditTotalOwed: credit.totalOwed,
        creditAmountPaid: credit.amountPaid,
        creditBalance: credit.balance,
      ));
    }

    // Add payment entries
    for (final payment in payments) {
      entries.add(_TimelineEntry(
        type: _EntryType.payment,
        dateTime: payment.paidAt,
        amount: payment.amount,
        creditId: payment.creditId,
      ));
    }

    // Sort chronologically (most recent first)
    entries.sort((a, b) => b.dateTime.compareTo(a.dateTime));

    setState(() {
      _timeline = entries;
      _totalOwed = totalOwed;
      _totalPaid = totalPaid;
      _totalBalance = totalOwed - totalPaid;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final name =
        '${widget.customer.firstName} ${widget.customer.lastName}'.trim();

    return Scaffold(
      appBar: AppBar(
        title: Text(name.isEmpty ? 'Customer' : name),
        backgroundColor: AppTheme.primaryOrange,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Summary card
                _buildSummaryCard(),
                // Timeline
                Expanded(
                  child: _timeline.isEmpty
                      ? const Center(
                          child: Text(
                            'No credit history',
                            style: TextStyle(color: AppTheme.darkGray),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          itemCount: _timeline.length,
                          itemBuilder: (context, index) =>
                              _buildTimelineItem(_timeline[index]),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildSummaryCard() {
    final progressPct =
        _totalOwed > 0 ? (_totalPaid / _totalOwed).clamp(0.0, 1.0) : 0.0;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: AppTheme.primaryOrange,
                radius: 24,
                child: Text(
                  widget.customer.firstName.isNotEmpty
                      ? widget.customer.firstName[0].toUpperCase()
                      : 'C',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${widget.customer.firstName} ${widget.customer.lastName}'
                          .trim(),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    if (widget.customer.phone.isNotEmpty)
                      Text(
                        widget.customer.phone,
                        style: const TextStyle(
                          color: AppTheme.darkGray,
                          fontSize: 13,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progressPct,
              minHeight: 10,
              backgroundColor: AppTheme.lightGray,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(AppTheme.success),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${(progressPct * 100).toStringAsFixed(0)}% paid',
            style: const TextStyle(
              fontSize: 12,
              color: AppTheme.darkGray,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildSummaryTile(
                  'Total Owed',
                  'KES ${_totalOwed.toStringAsFixed(0)}',
                  AppTheme.primaryOrange,
                  Icons.receipt_long_outlined,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildSummaryTile(
                  'Paid',
                  'KES ${_totalPaid.toStringAsFixed(0)}',
                  AppTheme.success,
                  Icons.payment,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildSummaryTile(
                  'Balance',
                  'KES ${_totalBalance.toStringAsFixed(0)}',
                  _totalBalance > 0 ? AppTheme.error : AppTheme.success,
                  Icons.account_balance_wallet,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryTile(
      String label, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: color.withOpacity(0.8),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            child: Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineItem(_TimelineEntry entry) {
    final isCredit = entry.type == _EntryType.credit;
    final color = isCredit ? AppTheme.error : AppTheme.success;
    final icon = isCredit ? Icons.shopping_cart : Icons.payments;
    final dateStr = _dateFormat.format(entry.dateTime);
    final timeStr = _timeFormat.format(entry.dateTime);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline dot and line
          Column(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  shape: BoxShape.circle,
                  border: Border.all(color: color, width: 2),
                ),
                child: Icon(icon, size: 18, color: color),
              ),
            ],
          ),
          const SizedBox(width: 12),
          // Content
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.lightGray),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.03),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        isCredit ? 'Credit Taken' : 'Payment Made',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: color,
                        ),
                      ),
                      Text(
                        '${isCredit ? '+' : '-'} KES ${entry.amount.toStringAsFixed(0)}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.calendar_today,
                          size: 12, color: AppTheme.darkGray),
                      const SizedBox(width: 4),
                      Text(
                        dateStr,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.darkGray,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Icon(Icons.access_time,
                          size: 12, color: AppTheme.darkGray),
                      const SizedBox(width: 4),
                      Text(
                        timeStr,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.darkGray,
                        ),
                      ),
                    ],
                  ),
                  if (isCredit) ...[
                    const Divider(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildMiniStat(
                            'Owed', entry.creditTotalOwed ?? 0, AppTheme.primaryOrange),
                        _buildMiniStat(
                            'Paid', entry.creditAmountPaid ?? 0, AppTheme.success),
                        _buildMiniStat(
                            'Left', entry.creditBalance ?? 0,
                            (entry.creditBalance ?? 0) > 0
                                ? AppTheme.error
                                : AppTheme.success),
                      ],
                    ),
                    if ((entry.creditBalance ?? 0) <= 0)
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.success.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_circle,
                                size: 14, color: AppTheme.success),
                            SizedBox(width: 4),
                            Text(
                              'FULLY PAID',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.success,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStat(String label, double value, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: color.withOpacity(0.7),
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          'KES ${value.toStringAsFixed(0)}',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}

enum _EntryType { credit, payment }

class _TimelineEntry {
  final _EntryType type;
  final DateTime dateTime;
  final double amount;
  final String creditId;
  final String? saleId;

  // Only for credit entries — current state of this credit record
  final double? initialPayment;
  final double? creditTotalOwed;
  final double? creditAmountPaid;
  final double? creditBalance;

  const _TimelineEntry({
    required this.type,
    required this.dateTime,
    required this.amount,
    required this.creditId,
    this.saleId,
    this.initialPayment,
    this.creditTotalOwed,
    this.creditAmountPaid,
    this.creditBalance,
  });
}
