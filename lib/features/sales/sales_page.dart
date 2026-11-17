import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:drift/drift.dart' as drift;
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/toast_utils.dart';
import '../../data/database/app_database.dart';
import '../../services/auth_service.dart';
import '../../widgets/receipt_template.dart';
import '../../services/receipt_print_service.dart';
import '../meter_readings/meter_readings_dialog.dart';

class SalesPage extends StatefulWidget {
  final String? resumeSaleId;

  const SalesPage({
    super.key,
    this.resumeSaleId,
  });

  @override
  State<SalesPage> createState() => _SalesPageState();
}

class _SalesPageState extends State<SalesPage> {
  final _searchController = TextEditingController();
  final _amountPaidController = TextEditingController();
  final _suspendNotesController = TextEditingController();
  final _customerSearchController = TextEditingController();
  final _uuid = const Uuid();

  List<Item> _searchResults = [];
  List<Customer> _customerResults = [];
  final List<_SaleCartItem> _cartItems = [];
  String _paymentMethod = AppConstants.paymentCash;
  Customer? _selectedCustomer;
  bool _isLoading = false;
  bool _isCompleting = false;
  bool _promptedOpeningReadings = false;
  String? _lastCategory;
  double? _paymentChange;
  double? _paymentBalance;
  String? _paymentError;
  String _pricingType = AppConstants.pricingRetail;

  Sale? _editingSale;

  @override
  void initState() {
    super.initState();
    if (widget.resumeSaleId != null) {
      _loadSuspendedSale(widget.resumeSaleId!);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybePromptOpeningReadings();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final authService = Provider.of<AuthService>(context, listen: false);
    final currentCategory = authService.currentCategory;
    if (_lastCategory != currentCategory) {
      _lastCategory = currentCategory;
      _promptedOpeningReadings = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _maybePromptOpeningReadings();
      });
    }
  }

  Future<void> _maybePromptOpeningReadings() async {
    if (_promptedOpeningReadings) {
      return;
    }

    final authService = Provider.of<AuthService>(context, listen: false);
    if (authService.currentCategory != AppConstants.categoryFillingStation) {
      return;
    }
    final db = Provider.of<AppDatabase>(context, listen: false);
    final locationId = authService.currentEmployee?.locationId;
    final employeeId = authService.currentEmployee?.id;
    if (locationId == null || employeeId == null) {
      return;
    }

    final category = authService.currentCategory ?? AppConstants.categoryFillingStation;
    final latestType = await db.getLatestMeterReadingType(
      locationId,
      employeeId,
      category,
    );
    if (latestType == AppConstants.readingTypeOpening) {
      authService.markMeterReadingsOpened();
      return;
    }
    if (latestType == AppConstants.readingTypeClosing) {
      authService.markMeterReadingsClosed();
    }

    if (authService.hasOpenedMeterReadings) {
      return;
    }

    _promptedOpeningReadings = true;
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const MeterReadingsDialog(
        readingType: AppConstants.readingTypeOpening,
      ),
    );

    if (saved == true) {
      authService.markMeterReadingsOpened();
      if (mounted) {
        setState(() {});
      }
    }
  }

  @override
  void dispose() {
    _disposeCartItems();
    _searchController.dispose();
    _amountPaidController.dispose();
    _suspendNotesController.dispose();
    _customerSearchController.dispose();
    super.dispose();
  }

  void _disposeCartItems() {
    for (final item in _cartItems) {
      item.quantityController.dispose();
    }
  }

  Future<void> _loadSuspendedSale(String saleId) async {
    setState(() => _isLoading = true);
    final db = Provider.of<AppDatabase>(context, listen: false);
    final sale = await db.getSale(saleId);
    if (sale == null || !sale.isSuspended) {
      setState(() => _isLoading = false);
      return;
    }

    final saleItems = await db.getSaleItems(sale.id);
    setState(() {
      _editingSale = sale;
      // If paymentMethod is 'Suspended', use last used or default to Cash
      if (sale.paymentMethod == 'Suspended' || sale.paymentMethod.isEmpty) {
        _paymentMethod = _paymentMethod.isNotEmpty ? _paymentMethod : AppConstants.paymentCash;
      } else {
        _paymentMethod = sale.paymentMethod;
      }
      _amountPaidController.text = sale.amountPaid.toStringAsFixed(0);
      if (saleItems.isNotEmpty) {
        _pricingType = saleItems.first.pricingType;
      }
      _cartItems
        ..clear()
        ..addAll(
          saleItems.map(
            (item) => _SaleCartItem(
              itemId: item.itemId,
              itemName: item.itemName,
              buyingPrice: item.buyingPrice,
              sellingPrice: item.sellingPrice,
              wholesalePrice: item.sellingPrice,
              quantity: item.quantity,
              pricingType: item.pricingType,
              saleMode: _FuelSaleMode.liters,
              quantityController: TextEditingController(
                text: _formatNumber(item.quantity),
              ),
            ),
          ),
        );
      _isLoading = false;
    });
  }

  Future<void> _searchItems(String query) async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final db = Provider.of<AppDatabase>(context, listen: false);
    final locationId = _getCurrentLocationId(authService);
    if (locationId == null) {
      return;
    }

    if (query.trim().isEmpty) {
      setState(() => _searchResults = []);
      return;
    }

    final category = authService.currentCategory ?? AppConstants.categoryFillingStation;
    final results = await db.searchItemsByCategory(locationId, category, query.trim());
    setState(() => _searchResults = results);
  }

  String? _getCurrentLocationId(AuthService authService) {
    final allowed = authService.allowedLocationIds;
    if (allowed.isEmpty) {
      ToastUtils.showError('No location assigned.');
      return null;
    }
    return allowed.first;
  }

  void _addItemToCart(Item item) {
    final existingIndex = _cartItems.indexWhere((i) => i.itemId == item.id);
    if (existingIndex != -1) {
      setState(() {
        final existing = _cartItems[existingIndex];
        final increment = existing.saleMode == _FuelSaleMode.price
            ? _getUnitPrice(existing)
            : 1;
        final nextQuantity = existing.quantity + increment;
        existing.quantityController.text = _formatNumber(nextQuantity);
        _cartItems[existingIndex] = existing.copyWith(quantity: nextQuantity);
      });
      return;
    }

    final authService = Provider.of<AuthService>(context, listen: false);
    final isFillingStation =
        authService.currentCategory == AppConstants.categoryFillingStation;
    setState(() {
      _cartItems.add(
        _SaleCartItem(
          itemId: item.id,
          itemName: item.name,
          buyingPrice: item.buyingPrice,
          sellingPrice: item.sellingPrice,
          wholesalePrice: item.wholesalePrice,
          quantity: 1,
          pricingType: _pricingType,
          saleMode: isFillingStation ? _FuelSaleMode.price : _FuelSaleMode.liters,
          quantityController: TextEditingController(text: _formatNumber(1)),
        ),
      );
    });
  }

  void _selectSearchItem(Item item) {
    _addItemToCart(item);
    setState(() {
      _searchResults = [];
      _searchController.clear();
    });
    FocusScope.of(context).unfocus();
  }

  void _updateCartQuantity(_SaleCartItem item, double quantity, {bool syncText = false}) {
    if (quantity <= 0) {
      setState(() => _cartItems.remove(item));
      return;
    }
    setState(() {
      if (syncText) {
        item.quantityController.text = _formatNumber(quantity);
      }
      final index = _cartItems.indexOf(item);
      _cartItems[index] = item.copyWith(quantity: quantity);
    });
  }

  void _updateCartInput(_SaleCartItem item, String value) {
    final parsed = _parseNumber(value);
    if (parsed == null) {
      return;
    }
    _updateCartQuantity(item, parsed);
  }

  void _setPricingType(String pricingType) {
    setState(() {
      _pricingType = pricingType;
      for (var i = 0; i < _cartItems.length; i++) {
        _cartItems[i] = _cartItems[i].copyWith(pricingType: pricingType);
      }
    });
  }

  double _calculateItemSubtotal(_SaleCartItem item) {
    final price = _getUnitPrice(item);
    if (item.saleMode == _FuelSaleMode.price) {
      return item.quantity;
    }
    return price * item.quantity;
  }

  double _getUnitPrice(_SaleCartItem item) {
    final authService = Provider.of<AuthService>(context, listen: false);
    final isFillingStation =
        authService.currentCategory == AppConstants.categoryFillingStation;
    if (isFillingStation && item.saleMode == _FuelSaleMode.price) {
      return item.sellingPrice;
    }
    return item.pricingType == AppConstants.pricingWholesale
        ? item.wholesalePrice
        : item.sellingPrice;
  }

  double _getEffectiveQuantity(_SaleCartItem item) {
    final price = _getUnitPrice(item);
    if (item.saleMode == _FuelSaleMode.price) {
      if (price <= 0) {
        return 0;
      }
      return item.quantity / price;
    }
    return item.quantity;
  }

  double _calculateTotal() {
    return _cartItems.fold(0, (sum, item) => sum + _calculateItemSubtotal(item));
  }

  String _formatNumber(double value) {
    final text = value.toStringAsFixed(3);
    return text.replaceFirst(RegExp(r'\.?0+$'), '');
  }

  double? _parseNumber(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return double.tryParse(trimmed.replaceAll(',', '.')) ?? 0;
  }

  double _calculateProfit() {
    return _cartItems.fold(
      0,
      (sum, item) {
        final price = _getUnitPrice(item);
        final qty = _getEffectiveQuantity(item);
        return sum + ((price - item.buyingPrice) * qty);
      },
    );
  }

  Future<void> _completeSale({required bool suspend}) async {
        // Prevent finishing sales if there are suspended sales
        if (!suspend) {
          final db = Provider.of<AppDatabase>(context, listen: false);
          final authService = Provider.of<AuthService>(context, listen: false);
          final locationId = _getCurrentLocationId(authService);
          final category = authService.currentCategory ?? AppConstants.categoryFillingStation;
          if (locationId != null) {
            final suspendedSales = await db.getSuspendedSalesByCategory(locationId, category);
            if (suspendedSales.isNotEmpty) {
              ToastUtils.showError('You have suspended sales. Please finish them before completing a new sale.');
              return;
            }
          }
        }
    if (_cartItems.isEmpty) {
      ToastUtils.showError('Add at least one item.');
      return;
    }

    final authService = Provider.of<AuthService>(context, listen: false);
    if (!authService.hasPermission('canProcessSales') && authService.isEmployee) {
      ToastUtils.showError('You do not have permission to process sales.');
      return;
    }

    if (!authService.isEmployee) {
      ToastUtils.showError('Admins cannot process sales.');
      return;
    }

    if (authService.currentCategory == AppConstants.categoryFillingStation &&
        authService.hasClosedMeterReadings) {
      ToastUtils.showError('Selling is closed for this session. Log out to continue.');
      return;
    }

    final locationId = _getCurrentLocationId(authService);
    if (locationId == null) {
      return;
    }

    final total = _calculateTotal();
    final amountPaid = double.tryParse(_amountPaidController.text.trim()) ?? 0;

    if (!suspend) {
      if (_paymentMethod == AppConstants.paymentCredit) {
        if (_selectedCustomer == null) {
          ToastUtils.showError('Select a customer for credit sales.');
          return;
        }
        if (amountPaid >= total) {
          ToastUtils.showError('Credit requires an outstanding balance.');
          return;
        }
      } else if (amountPaid < total) {
        ToastUtils.showError('Amount paid cannot be less than total.');
        return;
      }
    }

    setState(() => _isCompleting = true);
    final db = Provider.of<AppDatabase>(context, listen: false);

    try {
      final shouldPop = widget.resumeSaleId != null;
      final now = DateTime.now();
      final saleId = _editingSale?.saleId ?? _buildSaleId(locationId, now);
      final saleDbId = _editingSale?.id ?? _uuid.v4();

      final sale = SalesCompanion(
        id: drift.Value(saleDbId),
        saleId: drift.Value(saleId),
        locationId: drift.Value(locationId),
        category: drift.Value(authService.currentCategory ?? AppConstants.categoryFillingStation),
        employeeId: drift.Value(authService.currentEmployee!.id),
        paymentMethod: drift.Value(suspend ? 'Suspended' : _paymentMethod),
        totalAmount: drift.Value(total),
        amountPaid: drift.Value(suspend ? 0 : amountPaid),
        changeGiven: drift.Value(suspend
            ? 0
            : (_paymentMethod == AppConstants.paymentCredit
                ? 0
                : (amountPaid - total))),
        profit: drift.Value(_calculateProfit()),
        isSuspended: drift.Value(suspend),
        suspensionNotes: drift.Value(suspend ? _suspendNotesController.text.trim() : null),
        timestamp: drift.Value(now),
        syncedAt: const drift.Value(null),
      );

      if (_editingSale == null) {
        await db.insertSale(sale);
      } else {
        await db.updateSale(sale);
        await db.deleteSaleItems(saleDbId);
      }

      for (final item in _cartItems) {
        final qty = _getEffectiveQuantity(item);
        await db.insertSaleItem(
          SaleItemsCompanion(
            id: drift.Value(_uuid.v4()),
            saleId: drift.Value(saleDbId),
            itemId: drift.Value(item.itemId),
            itemName: drift.Value(item.itemName),
            quantity: drift.Value(qty),
            buyingPrice: drift.Value(item.buyingPrice),
            sellingPrice: drift.Value(
              _getUnitPrice(item),
            ),
            pricingType: drift.Value(item.pricingType),
            subtotal: drift.Value(_calculateItemSubtotal(item)),
          ),
        );
      }

      if (!suspend) {
        for (final item in _cartItems) {
          final dbItem = await db.getItem(item.itemId);
          if (dbItem == null) continue;
          final qty = _getEffectiveQuantity(item);
          final newQty = dbItem.quantity - qty;
          if (newQty < 0) {
            ToastUtils.showError('Not enough stock for ${item.itemName}.');
            setState(() => _isCompleting = false);
            return;
          }
          await db.updateItemQuantity(item.itemId, newQty);
        }

        if (_paymentMethod == AppConstants.paymentCredit && _selectedCustomer != null) {
          final balance = total - amountPaid;
          await db.insertCredit(
            CreditsCompanion(
              id: drift.Value(_uuid.v4()),
              customerId: drift.Value(_selectedCustomer!.id),
              saleId: drift.Value(saleDbId),
              locationId: drift.Value(locationId),
              category: drift.Value(authService.currentCategory ?? AppConstants.categoryFillingStation),
              totalOwed: drift.Value(total),
              amountPaid: drift.Value(amountPaid),
              balance: drift.Value(balance),
              createdAt: drift.Value(now),
            ),
          );
        }

        ToastUtils.showSuccess('Sale completed');
        await _showReceiptPreview(saleId, now, total, amountPaid);
      } else {
        ToastUtils.showSuccess('Sale suspended');
      }

      _resetSale();
      if (shouldPop && mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      ToastUtils.showError('Unable to save sale. Please try again.');
    } finally {
      if (mounted) {
        setState(() => _isCompleting = false);
      }
    }
  }

  String _buildSaleId(String locationId, DateTime now) {
    final timestamp = DateFormat(AppConstants.dateFormatSaleId).format(now);
    final shortLoc = locationId.length >= 4 ? locationId.substring(0, 4) : locationId;
    return '${shortLoc.toUpperCase()}-$timestamp-${_uuid.v4().substring(0, 4)}';
  }

  Future<void> _showReceiptPreview(
    String receiptId,
    DateTime timestamp,
    double totalAmount,
    double amountPaid,
  ) async {
    final db = Provider.of<AppDatabase>(context, listen: false);
    final authService = Provider.of<AuthService>(context, listen: false);
    final locationId = _getCurrentLocationId(authService);
    if (locationId == null) return;
    final location = await db.getLocation(locationId);
    if (location == null) return;

    final List<ReceiptItem> items = _cartItems
        .map(
          (item) => ReceiptItem(
            name: item.itemName,
            quantity: _getEffectiveQuantity(item),
            price: _getUnitPrice(item),
            total: _calculateItemSubtotal(item),
          ),
        )
        .toList();

    if (!mounted) return;
    final isCredit = _paymentMethod == AppConstants.paymentCredit;
    final outstandingBalance = isCredit ? (totalAmount - amountPaid) : null;
    final changeGiven = isCredit ? null : (amountPaid - totalAmount);
    final printData = ReceiptPrintData(
      location: location,
      receiptId: receiptId,
      timestamp: timestamp,
      employeeName:
          '${authService.currentEmployee?.firstName ?? ''} ${authService.currentEmployee?.surname ?? ''}',
      items: items
          .map(
            (item) => ReceiptPrintItem(
              name: item.name,
              quantity: item.quantity,
              price: item.price,
            ),
          )
          .toList(),
      paymentMethod: _paymentMethod,
      totalAmount: totalAmount,
      amountPaid: amountPaid,
      changeGiven: changeGiven,
      outstandingBalance: outstandingBalance,
    );

    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ReceiptTemplate(
                location: location,
                receiptType: 'SALE',
                receiptId: receiptId,
                timestamp: timestamp,
                employeeName: printData.employeeName,
                items: items,
                paymentMethod: _paymentMethod,
                totalAmount: totalAmount,
                amountPaid: amountPaid,
                  changeGiven: changeGiven,
                  outstandingBalance: outstandingBalance,
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () async {
                  final service = ReceiptPrintService();
                  await service.showPrintOptions(context, printData);
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

  void _resetSale() {
    setState(() {
      _disposeCartItems();
      _cartItems.clear();
      _searchResults.clear();
      _searchController.clear();
      _amountPaidController.clear();
      _suspendNotesController.clear();
      _customerSearchController.clear();
      _selectedCustomer = null;
      _customerResults = [];
      _paymentMethod = AppConstants.paymentCash;
      _editingSale = null;
      _paymentChange = null;
      _paymentBalance = null;
      _paymentError = null;
      _pricingType = AppConstants.pricingRetail;
    });
  }

  void _applyPayment(double total, {required bool isCredit}) {
    final amountPaid = _parseNumber(_amountPaidController.text) ?? 0;
    if (isCredit) {
      if (amountPaid > total) {
        setState(() {
          _paymentChange = null;
          _paymentBalance = null;
          _paymentError = 'Amount paid cannot exceed total.';
        });
        return;
      }

      setState(() {
        _paymentChange = null;
        _paymentBalance = total - amountPaid;
        _paymentError = null;
      });
      return;
    }

    if (amountPaid < total) {
      setState(() {
        _paymentChange = null;
        _paymentBalance = null;
        _paymentError = 'Amount paid must be greater than total.';
      });
      return;
    }

    setState(() {
      _paymentChange = amountPaid - total;
      _paymentBalance = null;
      _paymentError = null;
    });
  }

  Future<void> _searchCustomers(String query) async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final db = Provider.of<AppDatabase>(context, listen: false);
    final locationId = _getCurrentLocationId(authService);
    if (locationId == null) return;
    if (query.trim().isEmpty) {
      setState(() {
        _selectedCustomer = null;
        _customerResults = [];
      });
      return;
    }

    final results = await db.searchCustomers(locationId, query.trim());
    setState(() {
      _customerResults = results;
    });
  }

  void _selectCustomer(Customer customer) {
    setState(() {
      _selectedCustomer = customer;
      _customerResults = [];
      _customerSearchController.text =
          '${customer.firstName} ${customer.lastName}'.trim();
    });
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth > 900;

    if (authService.isAdmin || authService.isSuperAdmin) {
      return Scaffold(
        body: const Center(
          child: Text('Admins cannot process sales.'),
        ),
      );
    }

    if (!authService.hasPermission('canProcessSales')) {
      return Scaffold(
        body: const Center(
          child: Text('You do not have permission to process sales.'),
        ),
      );
    }

    if (authService.currentCategory == AppConstants.categoryFillingStation &&
        !authService.hasOpenedMeterReadings) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.local_gas_station, size: 64, color: AppTheme.primaryOrange),
              const SizedBox(height: 12),
              const Text(
                'Opening meter readings required',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () async {
                  final saved = await showDialog<bool>(
                    context: context,
                    barrierDismissible: false,
                    builder: (context) => const MeterReadingsDialog(
                      readingType: AppConstants.readingTypeOpening,
                    ),
                  );
                  if (saved == true) {
                    authService.markMeterReadingsOpened();
                    setState(() {});
                  }
                },
                icon: const Icon(Icons.edit),
                label: const Text('Enter Readings'),
              ),
            ],
          ),
        ),
      );
    }

    if (authService.currentCategory == AppConstants.categoryFillingStation &&
        authService.hasClosedMeterReadings) {
      return Scaffold(
        body: const Center(
          child: Text('Selling is closed for this session. Log out to continue.'),
        ),
      );
    }

    return Scaffold(
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: isWide
                  ? Row(
                      children: [
        // ...existing code...
                    ),
            ),
    );
      // Prevent finishing sales if there are suspended sales
      if (!suspend) {
        final db = Provider.of<AppDatabase>(context, listen: false);
        final authService = Provider.of<AuthService>(context, listen: false);
        final locationId = _getCurrentLocationId(authService);
        final category = authService.currentCategory ?? AppConstants.categoryFillingStation;
        if (locationId != null) {
          final suspendedSales = await db.getSuspendedSalesByCategory(locationId, category);
          if (suspendedSales.isNotEmpty) {
            ToastUtils.showError('You have suspended sales. Please finish them before completing a new sale.');
            return;
          }
        }
      }
  }

  Widget _buildItemsPanel() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _editingSale == null ? 'New Sale' : 'Resumed Sale',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                labelText: 'Search by name or barcode',
                prefixIcon: Icon(Icons.search),
                suffixIcon: Icon(Icons.search),
              ),
              onChanged: _searchItems,
            ),
            const SizedBox(height: 12),
            if (_searchController.text.isNotEmpty) ...[
              if (_searchResults.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Center(
                    child: Text(
                      'No items found',
                      style: TextStyle(color: AppTheme.darkGray),
                    ),
                  ),
                )
              else
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: AppTheme.mediumGray),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _searchResults.length > 8 ? 8 : _searchResults.length,
                    separatorBuilder: (context, index) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = _searchResults[index];
                      return Scaffold(
                        body: _isLoading
                            ? const Center(child: CircularProgressIndicator())
                            : Padding(
                                padding: const EdgeInsets.all(16),
                                child: isWide
                                    ? Row(
                                        children: [
                                          Expanded(child: _buildItemsPanel()),
                                          const SizedBox(width: 16),
                                          Expanded(child: _buildCartPanel()),
                                        ],
                                      )
                                    : _buildCartPanel(isNarrow: true),
                              ),
                      );
                      // ...existing code...
    final showLitersTotal = isFillingStation &&
        _cartItems.any((item) => item.saleMode == _FuelSaleMode.price);
    final totalLiters = _cartItems.fold(
      0.0,
      (sum, item) => sum + _getEffectiveQuantity(item),
    );

    final cartContent = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
                // Pricing Type Selector
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Pricing Type',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.darkGray,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(
                              value: AppConstants.pricingRetail,
                              label: Text('Retail'),
                              icon: Icon(Icons.storefront, size: 16),
                            ),
                            ButtonSegment(
                              value: AppConstants.pricingWholesale,
                              label: Text('Wholesale'),
                              icon: Icon(Icons.business, size: 16),
                            ),
                          ],
                          selected: {_pricingType},
                          onSelectionChanged: (selection) {
                            _setPricingType(selection.first);
                          },
                        ),
                        if (isFillingStation)
                          const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text(
                              'Note: Wholesale applies only to liters mode',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppTheme.darkGray,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Cart Items
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.shopping_cart, size: 20, color: AppTheme.primaryOrange),
                            const SizedBox(width: 8),
                            Text(
                              'Cart Items (${_cartItems.length})',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (_cartItems.isEmpty)
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.all(24.0),
                              child: Column(
                                children: [
                                  Icon(Icons.shopping_cart_outlined, size: 48, color: AppTheme.mediumGray),
                                  SizedBox(height: 8),
                                  Text(
                                    'No items added',
                                    style: TextStyle(color: AppTheme.darkGray),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _cartItems.length,
                            separatorBuilder: (context, index) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final item = _cartItems[index];
                              final price = _getUnitPrice(item);
                              final isPriceMode = item.saleMode == _FuelSaleMode.price;
                              final liters = _getEffectiveQuantity(item);
                              return Container(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                child: isFillingStation
                                    ? Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Flexible(
                                                child: Text(
                                                  item.itemName,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 15,
                                                  ),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              if (item.pricingType == AppConstants.pricingWholesale) ...[
                                                const SizedBox(width: 6),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 2,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: AppTheme.primaryOrange,
                                                    borderRadius: BorderRadius.circular(4),
                                                  ),
                                                  child: const Text(
                                                    'W',
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      fontWeight: FontWeight.bold,
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'KES ${price.toStringAsFixed(0)} / L',
                                            style: const TextStyle(color: AppTheme.darkGray, fontSize: 13),
                                          ),
                                          if (item.pricingType == AppConstants.pricingWholesale)
                                            const Padding(
                                              padding: EdgeInsets.only(top: 2),
                                              child: Text(
                                                'Wholesale pricing',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: AppTheme.primaryOrange,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ),
                                          const SizedBox(height: 10),
                                          Row(
                                            children: [
                                              SegmentedButton<_FuelSaleMode>(
                                                segments: const [
                                                  ButtonSegment(
                                                    value: _FuelSaleMode.liters,
                                                    label: Text('Liters'),
                                                  ),
                                                  ButtonSegment(
                                                    value: _FuelSaleMode.price,
                                                    label: Text('Price'),
                                                  ),
                                                ],
                                                selected: {item.saleMode},
                                                onSelectionChanged: (selection) {
                                                  final nextMode = selection.first;
                                                  if (nextMode == item.saleMode) {
                                                    return;
                                                  }
                                                  final price = _getUnitPrice(item);
                                                  var nextQuantity = item.quantity;
                                                  if (nextMode == _FuelSaleMode.price) {
                                                    nextQuantity = item.quantity * price;
                                                  } else if (price > 0) {
                                                    nextQuantity = item.quantity / price;
                                                  }
                                                  setState(() {
                                                    final index = _cartItems.indexOf(item);
                                                    item.quantityController.text =
                                                        _formatNumber(nextQuantity);
                                                    _cartItems[index] = item.copyWith(
                                                      saleMode: nextMode,
                                                      quantity: nextQuantity,
                                                    );
                                                  });
                                                },
                                                style: SegmentedButton.styleFrom(
                                                  backgroundColor: Colors.grey[100],
                                                  selectedBackgroundColor: AppTheme.primaryOrange.withOpacity(0.15),
                                                  selectedForegroundColor: AppTheme.primaryOrange,
                                                  foregroundColor: AppTheme.darkGray,
                                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                                                  textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: TextField(
                                                  controller: item.quantityController,
                                                  decoration: InputDecoration(
                                                    labelText: isPriceMode ? 'Amount' : 'Liters',
                                                    prefixText: isPriceMode ? 'KES ' : null,
                                                    isDense: true,
                                                    contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
                                                    border: OutlineInputBorder(
                                                      borderRadius: BorderRadius.circular(8),
                                                    ),
                                                  ),
                                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                                  inputFormatters: [
                                                    FilteringTextInputFormatter.allow(
                                                      RegExp(r'^\d*\.?\d{0,3}'),
                                                    ),
                                                  ],
                                                  onChanged: (value) => _updateCartInput(item, value),
                                                  style: const TextStyle(fontSize: 15),
                                                ),
                                              ),
                                            ],
                                          ),
                                          if (isPriceMode)
                                            Padding(
                                              padding: const EdgeInsets.only(top: 6),
                                              child: Text(
                                                'Liters: ${liters.toStringAsFixed(2)}',
                                                style: const TextStyle(
                                                  color: AppTheme.darkGray,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.close, color: AppTheme.error),
                                      onPressed: () => _updateCartQuantity(item, 0, syncText: true),
                                      tooltip: 'Remove',
                                    ),
                                  ],
                                ),
                                        controller: item.quantityController,
                                        decoration: InputDecoration(
                                          labelText: isPriceMode ? 'Amount' : 'Liters',
                                          prefixText: isPriceMode ? 'KES ' : null,
                                        ),
                                        keyboardType:
                                            const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                        inputFormatters: [
                                          FilteringTextInputFormatter.allow(
                                            RegExp(r'^\d*\.?\d{0,3}'),
                                          ),
                                        ],
                                        onChanged: (value) =>
                                            _updateCartInput(item, value),
                                      ),
                                    ),
                                  ],
                                ),
                                if (isPriceMode)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text(
                                      'Liters: ${liters.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        color: AppTheme.darkGray,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                              ],
                            )
                        : ListTile(
                            title: Row(
                              children: [
                                Text(item.itemName),
                                if (item.pricingType == AppConstants.pricingWholesale) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppTheme.primaryOrange,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      'W',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 90,
                                  child: TextField(
                                    controller: item.quantityController,
                                    decoration: const InputDecoration(
                                      labelText: 'Qty',
                                      isDense: true,
                                    ),
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                    inputFormatters: [
                                      FilteringTextInputFormatter.allow(
                                        RegExp(r'^\d*\.?\d{0,3}'),
                                      ),
                                    ],
                                    onChanged: (value) => _updateCartInput(item, value),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: AppTheme.error, size: 20),
                                  onPressed: () =>
                                      _updateCartQuantity(item, 0, syncText: true),
                                ),
                              ],
                            ),
                          ),
                      );
                    },
                  ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Total Summary
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryBlack,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'TOTAL',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: 1,
                            ),
                          ),
                          Text(
                            'KES ${total.toStringAsFixed(0)}',
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryOrange,
                            ),
                          ),
                        ],
                      ),
                      if (showLitersTotal)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Total Liters',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white70,
                                ),
                              ),
                              Text(
                                '${totalLiters.toStringAsFixed(2)} L',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // Payment Section
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.payment, size: 20, color: AppTheme.primaryOrange),
                            SizedBox(width: 8),
                            Text(
                              'Payment Details',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: _paymentMethod,
                          decoration: const InputDecoration(
                            labelText: 'Payment Method',
                            prefixIcon: Icon(Icons.account_balance_wallet),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: AppConstants.paymentCash,
                              child: Text(AppConstants.paymentCash),
                            ),
                            DropdownMenuItem(
                              value: AppConstants.paymentMpesa,
                              child: Text(AppConstants.paymentMpesa),
                            ),
                            DropdownMenuItem(
                              value: AppConstants.paymentEquity,
                              child: Text(AppConstants.paymentEquity),
                            ),
                            DropdownMenuItem(
                              value: AppConstants.paymentCredit,
                              child: Text(AppConstants.paymentCredit),
                            ),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() {
                              _paymentMethod = value;
                              _paymentChange = null;
                              _paymentBalance = null;
                              _paymentError = null;
                            });
                          },
                        ),
                        if (_paymentMethod == AppConstants.paymentCredit) ...[
                          const SizedBox(height: 12),
                          TextField(
                            controller: _customerSearchController,
                            decoration: const InputDecoration(
                              labelText: 'Search customer by name',
                              prefixIcon: Icon(Icons.person_search),
                            ),
                            onChanged: _searchCustomers,
                          ),
                          if (_customerResults.isNotEmpty)
                            Container(
                              margin: const EdgeInsets.only(top: 8),
                              decoration: BoxDecoration(
                                border: Border.all(color: AppTheme.mediumGray),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: _customerResults.length > 5 ? 5 : _customerResults.length,
                                separatorBuilder: (context, index) => const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final customer = _customerResults[index];
                                  final name =
                                      '${customer.firstName} ${customer.lastName}'.trim();
                                  return ListTile(
                                    dense: true,
                                    title: Text(name.isEmpty ? 'Unnamed' : name),
                                    subtitle: customer.phone.isNotEmpty
                                        ? Text(customer.phone)
                                        : null,
                                    trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                                    onTap: () => _selectCustomer(customer),
                                  );
                                },
                              ),
                            ),
                          if (_selectedCustomer != null)
                            Container(
                              margin: const EdgeInsets.only(top: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryOrange.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppTheme.primaryOrange.withOpacity(0.3)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.person, size: 16, color: AppTheme.primaryOrange),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      '${_selectedCustomer!.firstName} ${_selectedCustomer!.lastName}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                        const SizedBox(height: 12),
                        TextField(
                          controller: _amountPaidController,
                          decoration: InputDecoration(
                            labelText: 'Amount Paid (KES)',
                            prefixIcon: const Icon(Icons.money),
                            suffixIcon: _paymentChange != null || _paymentBalance != null
                                ? Padding(
                                    padding: const EdgeInsets.all(12.0),
                                    child: _paymentChange != null
                                        ? Text(
                                            'Change: ${_paymentChange!.toStringAsFixed(0)}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: AppTheme.success,
                                              fontSize: 12,
                                            ),
                                          )
                                        : Text(
                                            'Bal: ${_paymentBalance!.toStringAsFixed(0)}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: AppTheme.error,
                                              fontSize: 12,
                                            ),
                                          ),
                                  )
                                : null,
                          ),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          onChanged: (_) => _applyPayment(
                            total,
                            isCredit: _paymentMethod == AppConstants.paymentCredit,
                          ),
                        ),
                        if (_paymentError != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline, size: 16, color: AppTheme.error),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    _paymentError!,
                                    style: const TextStyle(
                                      color: AppTheme.error,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Notes Section
                if (_cartItems.isNotEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: TextField(
                        controller: _suspendNotesController,
                        decoration: const InputDecoration(
                          labelText: 'Suspend Notes (optional)',
                          hintText: 'Add notes if suspending sale...',
                          prefixIcon: Icon(Icons.note_outlined),
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 2,
                      ),
                    ),
                  ),
              ],
            );

        final bottomSummary = Container(
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _cartItems.isEmpty || _isCompleting
                              ? null
                              : () => _completeSale(suspend: true),
                          icon: const Icon(Icons.pause_circle_outline),
                          label: const Text('Suspend'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: _cartItems.isEmpty || _isCompleting
                              ? null
                              : () => _completeSale(suspend: false),
                          icon: _isCompleting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.check_circle),
                          label: Text(_isCompleting ? 'Processing...' : 'Complete Sale'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (authService.currentCategory == AppConstants.categoryFillingStation)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _isCompleting
                              ? null
                              : () async {
                                  final saved = await showDialog<bool>(
                                    context: context,
                                    barrierDismissible: false,
                                    builder: (context) => const MeterReadingsDialog(
                                      readingType: AppConstants.readingTypeClosing,
                                    ),
                                  );
                                  if (saved == true) {
                                    authService.markMeterReadingsClosed();
                                    if (mounted) {
                                      ToastUtils.showSuccess('Closing readings saved.');
                                      setState(() {});
                                    }
                                  }
                                },
                          icon: const Icon(Icons.lock_clock, size: 18),
                          label: const Text('Finish Selling'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.error,
                            side: const BorderSide(color: AppTheme.error),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );

        if (isNarrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              cartContent,
              const SizedBox(height: 12),
              bottomSummary,
            ],
          );
        }

        return Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: cartContent,
              ),
            ),
            bottomSummary,
          ],
        );
  }
}

class _SaleCartItem {
  final String itemId;
  final String itemName;
  final double buyingPrice;
  final double sellingPrice;
  final double wholesalePrice;
  final double quantity;
  final String pricingType;
  final _FuelSaleMode saleMode;
  final TextEditingController quantityController;

  const _SaleCartItem({
    required this.itemId,
    required this.itemName,
    required this.buyingPrice,
    required this.sellingPrice,
    this.wholesalePrice = 0,
    required this.quantity,
    required this.pricingType,
    required this.saleMode,
    required this.quantityController,
  });

  _SaleCartItem copyWith({
    double? quantity,
    String? pricingType,
    _FuelSaleMode? saleMode,
  }) {
    return _SaleCartItem(
      itemId: itemId,
      itemName: itemName,
      buyingPrice: buyingPrice,
      sellingPrice: sellingPrice,
      wholesalePrice: wholesalePrice,
      quantity: quantity ?? this.quantity,
      pricingType: pricingType ?? this.pricingType,
      saleMode: saleMode ?? this.saleMode,
      quantityController: quantityController,
    );
  }
}

enum _FuelSaleMode { liters, price }
