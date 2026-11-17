import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/toast_utils.dart';
import '../../data/database/app_database.dart';
import '../../services/auth_service.dart';
import '../sales/sales_page.dart';

class SuspendedSalesPage extends StatefulWidget {
  const SuspendedSalesPage({super.key});

  @override
  State<SuspendedSalesPage> createState() => _SuspendedSalesPageState();
}

class _SuspendedSalesPageState extends State<SuspendedSalesPage> {
  List<Sale> _sales = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSuspendedSales();
  }

  Future<void> _loadSuspendedSales() async {
    setState(() => _isLoading = true);
    final authService = Provider.of<AuthService>(context, listen: false);
    final db = Provider.of<AppDatabase>(context, listen: false);
    final locationIds = authService.allowedLocationIds;

    if (locationIds.isEmpty) {
      setState(() {
        _sales = [];
        _isLoading = false;
      });
      return;
    }

    final category = authService.currentCategory ?? AppConstants.categoryFillingStation;
    final sales = await db.getSuspendedSalesByCategory(locationIds.first, category);
    setState(() {
      _sales = sales;
      _isLoading = false;
    });
  }

  Future<void> _resumeSale(Sale sale) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => SalesPage(resumeSaleId: sale.id),
      ),
    );

    if (result == true) {
      ToastUtils.showSuccess('Sale resumed');
      await _loadSuspendedSales();
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd MMM yyyy, hh:mm a');

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _loadSuspendedSales,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _sales.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.pause_circle, size: 64, color: AppTheme.darkGray),
                        SizedBox(height: 16),
                        Text(
                          'No suspended sales',
                          style: TextStyle(fontSize: 16, color: AppTheme.darkGray),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _sales.length,
                    itemBuilder: (context, index) {
                      final sale = _sales[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          leading: const Icon(Icons.pause_circle, color: AppTheme.primaryOrange),
                          title: Text('Sale ${sale.saleId}'),
                          subtitle: Text(dateFormat.format(sale.timestamp)),
                          trailing: ElevatedButton(
                            onPressed: () => _resumeSale(sale),
                            child: const Text('Resume'),
                          ),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}
