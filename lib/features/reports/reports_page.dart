  Widget _buildDeletedSalesReport() {
    // 11.5 Deleted Sales Report
    if (_deletedSalesLogs.isEmpty) {
      return const Center(child: Text('No deleted sales found', style: TextStyle(color: AppTheme.darkGray)));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _deletedSalesLogs.length,
      separatorBuilder: (context, i) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final log = _deletedSalesLogs[i];
        final sale = log.saleDetails;
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ExpansionTile(
            title: Row(
              children: [
                Expanded(child: Text('Sale ID: ${log.saleId}', style: const TextStyle(fontWeight: FontWeight.bold))),
                Expanded(child: Text('Deleted by: ${log.employeeName}', style: const TextStyle(fontSize: 13))),
                Expanded(child: Text(DateFormat('dd MMM yyyy, hh:mm a').format(log.timestamp), style: const TextStyle(fontSize: 13))),
              ],
            ),
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Payment Method: ${sale.paymentMethod}'),
                    Text('Total: KES ${sale.totalAmount.toStringAsFixed(0)}'),
                    const SizedBox(height: 8),
                    const Text('Items:', style: TextStyle(fontWeight: FontWeight.bold)),
                    ...sale.items.map((item) => Text('${item.name} x${item.quantity} @ KES ${item.price.toStringAsFixed(0)}')),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEditedSalesReport() {
    // 11.6 Edited Sales Report
    if (_editedSalesLogs.isEmpty) {
      return const Center(child: Text('No edited sales found', style: TextStyle(color: AppTheme.darkGray)));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _editedSalesLogs.length,
      separatorBuilder: (context, i) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final log = _editedSalesLogs[i];
        final changes = log.changes;
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ExpansionTile(
            title: Row(
              children: [
                Expanded(child: Text('Sale ID: ${log.saleId}', style: const TextStyle(fontWeight: FontWeight.bold))),
                Expanded(child: Text('Edited by: ${log.employeeName}', style: const TextStyle(fontSize: 13))),
                Expanded(child: Text(DateFormat('dd MMM yyyy, hh:mm a').format(log.timestamp), style: const TextStyle(fontSize: 13))),
              ],
            ),
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Changes:', style: TextStyle(fontWeight: FontWeight.bold)),
                    ...changes.map<Widget>((change) => Text(change)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../data/database/app_database.dart';
import '../../services/auth_service.dart';

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

enum _ReportRange {
  today,
  yesterday,
  last7Days,
  lastMonth,
  lastYear,
  custom,
}


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
    if (range == _ReportRange.custom && customStart != null && customEnd != null) {
      customLabel = '${format.format(customStart!)} - ${format.format(customEnd!)}';
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DropdownButton<_ReportRange>(
          value: range,
          items: const [
            DropdownMenuItem(value: _ReportRange.today, child: Text('Today')),
            DropdownMenuItem(value: _ReportRange.yesterday, child: Text('Yesterday')),
            DropdownMenuItem(value: _ReportRange.last7Days, child: Text('Last 7 Days')),
            DropdownMenuItem(value: _ReportRange.lastMonth, child: Text('Last Month')),
            DropdownMenuItem(value: _ReportRange.lastYear, child: Text('Last Year')),
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
            child: Text(customLabel, style: const TextStyle(fontSize: 13, color: AppTheme.darkGray)),
          ),
        if (label != null)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Text(label!, style: const TextStyle(fontSize: 13, color: AppTheme.darkGray)),
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

  bool _isLoading = true;
  List<Sale> _sales = [];
  List<SaleItem> _saleItems = [];
  List<Item> _items = [];
  List<Receiving> _receivings = [];
  List<Location> _locations = [];

  @override
  void initState() {
    super.initState();
    _loadReportData();
  }

  Future<void> _loadReportData() async {
    setState(() => _isLoading = true);
    final authService = Provider.of<AuthService>(context, listen: false);
    final db = Provider.of<AppDatabase>(context, listen: false);

    final locationIds = authService.allowedLocationIds;
    if (locationIds.isEmpty) {
      setState(() {
        _isLoading = false;
      });
      return;
    }

    _locations = await db.getAllLocations();
    _selectedLocationId ??= locationIds.first;
    final selectedIds = _selectedLocationId == 'ALL'
        ? locationIds
        : [_selectedLocationId!];

    final category = authService.currentCategory ?? AppConstants.categoryFillingStation;

    final sales = selectedIds.length == 1
      ? await db.getSalesByLocationAndCategory(selectedIds.first, category)
      : await db.getSalesByLocationsAndCategory(selectedIds, category);

    final items = selectedIds.length == 1
      ? await db.getItemsByLocationAndCategory(selectedIds.first, category)
      : await db.getItemsByLocationsAndCategory(selectedIds, category);

    final receivings = selectedIds.length == 1
      ? await db.getReceivingsByLocationAndCategory(selectedIds.first, category)
      : await db.getReceivingsByLocationsAndCategory(selectedIds, category);

    final filteredSales = _filterSalesByRange(sales);
    final saleItemIds = filteredSales.map((sale) => sale.id).toList();
    final saleItems = saleItemIds.isEmpty
        ? <SaleItem>[]
        : await db.getSaleItemsBySaleIds(saleItemIds);

    setState(() {
      _sales = filteredSales;
      _saleItems = saleItems;
      _items = items;
      _receivings = _filterReceivingsByRange(receivings);
      _isLoading = false;
    });
  }

  List<Sale> _filterSalesByRange(List<Sale> sales) {
    final range = _getRange();
    return sales
        .where((sale) =>
            !sale.isSuspended &&
            sale.timestamp.isAfter(range.start) &&
            sale.timestamp.isBefore(range.end))
        .toList();
  }

  List<Receiving> _filterReceivingsByRange(List<Receiving> receivings) {
    final range = _getRange();
    return receivings
        .where((rec) =>
            rec.timestamp.isAfter(range.start) &&
            rec.timestamp.isBefore(range.end))
        .toList();
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
          end: DateTime(yesterday.year, yesterday.month, yesterday.day, 23, 59, 59),
        );
      case _ReportRange.last7Days:
        final start = now.subtract(const Duration(days: 6));
        return _DateRange(
          start: DateTime(start.year, start.month, start.day),
          end: DateTime(now.year, now.month, now.day, 23, 59, 59),
        );
      case _ReportRange.lastMonth:
        final firstDayThisMonth = DateTime(now.year, now.month, 1);
        final lastMonth = DateTime(firstDayThisMonth.year, firstDayThisMonth.month - 1, 1);
        final endLastMonth = DateTime(firstDayThisMonth.year, firstDayThisMonth.month, 0, 23, 59, 59);
        return _DateRange(
          start: lastMonth,
          end: endLastMonth,
        );
      case _ReportRange.lastYear:
        final start = DateTime(now.year - 1, 1, 1);
        final end = DateTime(now.year - 1, 12, 31, 23, 59, 59);
        return _DateRange(start: start, end: end);
      case _ReportRange.custom:
        final start = _customStart ?? DateTime(now.year, now.month, now.day);
        final end = _customEnd ?? DateTime(now.year, now.month, now.day, 23, 59, 59);
        return _DateRange(start: start, end: end);
    }
  }

  double _sumByPayment(String method) {
    return _sales
        .where((sale) => sale.paymentMethod == method)
        .fold(0, (sum, sale) => sum + sale.totalAmount);
  }

  double _totalSales() => _sales.fold(0, (sum, sale) => sum + sale.totalAmount);

  _ProfitSummary _profitSummary() {
    double profit = 0;
    double loss = 0;

    for (final item in _saleItems) {
      final delta = (item.sellingPrice - item.buyingPrice) * item.quantity;
      if (delta >= 0) {
        profit += delta;
      } else {
        loss += delta.abs();
      }
    }

    return _ProfitSummary(profit: profit, loss: loss);
  }

  _InventorySummary _inventorySummary() {
    double buyingValue = 0;
    double sellingValue = 0;

    for (final item in _items) {
      buyingValue += item.buyingPrice * item.quantity;
      sellingValue += item.sellingPrice * item.quantity;
    }

    return _InventorySummary(buyingValue: buyingValue, sellingValue: sellingValue);
  }

  Future<void> _pickCustomRange() async {
    final start = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (start == null) return;

    final end = await showDatePicker(
      context: context,
      initialDate: start,
      firstDate: start,
      lastDate: DateTime.now(),
    );

    if (end == null) return;

    setState(() {
      _customStart = start;
      _customEnd = end;
      _range = _ReportRange.custom;
    });
    await _loadReportData();
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
      length: 7,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Reports'),
          backgroundColor: AppTheme.primaryOrange,
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Sales Summary'),
              Tab(text: 'Sales Graph'),
              Tab(text: 'Sales Detail'),
              Tab(text: 'Profit/Loss'),
              Tab(text: 'Inventory'),
              Tab(text: 'Receivings'),
              Tab(text: 'Low Stock'),
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
                        ],
                      ),
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
                          return const Center(child: Text('No sales data for this period', style: TextStyle(color: AppTheme.darkGray)));
                        }
                        final maxY = salesByDate.values.fold<double>(0, (prev, e) => e > prev ? e : prev) * 1.2;
                        return Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text('Total Sales by Date', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
                                            if (idx < 0 || idx >= sortedDates.length) return const SizedBox();
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
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildFilters(AuthService authService) {
    final rangeLabel = _rangeLabel();
    final canSelectAll = authService.isSuperAdmin;
    final locationIds = authService.allowedLocationIds;
    final locations = _locations.where((loc) => locationIds.contains(loc.id)).toList();

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
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
                    child: Text(loc.name),
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

  String _rangeLabel() {
    if (_range != _ReportRange.custom || _customStart == null || _customEnd == null) {
      return '';
    }
    final format = DateFormat('dd MMM yyyy');
    return '${format.format(_customStart!)} - ${format.format(_customEnd!)}';
  }

  Widget _buildSalesSummary() {
    final authService = Provider.of<AuthService>(context, listen: false);
    final isFillingStation = authService.currentCategory == AppConstants.categoryFillingStation;
    final employees = isFillingStation
        ? _sales.map((s) => s.employeeName).toSet().toList()
        : [];
    final employeeSales = <String, List<Sale>>{};
    for (final emp in employees) {
      employeeSales[emp] = _sales.where((s) => s.employeeName == emp).toList();
    }
    double sumA = 0, sumL = 0, sumT = 0;
    double sumCash = 0, sumMpesa = 0, sumEquity = 0, sumCredit = 0;

    Widget buildEmployeeRow(String emp, List<Sale> sales) {
      // Placeholder for A/L/T values and meter readings
      // In real implementation, fetch meter readings and calculate A/L/T
      // Here, just show dummy values for demo
      final a = 0.0, l = 0.0, t = 0.0;
      final cash = sales.where((s) => s.paymentMethod == AppConstants.paymentCash).fold(0.0, (s, e) => s + e.totalAmount);
      final mpesa = sales.where((s) => s.paymentMethod == AppConstants.paymentMpesa).fold(0.0, (s, e) => s + e.totalAmount);
      final equity = sales.where((s) => s.paymentMethod == AppConstants.paymentEquity).fold(0.0, (s, e) => s + e.totalAmount);
      final credit = sales.where((s) => s.paymentMethod == AppConstants.paymentCredit).fold(0.0, (s, e) => s + e.totalAmount);
      sumA += a; sumL += l; sumT += t;
      sumCash += cash; sumMpesa += mpesa; sumEquity += equity; sumCredit += credit;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(flex: 2, child: Text(emp)),
            Expanded(child: Text(a.toStringAsFixed(2))),
            Expanded(child: Text(l.toStringAsFixed(2))),
            Expanded(child: Text(t.toStringAsFixed(2))),
            Expanded(child: Text(cash.toStringAsFixed(0))),
            Expanded(child: Text(mpesa.toStringAsFixed(0))),
            Expanded(child: Text(equity.toStringAsFixed(0))),
            Expanded(child: Text(credit.toStringAsFixed(0))),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSummaryCard('Cash', _sumByPayment(AppConstants.paymentCash)),
        _buildSummaryCard('Mpesa Till', _sumByPayment(AppConstants.paymentMpesa)),
        _buildSummaryCard('Equity Paybill', _sumByPayment(AppConstants.paymentEquity)),
        _buildSummaryCard('Credit', _sumByPayment(AppConstants.paymentCredit)),
        const Divider(height: 32),
        _buildSummaryCard('Grand Total', _totalSales(), highlight: true),
        if (isFillingStation && employees.isNotEmpty) ...[
          const SizedBox(height: 24),
          const Text('Filling Station Breakdown', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            color: AppTheme.primaryOrange.withOpacity(0.08),
            child: Row(
              children: const [
                Expanded(flex: 2, child: Text('Employee', style: TextStyle(fontWeight: FontWeight.bold))),
                Expanded(child: Text('A', style: TextStyle(fontWeight: FontWeight.bold))),
                Expanded(child: Text('L', style: TextStyle(fontWeight: FontWeight.bold))),
                Expanded(child: Text('T', style: TextStyle(fontWeight: FontWeight.bold))),
                Expanded(child: Text('Cash', style: TextStyle(fontWeight: FontWeight.bold))),
                Expanded(child: Text('Mpesa', style: TextStyle(fontWeight: FontWeight.bold))),
                Expanded(child: Text('Equity', style: TextStyle(fontWeight: FontWeight.bold))),
                Expanded(child: Text('Credit', style: TextStyle(fontWeight: FontWeight.bold))),
              ],
            ),
          ),
          ...employees.map((emp) => buildEmployeeRow(emp, employeeSales[emp]!)),
          const Divider(height: 24),
          Row(
            children: [
              const Expanded(flex: 2, child: Text('Grand Total', style: TextStyle(fontWeight: FontWeight.bold))),
              Expanded(child: Text('${sumA.toStringAsFixed(2)}', style: TextStyle(fontWeight: FontWeight.bold))),
              Expanded(child: Text('${sumL.toStringAsFixed(2)}', style: TextStyle(fontWeight: FontWeight.bold))),
              Expanded(child: Text('${sumT.toStringAsFixed(2)}', style: TextStyle(fontWeight: FontWeight.bold))),
              Expanded(child: Text('${sumCash.toStringAsFixed(0)}', style: TextStyle(fontWeight: FontWeight.bold))),
              Expanded(child: Text('${sumMpesa.toStringAsFixed(0)}', style: TextStyle(fontWeight: FontWeight.bold))),
              Expanded(child: Text('${sumEquity.toStringAsFixed(0)}', style: TextStyle(fontWeight: FontWeight.bold))),
              Expanded(child: Text('${sumCredit.toStringAsFixed(0)}', style: TextStyle(fontWeight: FontWeight.bold))),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildSalesDetail() {
    final format = DateFormat('dd MMM yyyy, hh:mm a');
    if (_sales.isEmpty) {
      return const Center(
        child: Text('No sales in this period', style: TextStyle(color: AppTheme.darkGray)),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _sales.length,
      separatorBuilder: (context, i) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final sale = _sales[i];
        final items = _saleItems.where((item) => item.saleId == sale.id).toList();
        final profit = sale.profit ?? 0.0;
        final isLoss = profit < 0;
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 8),
            childrenPadding: const EdgeInsets.only(left: 24, right: 8, bottom: 8),
            title: Row(
              children: [
                Expanded(flex: 2, child: Text(sale.saleId, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), overflow: TextOverflow.ellipsis)),
                Expanded(flex: 2, child: Text(format.format(sale.timestamp), style: const TextStyle(fontSize: 13))),
                Expanded(child: Text('KES ${sale.totalAmount.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w600))),
                Expanded(child: Text('Paid: ${sale.amountPaid.toStringAsFixed(0)}', style: const TextStyle(fontSize: 12))),
                Expanded(child: Text('Chg: ${(sale.amountPaid - sale.totalAmount).toStringAsFixed(0)}', style: const TextStyle(fontSize: 12))),
                Expanded(child: Text((isLoss ? 'Loss: ' : 'Profit: ') + profit.toStringAsFixed(0), style: TextStyle(fontSize: 12, color: isLoss ? AppTheme.error : AppTheme.success, fontWeight: FontWeight.w600))),
                Expanded(child: Text(sale.paymentMethod, style: const TextStyle(fontSize: 12))),
                Expanded(child: Text(sale.employeeName ?? '', style: const TextStyle(fontSize: 12))),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.print, size: 18, color: AppTheme.primaryOrange),
                      tooltip: 'Print Receipt',
                      onPressed: () => _printReceipt(sale),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit, size: 18, color: AppTheme.primaryBlue),
                      tooltip: 'Edit Sale',
                      onPressed: () => _editSale(sale),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 18, color: AppTheme.error),
                      tooltip: 'Delete Sale',
                      onPressed: () => _deleteSale(sale),
                    ),
                  ],
                ),
              ],
            ),
            children: [
              if (items.isNotEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Items:', style: TextStyle(fontWeight: FontWeight.bold)),
                    ...items.map((item) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              Expanded(child: Text(item.itemName)),
                              Text('x${item.quantity.toStringAsFixed(0)}'),
                              const SizedBox(width: 8),
                              Text('KES ${item.sellingPrice.toStringAsFixed(0)}'),
                            ],
                          ),
                        )),
                  ],
                ),
              if (sale.notes != null && sale.notes!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('Notes: ${sale.notes!}', style: const TextStyle(fontSize: 12)),
                ),
            ],
          ),
        );
      },
    );
  }

  // --- Actions for Detailed Sales Report ---
  void _printReceipt(sale) {
    // TODO: Implement print receipt logic
    // Example: showDialog or call print service
  }

  void _editSale(sale) {
    // TODO: Implement edit sale logic
    // Example: navigate to sale edit page
  }

  void _deleteSale(sale) async {
    // TODO: Implement delete sale logic
    // Example: show confirmation and delete from db
  }

  Widget _buildProfitLoss() {
    // 11.2.A Summary Profit/Loss
    final summary = _profitSummary();
    final net = summary.profit - summary.loss;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Profit/Loss Summary', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 12),
        _buildSummaryCard('Total Profit', summary.profit, highlight: true),
        _buildSummaryCard('Total Loss', summary.loss),
        const Divider(height: 32),
        _buildSummaryCard('Net Result', net, highlight: true),
        const SizedBox(height: 32),
        const Text('Profit/Loss by Date', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 12),
        SizedBox(height: 260, child: _buildProfitLossGraph()),
      ],
    );
  }

  Widget _buildProfitLossGraph() {
    // 11.2.B Graphical Profit/Loss
    // Aggregate profit/loss by date
    final Map<String, double> profitByDate = {};
    final dateFormat = DateFormat('yyyy-MM-dd');
    for (final sale in _sales) {
      final dateStr = dateFormat.format(sale.timestamp);
      final profit = sale.profit ?? 0.0;
      profitByDate[dateStr] = (profitByDate[dateStr] ?? 0) + profit;
    }
    final sortedDates = profitByDate.keys.toList()..sort();
    if (sortedDates.isEmpty) {
      return const Center(child: Text('No data for this period', style: TextStyle(color: AppTheme.darkGray)));
    }
    final maxY = profitByDate.values.map((e) => e.abs()).fold<double>(0, (prev, e) => e > prev ? e : prev) * 1.2;
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
                if (idx < 0 || idx >= sortedDates.length) return const SizedBox();
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
                  color: profitByDate[sortedDates[i]]! >= 0 ? Colors.green : Colors.red,
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
    // 11.3.A Summary Inventory
    final summary = _inventorySummary();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Inventory Value Summary', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 12),
        _buildSummaryCard('Total Value (Buying)', summary.buyingValue, highlight: true),
        _buildSummaryCard('Total Value (Selling)', summary.sellingValue),
        const SizedBox(height: 32),
        const Text('Detailed Inventory', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 12),
        _buildInventoryDetailTable(),
      ],
    );
  }

  Widget _buildInventoryDetailTable() {
    // 11.3.B Detailed Inventory Table
    if (_items.isEmpty) {
      return const Center(child: Text('No inventory items found', style: TextStyle(color: AppTheme.darkGray)));
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
        rows: _items.map((item) => DataRow(cells: [
          DataCell(Text(item.name)),
          DataCell(Text(item.barcode ?? '-')),
          DataCell(Text(item.quantity.toStringAsFixed(2))),
          DataCell(Text('KES ${item.buyingPrice.toStringAsFixed(2)}')),
          DataCell(Text('KES ${item.sellingPrice.toStringAsFixed(2)}')),
          DataCell(Text('KES ${(item.buyingPrice * item.quantity).toStringAsFixed(2)}')),
          DataCell(Text('KES ${(item.sellingPrice * item.quantity).toStringAsFixed(2)}')),
        ])).toList(),
      ),
    );
  }

  Widget _buildReceivingsSummary() {
    // 11.4.A Summary Receivings
    final total = _receivings.fold(0.0, (sum, rec) => sum + rec.totalAmount);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Receivings Summary', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 12),
        _buildSummaryCard('Total Receivings', total, highlight: true),
        const SizedBox(height: 32),
        const Text('Detailed Receivings', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 12),
        _buildReceivingsDetailTable(),
      ],
    );
  }

  Widget _buildReceivingsDetailTable() {
    // 11.4.B Detailed Receivings Table
    if (_receivings.isEmpty) {
      return const Center(child: Text('No receivings found', style: TextStyle(color: AppTheme.darkGray)));
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
                Expanded(flex: 2, child: Text(rec.receivingId, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), overflow: TextOverflow.ellipsis)),
                Expanded(flex: 2, child: Text(DateFormat('dd MMM yyyy, hh:mm a').format(rec.timestamp), style: const TextStyle(fontSize: 13))),
                Expanded(child: Text('KES ${rec.totalAmount.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w600))),
                Expanded(child: Text(rec.employeeName ?? '', style: const TextStyle(fontSize: 12))),
              ],
            ),
            children: [
              if (items.isNotEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Items Received:', style: TextStyle(fontWeight: FontWeight.bold)),
                    ...items.map((item) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              Expanded(child: Text(item.name)),
                              Text('Qty: ${item.quantity.toStringAsFixed(2)}'),
                              const SizedBox(width: 8),
                              Text('Buy: KES ${item.buyingPrice.toStringAsFixed(2)}'),
                              const SizedBox(width: 8),
                              Text('Total: KES ${(item.buyingPrice * item.quantity).toStringAsFixed(2)}'),
                            ],
                          ),
                        )),
                  ],
                ),
              if (rec.notes != null && rec.notes!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('Notes: ${rec.notes!}', style: const TextStyle(fontSize: 12)),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLowStockReport() {
    final lowStockItems = _items
        .where((item) => item.quantity <= item.reorderLevel)
        .toList()
      ..sort((a, b) => (a.quantity - a.reorderLevel).compareTo(b.quantity - b.reorderLevel));

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
        ...lowStockItems.map(
          (item) {
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
                        color: isOutOfStock ? AppTheme.error : AppTheme.primaryOrange,
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
                                  color: isOutOfStock ? AppTheme.error : AppTheme.darkGray,
                                  fontWeight: isOutOfStock ? FontWeight.bold : FontWeight.normal,
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
          },
        ),
      ],
    );
  }

  Widget _buildSummaryCard(String title, double value, {bool highlight = false}) {
    return Card(
      child: ListTile(
        title: Text(title),
        trailing: Text(
          'KES ${value.toStringAsFixed(0)}',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: highlight ? AppTheme.primaryOrange : AppTheme.primaryBlack,
          ),
        ),
      ),
    );
  }
}

class _DateRange {
  final DateTime start;
  final DateTime end;

  const _DateRange({required this.start, required this.end});
}

class _ProfitSummary {
  final double profit;
  final double loss;

  const _ProfitSummary({required this.profit, required this.loss});
}

class _InventorySummary {
  final double buyingValue;
  final double sellingValue;

  const _InventorySummary({required this.buyingValue, required this.sellingValue});
}
