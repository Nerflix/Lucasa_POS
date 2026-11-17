import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../meter_readings/meter_reading_edit_dialog.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../data/repositories/sales_repository.dart';
import '../../data/repositories/inventory_repository.dart';
import '../../data/repositories/receiving_repository.dart';
import '../../data/repositories/meter_reading_repository.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/models/item.dart' as model_item;
import '../../data/models/sale.dart';
import '../../data/models/location.dart';
import '../../data/models/receiving.dart';
import '../../data/models/meter_reading.dart' as model_mr;
import '../../services/auth_service.dart';
import '../../services/receipt_print_service.dart';
import '../../widgets/receipt_template.dart';
import '../../data/models/sale_audit_log.dart';
import 'edit_sale_dialog.dart';

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

enum _ReportRange { today, yesterday, last7Days, lastMonth, lastYear, custom }

class DateRangeSelector extends StatelessWidget {
  final _ReportRange range;
  final DateTime? customStart;
  final DateTime? customEnd;
  final ValueChanged<_ReportRange> onRangeChanged;
  final Future<void> Function()? onPickCustom;
  final String? label;
  const DateRangeSelector({
    super.key,
    required this.range,
    required this.onRangeChanged,
    this.customStart,
    this.customEnd,
    this.onPickCustom,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    final format = DateFormat('dd MMM yyyy');
    String customLabel = '';
    if (range == _ReportRange.custom &&
        customStart != null &&
        customEnd != null) {
      customLabel =
          '${format.format(customStart!)} - ${format.format(customEnd!)}';
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DropdownButton<_ReportRange>(
          value: range,
          items: const [
            DropdownMenuItem(value: _ReportRange.today, child: Text('Today')),
            DropdownMenuItem(
              value: _ReportRange.yesterday,
              child: Text('Yesterday'),
            ),
            DropdownMenuItem(
              value: _ReportRange.last7Days,
              child: Text('Last 7 Days'),
            ),
            DropdownMenuItem(
              value: _ReportRange.lastMonth,
              child: Text('Last Month'),
            ),
            DropdownMenuItem(
              value: _ReportRange.lastYear,
              child: Text('Last Year'),
            ),
            DropdownMenuItem(value: _ReportRange.custom, child: Text('Custom')),
          ],
          onChanged: (value) async {
            if (value == null) return;
            if (value == _ReportRange.custom && onPickCustom != null) {
              await onPickCustom!();
            } else {
              onRangeChanged(value);
            }
          },
        ),
        if (range == _ReportRange.custom && customLabel.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Text(
              customLabel,
              style: const TextStyle(fontSize: 13, color: AppTheme.darkGray),
            ),
          ),
        if (label != null)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Text(
              label!,
              style: const TextStyle(fontSize: 13, color: AppTheme.darkGray),
            ),
          ),
      ],
    );
  }
}

class _ReportsPageState extends State<ReportsPage> {
  _ReportRange _range = _ReportRange.today;
  DateTime? _customStart;
  DateTime? _customEnd;
  String? _selectedLocationId;
  String _selectedCategory = AppConstants.categoryFillingStation;
  bool _isLoading = true;
  List<Sale> _sales = [];
  List<SaleItem> _saleItems = [];
  List<model_item.Item> _items = [];
  List<Receiving> _receivings = [];
  List<Location> _locations = [];
  List<model_mr.MeterReading> _meterReadings = [];
  List<SaleAuditLog> _auditLogs = [];
  final TextEditingController _receiptSearchController =
      TextEditingController();

  @override
  void initState() {
    super.initState();
    final authService = Provider.of<AuthService>(context, listen: false);
    _selectedCategory =
        authService.currentCategory ?? AppConstants.categoryFillingStation;
    _loadReportData();
  }

  @override
  void dispose() {
    _receiptSearchController.dispose();
    super.dispose();
  }

  Future<void> _loadReportData() async {
    setState(() => _isLoading = true);
    try {
      final authService = Provider.of<AuthService>(context, listen: false);

      final salesRepo = Provider.of<SalesRepository>(context, listen: false);
      final inventoryRepo = Provider.of<InventoryRepository>(
        context,
        listen: false,
      );
      final receivingRepo = Provider.of<ReceivingRepository>(
        context,
        listen: false,
      );
      final meterRepo = Provider.of<MeterReadingRepository>(
        context,
        listen: false,
      );
      final authRepo = Provider.of<AuthRepository>(context, listen: false);

      final locationIds = authService.allowedLocationIds;
      if (locationIds.isEmpty) {
        setState(() {
          _isLoading = false;
        });
        return;
      }

      _locations = await authRepo.getActiveLocations();
      _selectedLocationId ??= locationIds.first;
      final selectedIds = _selectedLocationId == 'ALL'
          ? locationIds
          : [_selectedLocationId!];

      final category = _selectedCategory;

      final range = _getRange();
      final sales = selectedIds.length == 1
          ? await salesRepo.getSalesByLocationAndCategory(
              selectedIds.first,
              category,
              startDate: range.start,
              endDate: range.end,
            )
          : await salesRepo.getSalesByLocationsAndCategory(
              selectedIds,
              category,
              startDate: range.start,
              endDate: range.end,
            );

      final items = selectedIds.length == 1
          ? await inventoryRepo.getItemsByLocationAndCategory(
              selectedIds.first,
              category,
            )
          : await inventoryRepo.getItemsByLocationsAndCategory(
              selectedIds,
              category,
            );

      final filteredSales = sales.where((sale) => !sale.isSuspended).toList();
      final saleItemIds = filteredSales.map((sale) => sale.id).toList();
      final saleItems = await salesRepo.getSaleItemsBySaleIds(saleItemIds);

      final receivings = selectedIds.length == 1
          ? await receivingRepo.getReceivingsByLocationAndCategory(
              selectedIds.first,
              category,
              startDate: range.start,
              endDate: range.end,
            )
          : await receivingRepo.getReceivingsByLocationsAndCategory(
              selectedIds,
              category,
              startDate: range.start,
              endDate: range.end,
            );

      final readings = selectedIds.length == 1
          ? await meterRepo.getMeterReadingsByLocationAndRange(
              selectedIds.first,
              range.start,
              range.end,
            )
          : await meterRepo.getMeterReadingsByLocationsAndRange(
              selectedIds,
              range.start,
              range.end,
            );

      final auditLogs = await salesRepo.getAuditLogs(
        locationIds: selectedIds,
        startDate: range.start,
        endDate: range.end,
      );

      setState(() {
        _sales = filteredSales;
        _saleItems = saleItems;
        _items = items;
        _receivings = receivings;
        _meterReadings = readings;
        _auditLogs = auditLogs;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading report data: $e'),
            backgroundColor: AppTheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  _DateRange _getRange() {
    final now = DateTime.now();
    switch (_range) {
      case _ReportRange.today:
        return _DateRange(
          start: DateTime(now.year, now.month, now.day),
          end: DateTime(now.year, now.month, now.day, 23, 59, 59),
        );
      case _ReportRange.yesterday:
        final yesterday = now.subtract(const Duration(days: 1));
        return _DateRange(
          start: DateTime(yesterday.year, yesterday.month, yesterday.day),
          end: DateTime(
            yesterday.year,
            yesterday.month,
            yesterday.day,
            23,
            59,
            59,
          ),
        );
      case _ReportRange.last7Days:
        final start = now.subtract(const Duration(days: 6));
        return _DateRange(
          start: DateTime(start.year, start.month, start.day),
          end: DateTime(now.year, now.month, now.day, 23, 59, 59),
        );
      case _ReportRange.lastMonth:
        final firstDayThisMonth = DateTime(now.year, now.month, 1);
        final lastMonth = DateTime(
          firstDayThisMonth.year,
          firstDayThisMonth.month - 1,
          1,
        );
        final endLastMonth = DateTime(
          firstDayThisMonth.year,
          firstDayThisMonth.month,
          0,
          23,
          59,
          59,
        );
        return _DateRange(start: lastMonth, end: endLastMonth);
      case _ReportRange.lastYear:
        final start = DateTime(now.year - 1, 1, 1);
        final end = DateTime(now.year - 1, 12, 31, 23, 59, 59);
        return _DateRange(start: start, end: end);
      case _ReportRange.custom:
        final start = _customStart ?? DateTime(now.year, now.month, now.day);
        final end =
            _customEnd ?? DateTime(now.year, now.month, now.day, 23, 59, 59);
        return _DateRange(start: start, end: end);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);

    if (!authService.hasPermission('canViewReports')) {
      return const Scaffold(
        body: Center(
          child: Text('You do not have permission to view reports.'),
        ),
      );
    }

    return DefaultTabController(
      length: _selectedCategory == AppConstants.categoryFillingStation ? 9 : 8,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Reports'),
          backgroundColor: AppTheme.primaryOrange,
          foregroundColor: Colors.white,
          bottom: TabBar(
            isScrollable: true,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            labelStyle: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
            unselectedLabelStyle: const TextStyle(fontSize: 13),
            indicatorColor: Colors.white,
            indicatorWeight: 3,
            tabs: [
              Tab(text: 'Sales Summary'),
              Tab(text: 'Sales Graph'),
              Tab(text: 'Sales Detail'),
              Tab(text: 'Profit/Loss'),
              Tab(text: 'Inventory'),
              Tab(text: 'Receivings'),
              Tab(text: 'Low Stock'),
              if (_selectedCategory == AppConstants.categoryFillingStation)
                Tab(text: 'Meter Readings'),
              Tab(text: 'Audit Log'),
            ],
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  _buildFilters(authService),
                  const Divider(height: 1),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _loadReportData,
                      child: TabBarView(
                        children: [
                          _buildSalesSummary(),
                          _buildSalesGraph(),
                          _buildSalesDetail(),
                          _buildProfitLoss(),
                          _buildInventorySummary(),
                          _buildReceivingsSummary(),
                          _buildLowStockReport(),
                          if (_selectedCategory ==
                              AppConstants.categoryFillingStation)
                            _buildMeterReadingsReport(),
                          _buildAuditLogTab(),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildSalesGraph() {
    // Aggregate sales by date
    final Map<String, double> salesByDate = {};
    final dateFormat = DateFormat('yyyy-MM-dd');
    for (final sale in _sales) {
      final dateStr = dateFormat.format(sale.timestamp);
      salesByDate[dateStr] = (salesByDate[dateStr] ?? 0) + sale.totalAmount;
    }
    final sortedDates = salesByDate.keys.toList()..sort();
    if (sortedDates.isEmpty) {
      return const Center(
        child: Text(
          'No sales data for this period',
          style: TextStyle(color: AppTheme.darkGray),
        ),
      );
    }
    final maxY =
        salesByDate.values.fold<double>(0, (prev, e) => e > prev ? e : prev) *
        1.2;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Total Sales by Date',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 260,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceBetween,
                maxY: maxY > 0 ? maxY : 100,
                barTouchData: BarTouchData(enabled: true),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: true, reservedSize: 40),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        if (idx < 0 || idx >= sortedDates.length)
                          return const SizedBox();
                        final date = sortedDates[idx];
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            DateFormat('MMMd').format(DateTime.parse(date)),
                            style: const TextStyle(fontSize: 11),
                          ),
                        );
                      },
                      reservedSize: 36,
                    ),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                borderData: FlBorderData(show: false),
                gridData: FlGridData(show: true, horizontalInterval: maxY / 4),
                barGroups: [
                  for (int i = 0; i < sortedDates.length; i++)
                    BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: salesByDate[sortedDates[i]]!,
                          color: AppTheme.primaryOrange,
                          width: 18,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters(AuthService authService) {
    final canSelectAll = authService.isSuperAdmin;
    final isAdminUser = authService.isSuperAdmin || authService.isAdmin;
    final locationIds = authService.allowedLocationIds;
    final locations = _locations
        .where((loc) => locationIds.contains(loc.id))
        .toList();

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // Category switcher for admin/superadmin
          if (isAdminUser)
            DropdownButton<String>(
              value: _selectedCategory,
              items: const [
                DropdownMenuItem(
                  value: AppConstants.categoryFillingStation,
                  child: Text('Filling Station'),
                ),
                DropdownMenuItem(
                  value: AppConstants.categoryCarSale,
                  child: Text('Car Sale'),
                ),
              ],
              onChanged: (value) async {
                if (value == null) return;
                setState(() => _selectedCategory = value);
                await _loadReportData();
              },
            ),
          DateRangeSelector(
            range: _range,
            customStart: _customStart,
            customEnd: _customEnd,
            onRangeChanged: (value) async {
              setState(() => _range = value);
              await _loadReportData();
            },
            onPickCustom: _pickCustomRange,
          ),
          if (locations.isNotEmpty)
            DropdownButton<String>(
              value: _selectedLocationId ?? locations.first.id,
              items: [
                if (canSelectAll)
                  const DropdownMenuItem(
                    value: 'ALL',
                    child: Text('All Locations'),
                  ),
                ...locations.map(
                  (loc) => DropdownMenuItem(
                    value: loc.id,
                    child: Text(loc.address ?? loc.name),
                  ),
                ),
              ],
              onChanged: (value) async {
                if (value == null) return;
                setState(() => _selectedLocationId = value);
                await _loadReportData();
              },
            ),
        ],
      ),
    );
  }

  Widget _buildSalesSummary() {
    final isFillingStation =
        _selectedCategory == AppConstants.categoryFillingStation;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSummaryCard('Cash', _sumByPayment(AppConstants.paymentCash)),
        _buildSummaryCard(
          'Mpesa Till',
          _sumByPayment(AppConstants.paymentMpesa),
        ),
        _buildSummaryCard(
          'Equity Paybill',
          _sumByPayment(AppConstants.paymentEquity),
        ),
        _buildSummaryCard('Credit', _sumByPayment(AppConstants.paymentCredit)),
        const Divider(height: 32),
        _buildSummaryCard('Grand Total', _totalSales(), highlight: true),
        if (isFillingStation) ...[
          const SizedBox(height: 24),
          const Text(
            'Filling Station Detailed Summary',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          const SizedBox(height: 16),
          _buildFuelTieredSection('AGO (Diesel)', AppConstants.pumpTypeAGO),
          const SizedBox(height: 24),
          _buildFuelTieredSection('PMS (Petrol)', AppConstants.pumpTypePMS),
          const Divider(height: 48),
          _buildFuelGrandTotalSection(),
        ],
        const SizedBox(height: 100),
      ],
    );
  }

  Widget _buildFuelTieredSection(String title, String pumpType) {
    // 1. Calculate Pump Level Data
    final pumpReadings = _meterReadings
        .where((r) => r.pumpType == pumpType)
        .toList();
    final Map<int, List<model_mr.MeterReading>> pumpGroups = {};
    for (final r in pumpReadings) {
      pumpGroups.putIfAbsent(r.pumpNumber, () => []).add(r);
    }

    final List<Map<String, dynamic>> pumpList = [];
    double catA = 0, catL = 0, catT = 0;

    pumpGroups.forEach((pumpNum, readings) {
      if (readings.isEmpty) return;
      readings.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      final model_mr.MeterReading first = readings.first;
      final model_mr.MeterReading last = readings.last;

      double a = 0, l = 0, t = 0;
      if (readings.length > 1) {
        a = (last.valueA - first.valueA);
        l = (last.valueL - first.valueL);
        t = (last.valueT - first.valueT);
      }

      pumpList.add({'number': pumpNum, 'A': a, 'L': l, 'T': t});
      catA += a;
      catL += l;
      catT += t;
    });

    // 2. Calculate Category Payment Breakdown
    final typeSales = _sales.where((s) {
      final items = _saleItems.where((i) => i.saleId == s.id);
      return items.any((i) {
        final itemName = i.itemName.toUpperCase();
        final type = pumpType.toUpperCase();
        return itemName == type || itemName.contains('$type (');
      });
    }).toList();

    double cash = 0, mpesa = 0, equity = 0, credit = 0;
    for (final s in typeSales) {
      // We only take the amount corresponding to THIS pumpType if it's a mixed sale?
      // For filling station, it's usually one or the other per sale, but let's be safe.
      final items = _saleItems.where(
        (i) =>
            i.saleId == s.id &&
            i.itemName.toUpperCase() == pumpType.toUpperCase(),
      );
      final typeAmount = items.fold(0.0, (sum, item) => sum + item.subtotal);

      if (s.paymentMethod == AppConstants.paymentCash)
        cash += typeAmount;
      else if (s.paymentMethod == AppConstants.paymentMpesa)
        mpesa += typeAmount;
      else if (s.paymentMethod == AppConstants.paymentEquity)
        equity += typeAmount;
      else if (s.paymentMethod == AppConstants.paymentCredit)
        credit += typeAmount;
    }

    // Calculate total discounts for this fuel type
    double totalDiscounts = 0;
    for (final s in typeSales) {
      final items = _saleItems.where(
        (i) =>
            i.saleId == s.id &&
            i.itemName.toUpperCase() == pumpType.toUpperCase(),
      );
      totalDiscounts += items.fold(0.0, (sum, item) => sum + item.discount);
    }

    final totalSales = cash + mpesa + equity + credit;
    final adjustedTotal = totalSales + totalDiscounts;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: AppTheme.primaryOrange,
          ),
        ),
        const SizedBox(height: 8),
        Table(
          border: TableBorder.all(color: Colors.grey.shade300),
          columnWidths: const {
            0: FlexColumnWidth(1),
            1: FlexColumnWidth(1),
            2: FlexColumnWidth(1),
            3: FlexColumnWidth(1),
          },
          children: [
            TableRow(
              decoration: BoxDecoration(color: Colors.grey.shade100),
              children: const [
                Padding(
                  padding: EdgeInsets.all(8),
                  child: Text(
                    'Pump #',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.all(8),
                  child: Text(
                    'A (Cash)',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.all(8),
                  child: Text(
                    'L (Liters)',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.all(8),
                  child: Text(
                    'T (Total)',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            ...pumpList.map(
              (p) => TableRow(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text('Pump ${p['number']}'),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(p['A'].toStringAsFixed(1)),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(p['L'].toStringAsFixed(1)),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(p['T'].toStringAsFixed(1)),
                  ),
                ],
              ),
            ),
            TableRow(
              decoration: BoxDecoration(
                color: AppTheme.primaryOrange.withOpacity(0.05),
              ),
              children: [
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text(
                    'Category Total',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    catA.toStringAsFixed(1),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    catL.toStringAsFixed(1),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    catT.toStringAsFixed(1),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 16,
          children: [
            _buildMiniStat('Cash', cash),
            _buildMiniStat('Mpesa', mpesa),
            _buildMiniStat('Equity', equity),
            _buildMiniStat('Credit', credit),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 16,
          children: [
            _buildMiniStat('Total Sales', totalSales),
            if (totalDiscounts > 0) ...[
              _buildMiniStat('W/sale Discounts', totalDiscounts),
              _buildMiniStat('Adjusted Total', adjustedTotal),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildMiniStat(String label, double value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppTheme.darkGray),
        ),
        Text(
          value.toStringAsFixed(0),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildFuelGrandTotalSection() {
    double grandA = 0, grandL = 0, grandT = 0;

    // Filter to filling station readings only
    final fuelReadings = _meterReadings.toList();
    final Map<String, List<model_mr.MeterReading>> pumpGroups = {};
    for (final r in fuelReadings) {
      final key = '${r.pumpType}_${r.pumpNumber}';
      pumpGroups.putIfAbsent(key, () => []).add(r);
    }

    pumpGroups.values.forEach((readings) {
      if (readings.length > 1) {
        readings.sort((a, b) => a.timestamp.compareTo(b.timestamp));
        grandA += (readings.last.valueA - readings.first.valueA);
        grandL += (readings.last.valueL - readings.first.valueL);
        grandT += (readings.last.valueT - readings.first.valueT);
      }
    });

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.primaryOrange,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          const Text(
            'Grand Total (AGO + PMS)',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildLargeStat('A', grandA),
              _buildLargeStat('L', grandL),
              _buildLargeStat('T', grandT),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLargeStat(String label, double value) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
        Text(
          value.toStringAsFixed(1),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
      ],
    );
  }

  Widget _buildSalesDetail() {
    final format = DateFormat('dd MMM yyyy, hh:mm a');

    // Filter sales by receipt number if search is active
    final searchQuery = _receiptSearchController.text.trim().toLowerCase();
    final filteredSales = _sales.where((sale) {
      if (searchQuery.isEmpty) return true;
      return sale.saleId.toLowerCase().contains(searchQuery);
    }).toList();

    if (_sales.isEmpty) {
      return const Center(
        child: Text(
          'No sales in this period',
          style: TextStyle(color: AppTheme.darkGray),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: TextField(
            controller: _receiptSearchController,
            decoration: InputDecoration(
              hintText: 'Search by Receipt Number...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        setState(() {
                          _receiptSearchController.clear();
                        });
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            onChanged: (value) => setState(() {}),
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 600;

              if (filteredSales.isEmpty) {
                return const Center(
                  child: Text(
                    'No sales match your search',
                    style: TextStyle(color: AppTheme.darkGray),
                  ),
                );
              }

              return ListView.builder(
                padding: EdgeInsets.fromLTRB(12, 12, 12, isNarrow ? 100 : 16),
                itemCount: filteredSales.length,
                itemBuilder: (context, i) {
                  final sale = filteredSales[i];

                  final items = _saleItems
                      .where((item) => item.saleId == sale.id)
                      .toList();
                  final profit = sale.profit;
                  final isLoss = profit < 0;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ExpansionTile(
                      tilePadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      title: isNarrow
                          ? _buildSaleTileNarrow(sale, format, profit, isLoss)
                          : _buildSaleTileWide(sale, format, profit, isLoss),
                      children: [
                        const Divider(height: 1),
                        const SizedBox(height: 8),
                        if (items.isNotEmpty) ...[
                          const Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Items',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          ...items.map(
                            (item) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.circle,
                                    size: 6,
                                    color: AppTheme.darkGray,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      item.itemName,
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ),
                                  Text(
                                    'x${item.quantity.toStringAsFixed(0)}',
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    'KES ${item.sellingPrice.toStringAsFixed(0)}',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                        if (sale.notes != null && sale.notes!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.note,
                                  size: 14,
                                  color: AppTheme.darkGray,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    sale.notes!,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.darkGray,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 12),
                        Builder(
                          builder: (context) {
                            final auth = Provider.of<AuthService>(
                              context,
                              listen: false,
                            );
                            final canVoid =
                                auth.hasPermission('canVoidSales') ||
                                auth.isAdmin ||
                                auth.isSuperAdmin;
                            return Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                _buildActionChip(
                                  icon: Icons.print,
                                  label: 'Print',
                                  color: AppTheme.primaryOrange,
                                  onTap: () => _printReceipt(sale),
                                ),
                                if (canVoid) ...[
                                  const SizedBox(width: 8),
                                  _buildActionChip(
                                    icon: Icons.edit,
                                    label: 'Edit',
                                    color: AppTheme.info,
                                    onTap: () => _editSale(sale, items),
                                  ),
                                  const SizedBox(width: 8),
                                  _buildActionChip(
                                    icon: Icons.delete_outline,
                                    label: 'Delete',
                                    color: AppTheme.error,
                                    onTap: () => _deleteSale(sale, items),
                                  ),
                                ],
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSaleTileNarrow(
    Sale sale,
    DateFormat format,
    double profit,
    bool isLoss,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                sale.saleId,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.primaryOrange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                sale.paymentMethod,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppTheme.primaryOrange,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          format.format(sale.timestamp),
          style: const TextStyle(fontSize: 12, color: AppTheme.darkGray),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Text(
              'KES ${sale.totalAmount.toStringAsFixed(0)}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const Spacer(),
            Text(
              (isLoss ? 'Loss: ' : 'Profit: ') + profit.toStringAsFixed(0),
              style: TextStyle(
                fontSize: 12,
                color: isLoss ? AppTheme.error : AppTheme.success,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        if (sale.employeeName != null && sale.employeeName!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              'By: ${sale.employeeName}',
              style: const TextStyle(fontSize: 11, color: AppTheme.darkGray),
            ),
          ),
      ],
    );
  }

  Widget _buildSaleTileWide(
    Sale sale,
    DateFormat format,
    double profit,
    bool isLoss,
  ) {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                sale.saleId,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                format.format(sale.timestamp),
                style: const TextStyle(fontSize: 12, color: AppTheme.darkGray),
              ),
            ],
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'KES ${sale.totalAmount.toStringAsFixed(0)}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 2),
              Text(
                'Paid: ${sale.amountPaid.toStringAsFixed(0)}',
                style: const TextStyle(fontSize: 12, color: AppTheme.darkGray),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.primaryOrange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  sale.paymentMethod,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.primaryOrange,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                (isLoss ? 'Loss: ' : 'Profit: ') + profit.toStringAsFixed(0),
                style: TextStyle(
                  fontSize: 12,
                  color: isLoss ? AppTheme.error : AppTheme.success,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        if (sale.employeeName != null && sale.employeeName!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Text(
              sale.employeeName!,
              style: const TextStyle(fontSize: 12, color: AppTheme.darkGray),
            ),
          ),
      ],
    );
  }

  Widget _buildActionChip({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Actions for Sales Detail ---
  void _printReceipt(Sale sale) async {
    final authRepo = Provider.of<AuthRepository>(context, listen: false);
    final salesRepo = Provider.of<SalesRepository>(context, listen: false);
    final locationId = _selectedLocationId;
    if (locationId == null || locationId == 'ALL') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a specific location to print receipt'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final location = await authRepo.getLocation(locationId);
    if (location == null) return;
    final saleItems = await salesRepo.getSaleItemsBySaleIds([sale.id]);
    final receiptItems = saleItems
        .map(
          (item) => ReceiptItem(
            name: item.itemName,
            quantity: item.quantity,
            price: item.sellingPrice,
            total: item.subtotal,
          ),
        )
        .toList();
    final isCredit = sale.paymentMethod == AppConstants.paymentCredit;
    final changeGiven = isCredit ? null : (sale.amountPaid - sale.totalAmount);
    final outstandingBalance = isCredit
        ? (sale.totalAmount - sale.amountPaid)
        : null;
    final printData = ReceiptPrintData(
      location: location,
      receiptId: sale.saleId,
      timestamp: sale.timestamp,
      employeeName: sale.employeeName ?? '',
      items: saleItems
          .map(
            (item) => ReceiptPrintItem(
              name: item.itemName,
              quantity: item.quantity,
              price: item.sellingPrice,
            ),
          )
          .toList(),
      paymentMethod: sale.paymentMethod,
      totalAmount: sale.totalAmount,
      amountPaid: sale.amountPaid,
      changeGiven: changeGiven,
      outstandingBalance: outstandingBalance,
    );
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ReceiptTemplate(
                location: location,
                receiptType: 'SALE',
                receiptId: sale.saleId,
                timestamp: sale.timestamp,
                employeeName: sale.employeeName ?? '',
                items: receiptItems,
                paymentMethod: sale.paymentMethod,
                totalAmount: sale.totalAmount,
                amountPaid: sale.amountPaid,
                changeGiven: changeGiven,
                outstandingBalance: outstandingBalance,
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () async {
                  final service = ReceiptPrintService();
                  await service.showPrintOptions(ctx, printData);
                },
                icon: const Icon(Icons.print),
                label: const Text('Print Receipt'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _editSale(Sale sale, List<SaleItem> items) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => EditSaleDialog(sale: sale, items: items),
    );

    if (result == true) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sale updated successfully'),
            backgroundColor: AppTheme.success,
          ),
        );
        _loadReportData();
      }
    }
  }

  void _deleteSale(Sale sale, List<SaleItem> items) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Sale'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Delete sale ${sale.saleId}? This will restore inventory for all items sold.',
            ),
            if (items.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'Items that will be restored:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 6),
              ...items.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '• ${item.itemName} × ${item.quantity.toStringAsFixed(item.quantity == item.quantity.truncateToDouble() ? 0 : 2)}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete & Restore Inventory'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        final salesRepo = Provider.of<SalesRepository>(context, listen: false);
        final authService = Provider.of<AuthService>(context, listen: false);
        final actor =
            authService.currentEmployee?.firstName ??
            authService.currentEmployee?.id ??
            'Unknown';
        await salesRepo.deleteSaleWithInventoryReversal(
          saleId: sale.id,
          saleItems: items,
          sale: sale,
          performedBy: actor,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Sale deleted & inventory restored'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: AppTheme.success,
            ),
          );
          await _loadReportData();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error deleting sale: $e'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: AppTheme.error,
            ),
          );
        }
      }
    }
  }

  Widget _buildProfitLoss() {
    final authService = Provider.of<AuthService>(context, listen: false);
    final isFillingStation =
        authService.currentCategory == AppConstants.categoryFillingStation;
    final summary = _profitSummary();
    final net = summary.profit - summary.loss;
    final fuelProfits = isFillingStation ? _calculateFuelProfits() : null;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: net >= 0
                  ? [AppTheme.success, AppTheme.success.withOpacity(0.7)]
                  : [AppTheme.error, AppTheme.error.withOpacity(0.7)],
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              const Text(
                'Net Result',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 4),
              Text(
                'KES ${net.toStringAsFixed(0)}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 28,
                ),
              ),
              const SizedBox(height: 4),
              Icon(
                net >= 0 ? Icons.trending_up : Icons.trending_down,
                color: Colors.white,
                size: 24,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                'Total Profit',
                summary.profit,
                Icons.arrow_upward,
                AppTheme.success,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                'Total Loss',
                summary.loss,
                Icons.arrow_downward,
                AppTheme.error,
              ),
            ),
          ],
        ),
        if (isFillingStation && fuelProfits != null) ...[
          const SizedBox(height: 24),
          const Text(
            'Fuel Specific Profits',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 12),
          _buildSummaryCard('AGO (Diesel) Profit', fuelProfits.agoProfit),
          _buildSummaryCard('PMS (Petrol) Profit', fuelProfits.pmsProfit),
          _buildSummaryCard(
            'Total Fuel Profit',
            fuelProfits.agoProfit + fuelProfits.pmsProfit,
            highlight: true,
          ),
        ],
        const SizedBox(height: 24),
        const Text(
          'Profit/Loss by Date',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 12),
        SizedBox(height: 260, child: _buildProfitLossGraph()),
        const SizedBox(height: 100),
      ],
    );
  }

  Widget _buildStatCard(
    String label,
    double value,
    IconData icon,
    Color color,
  ) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: AppTheme.darkGray),
            ),
            const SizedBox(height: 4),
            Text(
              'KES ${value.toStringAsFixed(0)}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfitLossGraph() {
    // 11.2.B Graphical Profit/Loss
    // Aggregate profit/loss by date
    final Map<String, double> profitByDate = {};
    final dateFormat = DateFormat('yyyy-MM-dd');
    for (final sale in _sales) {
      final dateStr = dateFormat.format(sale.timestamp);
      final profit = sale.profit;
      profitByDate[dateStr] = (profitByDate[dateStr] ?? 0) + profit;
    }
    final sortedDates = profitByDate.keys.toList()..sort();
    if (sortedDates.isEmpty) {
      return const Center(
        child: Text(
          'No data for this period',
          style: TextStyle(color: AppTheme.darkGray),
        ),
      );
    }
    final maxY =
        profitByDate.values
            .map((e) => e.abs())
            .fold<double>(0, (prev, e) => e > prev ? e : prev) *
        1.2;
    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceBetween,
        maxY: maxY > 0 ? maxY : 100,
        minY: -maxY,
        barTouchData: BarTouchData(enabled: true),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(showTitles: true, reservedSize: 40),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final idx = value.toInt();
                if (idx < 0 || idx >= sortedDates.length)
                  return const SizedBox();
                final date = sortedDates[idx];
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    DateFormat('MMMd').format(DateTime.parse(date)),
                    style: const TextStyle(fontSize: 11),
                  ),
                );
              },
              reservedSize: 36,
            ),
          ),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        gridData: FlGridData(show: true, horizontalInterval: maxY / 4),
        barGroups: [
          for (int i = 0; i < sortedDates.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: profitByDate[sortedDates[i]]!,
                  color: profitByDate[sortedDates[i]]! >= 0
                      ? Colors.green
                      : Colors.red,
                  width: 18,
                  borderRadius: BorderRadius.circular(4),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildInventorySummary() {
    final summary = _inventorySummary();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                'Value (Buying)',
                summary.buyingValue,
                Icons.shopping_cart,
                AppTheme.info,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                'Value (Selling)',
                summary.sellingValue,
                Icons.sell,
                AppTheme.primaryOrange,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const Text(
          'Detailed Inventory',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 12),
        _buildInventoryDetailTable(),
        const SizedBox(height: 100),
      ],
    );
  }

  Widget _buildInventoryDetailTable() {
    if (_items.isEmpty) {
      return const Center(
        child: Text(
          'No inventory items found',
          style: TextStyle(color: AppTheme.darkGray),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 600) {
          return Column(
            children: _items.map((model_item.Item item) {
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      if (item.barcode != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          item.barcode!,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppTheme.darkGray,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          _buildInfoChip(
                            'Qty',
                            item.quantity.toStringAsFixed(2),
                          ),
                          _buildInfoChip(
                            'Buy',
                            'KES ${item.buyingPrice.toStringAsFixed(0)}',
                          ),
                          _buildInfoChip(
                            'Sell',
                            'KES ${item.sellingPrice.toStringAsFixed(0)}',
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Value (B): KES ${(item.buyingPrice * item.quantity).toStringAsFixed(0)}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.darkGray,
                            ),
                          ),
                          Text(
                            'Value (S): KES ${(item.sellingPrice * item.quantity).toStringAsFixed(0)}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          );
        }
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: const [
              DataColumn(label: Text('Item Name')),
              DataColumn(label: Text('Barcode')),
              DataColumn(label: Text('Quantity')),
              DataColumn(label: Text('Buying Price')),
              DataColumn(label: Text('Selling Price')),
              DataColumn(label: Text('Value (Buying)')),
              DataColumn(label: Text('Value (Selling)')),
            ],
            rows: _items
                .map(
                  (model_item.Item item) => DataRow(
                    cells: [
                      DataCell(Text(item.name)),
                      DataCell(Text(item.barcode ?? '-')),
                      DataCell(Text(item.quantity.toStringAsFixed(2))),
                      DataCell(
                        Text('KES ${item.buyingPrice.toStringAsFixed(2)}'),
                      ),
                      DataCell(
                        Text('KES ${item.sellingPrice.toStringAsFixed(2)}'),
                      ),
                      DataCell(
                        Text(
                          'KES ${(item.buyingPrice * item.quantity).toStringAsFixed(2)}',
                        ),
                      ),
                      DataCell(
                        Text(
                          'KES ${(item.sellingPrice * item.quantity).toStringAsFixed(2)}',
                        ),
                      ),
                    ],
                  ),
                )
                .toList(),
          ),
        );
      },
    );
  }

  Widget _buildInfoChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.lightGray,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 10, color: AppTheme.darkGray),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildReceivingsSummary() {
    final total = _receivings.fold(0.0, (sum, rec) => sum + rec.totalAmount);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSummaryCard('Total Receivings', total, highlight: true),
        const SizedBox(height: 24),
        const Text(
          'Detailed Receivings',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 12),
        _buildReceivingsDetailTable(),
        const SizedBox(height: 100),
      ],
    );
  }

  Widget _buildReceivingsDetailTable() {
    // 11.4.B Detailed Receivings Table
    if (_receivings.isEmpty) {
      return const Center(
        child: Text(
          'No receivings found',
          style: TextStyle(color: AppTheme.darkGray),
        ),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _receivings.length,
      separatorBuilder: (context, i) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final rec = _receivings[i];
        final items = rec.items ?? [];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ExpansionTile(
            title: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Text(
                    rec.receivingId,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    DateFormat('dd MMM yyyy, hh:mm a').format(rec.timestamp),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                Expanded(
                  child: Text(
                    'KES ${rec.totalAmount.toStringAsFixed(0)}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Expanded(
                  child: Text(
                    rec.employeeName ?? '',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
            children: [
              if (items.isNotEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Items Received:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    ...items.map(
                      (item) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Expanded(child: Text(item.itemName)),
                            Text('Qty: ${item.quantity.toStringAsFixed(2)}'),
                            const SizedBox(width: 8),
                            Text(
                              'Buy: KES ${item.buyingPrice.toStringAsFixed(2)}',
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Total: KES ${(item.buyingPrice * item.quantity).toStringAsFixed(2)}',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              if (rec.notes != null && rec.notes!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Notes: ${rec.notes!}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLowStockReport() {
    final lowStockItems =
        _items.where((item) => item.quantity <= item.reorderLevel).toList()
          ..sort(
            (a, b) => (a.quantity - a.reorderLevel).compareTo(
              b.quantity - b.reorderLevel,
            ),
          );

    if (lowStockItems.isEmpty) {
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

    return ListView(
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
                '${lowStockItems.length} item${lowStockItems.length == 1 ? '' : 's'} need restocking',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppTheme.error,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        ...lowStockItems.map((model_item.Item item) {
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
                      color: isOutOfStock
                          ? AppTheme.error
                          : AppTheme.primaryOrange,
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
                      color: isOutOfStock
                          ? AppTheme.error
                          : AppTheme.primaryOrange,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      isOutOfStock
                          ? 'OUT'
                          : 'Need ${deficit.toStringAsFixed(0)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
        const SizedBox(height: 100),
      ],
    );
  }

  Widget _buildSummaryCard(
    String title,
    double value, {
    bool highlight = false,
  }) {
    return Card(
      elevation: highlight ? 3 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: highlight
            ? const BorderSide(color: AppTheme.primaryOrange, width: 1.5)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            if (highlight)
              Container(
                width: 4,
                height: 32,
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  color: AppTheme.primaryOrange,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: highlight ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
            Text(
              'KES ${value.toStringAsFixed(0)}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: highlight ? 17 : 15,
                color: highlight
                    ? AppTheme.primaryOrange
                    : AppTheme.primaryBlack,
              ),
            ),
          ],
        ),
      ),
    );
  }

  double _sumByPayment(String method) {
    return _sales
        .where((s) => s.paymentMethod == method)
        .fold(0, (sum, s) => sum + s.totalAmount);
  }

  _FuelProfitSummary _calculateFuelProfits() {
    double agoProfit = 0;
    double pmsProfit = 0;

    for (final s in _sales) {
      final items = _saleItems.where((i) => i.saleId == s.id);
      for (final item in items) {
        final profit = (item.sellingPrice - item.buyingPrice) * item.quantity;
        if (item.itemName.toUpperCase().contains('AGO')) {
          agoProfit += profit;
        } else if (item.itemName.toUpperCase().contains('PMS')) {
          pmsProfit += profit;
        }
      }
    }
    return _FuelProfitSummary(agoProfit: agoProfit, pmsProfit: pmsProfit);
  }

  double _totalSales() {
    return _sales.fold(0, (sum, s) => sum + s.totalAmount);
  }

  _ProfitSummary _profitSummary() {
    double profit = 0;
    double loss = 0;
    for (final s in _sales) {
      if (s.profit >= 0) {
        profit += s.profit;
      } else {
        loss += s.profit.abs();
      }
    }
    return _ProfitSummary(profit: profit, loss: loss);
  }

  _InventorySummary _inventorySummary() {
    double buying = 0;
    double selling = 0;
    for (final i in _items) {
      buying += i.buyingPrice * i.quantity;
      selling += i.sellingPrice * i.quantity;
    }
    return _InventorySummary(buyingValue: buying, sellingValue: selling);
  }

  Future<void> _pickCustomRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: _customStart != null && _customEnd != null
          ? DateTimeRange(start: _customStart!, end: _customEnd!)
          : null,
    );
    if (picked != null) {
      setState(() {
        _customStart = picked.start;
        _customEnd = picked.end;
        _range = _ReportRange.custom;
      });
      await _loadReportData();
    }
  }

  Widget _buildMeterReadingsReport() {
    if (_meterReadings.isEmpty) {
      return const Center(
        child: Text(
          'No meter readings in this period',
          style: TextStyle(color: AppTheme.darkGray),
        ),
      );
    }
    final authService = Provider.of<AuthService>(context, listen: false);
    final canEdit = authService.hasPermission('canEditMeterReadings');
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
      itemCount: _meterReadings.length,
      itemBuilder: (context, index) {
        final reading = _meterReadings[index];
        final timeStr = DateFormat('dd MMM, HH:mm').format(reading.timestamp);
        final isAGO = reading.pumpType.toUpperCase().contains('AGO');
        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: isAGO
                            ? Colors.amber.withOpacity(0.15)
                            : Colors.blue.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        reading.pumpType,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: isAGO
                              ? Colors.amber.shade800
                              : Colors.blue.shade700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Pump ${reading.pumpNumber}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.lightGray,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        reading.readingType,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.darkGray,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _buildReadingValue('A', reading.valueA)),
                    const SizedBox(width: 8),
                    Expanded(child: _buildReadingValue('L', reading.valueL)),
                    const SizedBox(width: 8),
                    Expanded(child: _buildReadingValue('T', reading.valueT)),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(
                      Icons.person_outline,
                      size: 14,
                      color: AppTheme.darkGray,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      reading.employeeId,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.darkGray,
                      ),
                    ),
                    const Spacer(),
                    const Icon(
                      Icons.access_time,
                      size: 14,
                      color: AppTheme.darkGray,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      timeStr,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.darkGray,
                      ),
                    ),
                    if (canEdit) ...[
                      const SizedBox(width: 12),
                      InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () async {
                          final result = await showDialog<bool>(
                            context: context,
                            builder: (context) =>
                                MeterReadingEditDialog(reading: reading),
                          );
                          if (result == true) _loadReportData();
                        },
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryOrange.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.edit,
                            size: 16,
                            color: AppTheme.primaryOrange,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildReadingValue(String label, double value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: BoxDecoration(
        color: AppTheme.lightGray,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppTheme.darkGray,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value.toStringAsFixed(1),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildAuditLogTab() {
    final format = DateFormat('dd MMM yyyy, hh:mm a');

    if (_auditLogs.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 56, color: AppTheme.darkGray),
            SizedBox(height: 12),
            Text(
              'No audit events for this period',
              style: TextStyle(color: AppTheme.darkGray, fontSize: 15),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 80),
      itemCount: _auditLogs.length,
      itemBuilder: (context, index) {
        final log = _auditLogs[index];
        final isDelete = log.action == 'DELETE';
        final color = isDelete ? AppTheme.error : AppTheme.info;
        final icon = isDelete ? Icons.delete_outline : Icons.edit_outlined;
        final label = isDelete ? 'DELETED' : 'EDITED';

        // Parse snapshot items
        List<dynamic> snapshotItems = [];
        Map<String, dynamic>? saleInfo;
        List<dynamic> changes = [];

        try {
          if (isDelete) {
            saleInfo = Map<String, dynamic>.from(log.snapshot['sale'] ?? {});
            snapshotItems = List<dynamic>.from(log.snapshot['items'] ?? []);
          } else {
            changes = List<dynamic>.from(log.snapshot['changes'] ?? []);
            snapshotItems = List<dynamic>.from(
              log.snapshot['after_items'] ?? [],
            );
          }
        } catch (_) {}

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: ExpansionTile(
            leading: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 14, color: color),
                  const SizedBox(width: 4),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      color: color,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            title: Text(
              'Receipt: ${log.saleId}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'By: ${log.performedBy}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.darkGray,
                  ),
                ),
                Text(
                  format.format(log.performedAt.toLocal()),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.darkGray,
                  ),
                ),
              ],
            ),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              const Divider(height: 1),
              const SizedBox(height: 12),

              // ── DELETE: show full sale snapshot ─────────────────────
              if (isDelete && saleInfo != null) ...[
                _buildAuditInfoRow(
                  'Payment',
                  saleInfo['payment_method']?.toString() ?? '—',
                ),
                _buildAuditInfoRow(
                  'Total',
                  'KES ${(saleInfo['total_amount'] as num?)?.toStringAsFixed(0) ?? '—'}',
                ),
                _buildAuditInfoRow(
                  'Amount Paid',
                  'KES ${(saleInfo['amount_paid'] as num?)?.toStringAsFixed(0) ?? '—'}',
                ),
                _buildAuditInfoRow(
                  'Change Due',
                  'KES ${(saleInfo['change_given'] as num?)?.toStringAsFixed(0) ?? '—'}',
                ),
                if (saleInfo['employee_name'] != null)
                  _buildAuditInfoRow(
                    'Sold By',
                    saleInfo['employee_name'].toString(),
                  ),
                if (saleInfo['notes'] != null &&
                    saleInfo['notes'].toString().isNotEmpty)
                  _buildAuditInfoRow('Notes', saleInfo['notes'].toString()),
                const SizedBox(height: 10),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Items in deleted sale:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
                const SizedBox(height: 6),
                ...snapshotItems.map((rawItem) {
                  final item = Map<String, dynamic>.from(rawItem);
                  final qty = (item['quantity'] as num?)?.toDouble() ?? 0;
                  final price =
                      (item['selling_price'] as num?)?.toDouble() ?? 0;
                  final sub = (item['subtotal'] as num?)?.toDouble() ?? 0;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.circle,
                          size: 6,
                          color: AppTheme.darkGray,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            item['item_name']?.toString() ?? '—',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        Text(
                          '×${qty.toStringAsFixed(qty == qty.truncateToDouble() ? 0 : 2)}',
                          style: const TextStyle(fontSize: 13),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'KES ${price.toStringAsFixed(0)}',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppTheme.darkGray,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '= KES ${sub.toStringAsFixed(0)}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],

              // ── EDIT: show what changed ──────────────────────────────
              if (!isDelete) ...[
                if (changes.isEmpty)
                  const Text(
                    'Only payment/notes were changed (no qty edits)',
                    style: TextStyle(fontSize: 13, color: AppTheme.darkGray),
                  )
                else ...[
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Quantity changes:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  ...changes.map((change) {
                    final c = Map<String, dynamic>.from(change);
                    final oldQty = (c['old_qty'] as num?)?.toDouble() ?? 0;
                    final newQty = (c['new_qty'] as num?)?.toDouble() ?? 0;
                    final diff = newQty - oldQty;
                    final diffStr = diff > 0
                        ? '+${diff.toStringAsFixed(diff == diff.truncateToDouble() ? 0 : 2)}'
                        : diff.toStringAsFixed(
                            diff == diff.truncateToDouble() ? 0 : 2,
                          );
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.swap_horiz,
                            size: 14,
                            color: AppTheme.darkGray,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              c['item_name']?.toString() ?? '—',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                          Text(
                            '${oldQty.toStringAsFixed(oldQty == oldQty.truncateToDouble() ? 0 : 2)} → ${newQty.toStringAsFixed(newQty == newQty.truncateToDouble() ? 0 : 2)}',
                            style: const TextStyle(fontSize: 13),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '($diffStr)',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: diff < 0
                                  ? AppTheme.success
                                  : AppTheme.error,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildAuditInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.darkGray,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _DateRange {
  final DateTime start;
  final DateTime end;

  const _DateRange({required this.start, required this.end});
}

class _FuelProfitSummary {
  final double agoProfit;
  final double pmsProfit;

  const _FuelProfitSummary({required this.agoProfit, required this.pmsProfit});
}

class _ProfitSummary {
  final double profit;
  final double loss;

  const _ProfitSummary({required this.profit, required this.loss});
}

class _InventorySummary {
  final double buyingValue;
  final double sellingValue;

  const _InventorySummary({
    required this.buyingValue,
    required this.sellingValue,
  });
}
