import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/toast_utils.dart';
import '../../data/models/item.dart';
import '../../data/models/sale.dart';
import '../../data/models/meter_reading.dart';
import '../../data/models/customer.dart';

import '../../data/repositories/sales_repository.dart';
import '../../data/repositories/inventory_repository.dart';
import '../../data/repositories/customer_repository.dart';
import '../../data/repositories/meter_reading_repository.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/employee_repository.dart';
import '../../services/auth_service.dart';
import '../../widgets/receipt_template.dart';
import '../../services/receipt_print_service.dart';
import '../meter_readings/meter_readings_dialog.dart';
import '../../services/connectivity_service.dart';

class SalesPage extends StatefulWidget {
  final String? resumeSaleId;

  const SalesPage({super.key, this.resumeSaleId});

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
  String _pricingType = AppConstants.pricingRetail;
  String? _occupyingEmployeeName;
  MeterReading? _latestReading;

  Sale? _editingSale;

  @override
  void initState() {
    super.initState();
    if (widget.resumeSaleId != null) {
      _loadSuspendedSale(widget.resumeSaleId!);
    }

    _amountPaidController.addListener(_onAmountPaidChanged);

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
      _occupyingEmployeeName = null;
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
    final meterReadingRepository = Provider.of<MeterReadingRepository>(
      context,
      listen: false,
    );
    final locationId = authService.currentEmployee?.locationId;
    final employeeId = authService.currentEmployee?.id;
    if (locationId == null || employeeId == null) {
      return;
    }

    final category =
        authService.currentCategory ?? AppConstants.categoryFillingStation;

    // Check if ANY employee has an open session for this location/category
    final latestReading = await meterReadingRepository.getLatestMeterReading(
      locationId,
      category,
    );

    if (mounted) {
      setState(() {
        _latestReading = latestReading;
      });
    }

    if (latestReading != null &&
        latestReading.readingType == AppConstants.readingTypeOpening) {
      if (latestReading.employeeId != employeeId) {
        // Someone else is selling!
        final employeeRepo = Provider.of<EmployeeRepository>(
          context,
          listen: false,
        );
        final employee = await employeeRepo.getEmployee(
          latestReading.employeeId,
        );
        if (mounted) {
          setState(() {
            _occupyingEmployeeName = employee != null
                ? '${employee.firstName} ${employee.surname}'
                : 'Another employee';
          });
        }
        return;
      } else {
        // Current employee is already open
        authService.markMeterReadingsOpened();
        if (mounted) {
          setState(() {
            _occupyingEmployeeName = null;
          });
        }
        return;
      }
    }

    // No one is open, or someone closed.
    if (latestReading?.readingType == AppConstants.readingTypeClosing) {
      authService.markMeterReadingsClosed();
    }

    if (authService.hasOpenedMeterReadings) {
      if (mounted) {
        setState(() {
          _occupyingEmployeeName = null;
        });
      }
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
        setState(() {
          _occupyingEmployeeName = null;
        });
      }
    }
  }

  @override
  void dispose() {
    _amountPaidController.removeListener(_onAmountPaidChanged);
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

  void _onAmountPaidChanged() {
    setState(() {}); // Triggers rebuild for real-time change due
  }

  Future<void> _loadSuspendedSale(String saleId) async {
    setState(() => _isLoading = true);
    final salesRepository = Provider.of<SalesRepository>(
      context,
      listen: false,
    );
    try {
      final sale = await salesRepository.getSale(saleId);
      if (sale == null || !sale.isSuspended) {
        setState(() => _isLoading = false);
        return;
      }

      final saleItems = await salesRepository.getSaleItems(saleId);

      setState(() {
        _editingSale = sale;
        if (sale.paymentMethod == 'Suspended' || sale.paymentMethod.isEmpty) {
          _paymentMethod = _paymentMethod.isNotEmpty
              ? _paymentMethod
              : AppConstants.paymentCash;
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
                availableStock:
                    0, // Not available for suspended sales immediately
              ),
            ),
          );
        _isLoading = false;
      });
    } catch (e) {
      ToastUtils.showError('Failed to load suspended sale');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _searchItems(String query) async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final inventoryRepository = Provider.of<InventoryRepository>(
      context,
      listen: false,
    );
    final locationId = _getCurrentLocationId(authService);
    if (locationId == null) return;

    if (query.trim().isEmpty) {
      setState(() => _searchResults = []);
      return;
    }

    final category =
        authService.currentCategory ?? AppConstants.categoryFillingStation;
    final results = await inventoryRepository.searchItems(
      locationId,
      query.trim(),
      category: category,
    );
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
          quantity: isFillingStation ? 0 : 1,
          pricingType: _pricingType,
          saleMode: isFillingStation
              ? _FuelSaleMode.price
              : _FuelSaleMode.liters,
          quantityController: TextEditingController(
            text: isFillingStation ? '' : _formatNumber(1),
          ),
          availableStock: item.quantity,
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

  void _updateCartQuantity(
    _SaleCartItem item,
    double quantity, {
    bool syncText = false,
  }) {
    if (quantity < 0) {
      setState(() => _cartItems.remove(item));
      return;
    }
    setState(() {
      if (syncText) {
        item.quantityController.text = _formatNumber(quantity);
      }
      final index = _cartItems.indexOf(item);
      if (index != -1) {
        _cartItems[index] = item.copyWith(quantity: quantity);
      }
    });
  }

  void _removeCartItem(_SaleCartItem item) {
    setState(() {
      item.quantityController.dispose();
      _cartItems.remove(item);
    });
  }

  void _updateCartInput(_SaleCartItem item, String value) {
    final parsed = _parseNumber(value);
    if (parsed == null) {
      _updateCartQuantity(item, 0);
      return;
    }
    _updateCartQuantity(item, parsed);
  }

  void _setPricingType(String pricingType) {
    setState(() {
      final isSwitchingToWholesale =
          pricingType == AppConstants.pricingWholesale;
      final authService = Provider.of<AuthService>(context, listen: false);
      final isFillingStation =
          authService.currentCategory == AppConstants.categoryFillingStation;

      for (var i = 0; i < _cartItems.length; i++) {
        var item = _cartItems[i];

        // Specific logic for Filling Station:
        // If switching Retail -> Wholesale and item is in 'Price' (Amount) mode:
        // 1. Calculate liters based on current Retail Price.
        // 2. Switch mode to Liters.
        // 3. Update quantity to those liters.
        if (isFillingStation &&
            isSwitchingToWholesale &&
            item.saleMode == _FuelSaleMode.price) {
          final retailPrice = item.sellingPrice;
          if (retailPrice > 0) {
            // Calculate effective liters from the Amount (quantity in price mode = amount)
            final effectiveLiters = item.quantity / retailPrice;

            item = item.copyWith(
              saleMode: _FuelSaleMode.liters,
              quantity: effectiveLiters,
              pricingType: pricingType, // Apply new pricing type immediately
              availableStock: item.availableStock,
            );
            item.quantityController.text = _formatNumber(effectiveLiters);
          } else {
            // Fallback if price is 0, just switch type
            item = item.copyWith(pricingType: pricingType);
          }
        } else {
          // Standard update for other cases
          item = item.copyWith(pricingType: pricingType);
        }
        _cartItems[i] = item;
      }
      _pricingType = pricingType;
    });
  }

  double _calculateItemSubtotal(_SaleCartItem item) {
    final price = _getUnitPrice(item);
    if (item.saleMode == _FuelSaleMode.price) {
      return item.quantity; // quantity IS the KES amount
    }
    return price * item.quantity;
  }

  double _getUnitPrice(_SaleCartItem item) {
    final authService = Provider.of<AuthService>(context, listen: false);
    final isFillingStation =
        authService.currentCategory == AppConstants.categoryFillingStation;
    // Price mode in filling station → always retail
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
      if (price <= 0) return 0;
      return item.quantity / price;
    }
    return item.quantity;
  }

  double _calculateTotal() {
    return _cartItems.fold(
      0,
      (sum, item) => sum + _calculateItemSubtotal(item),
    );
  }

  String _formatNumber(double value) {
    final text = value.toStringAsFixed(3);
    return text.replaceFirst(RegExp(r'\.?0+$'), '');
  }

  double? _parseNumber(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    return double.tryParse(trimmed.replaceAll(',', '.')) ?? 0;
  }

  double _calculateProfit() {
    return _cartItems.fold(0, (sum, item) {
      final price = _getUnitPrice(item);
      final qty = _getEffectiveQuantity(item);
      return sum + ((price - item.buyingPrice) * qty);
    });
  }

  double get _amountPaid => _parseNumber(_amountPaidController.text) ?? 0;

  bool get _canCompleteSale {
    if (_cartItems.isEmpty || _isCompleting) return false;
    final total = _calculateTotal();
    if (total <= 0) return false;
    if (_paymentMethod == AppConstants.paymentCredit) {
      return _selectedCustomer != null && _amountPaid < total;
    }
    return _amountPaid >= total;
  }

  Future<void> _completeSale({required bool suspend}) async {
    final connectivity = Provider.of<ConnectivityService>(
      context,
      listen: false,
    );
    if (!await connectivity.checkConnection()) {
      ToastUtils.showError(
        'No internet connection. This action is online-only.',
      );
      return;
    }

    if (!suspend) {
      final salesRepository = Provider.of<SalesRepository>(
        context,
        listen: false,
      );
      final authService = Provider.of<AuthService>(context, listen: false);
      final locationId = _getCurrentLocationId(authService);
      final category =
          authService.currentCategory ?? AppConstants.categoryFillingStation;
      if (locationId != null && _editingSale == null) {
        final suspendedSales = await salesRepository.getSuspendedSales(
          locationId,
          category,
        );
        if (suspendedSales.isNotEmpty) {
          ToastUtils.showError(
            'You have suspended sales. Please finish them before completing a new sale.',
          );
          return;
        }
      }
    }
    if (_cartItems.isEmpty) {
      ToastUtils.showError('Add at least one item.');
      return;
    }

    final authService = Provider.of<AuthService>(context, listen: false);
    if (!authService.hasPermission('canProcessSales') &&
        authService.isEmployee) {
      ToastUtils.showError('You do not have permission to process sales.');
      return;
    }

    if (!authService.isEmployee) {
      ToastUtils.showError('Admins cannot process sales.');
      return;
    }

    if (authService.currentCategory == AppConstants.categoryFillingStation &&
        authService.hasClosedMeterReadings) {
      ToastUtils.showError(
        'Selling is closed for this session. Log out to continue.',
      );
      return;
    }

    final locationId = _getCurrentLocationId(authService);
    if (locationId == null) return;

    final total = _calculateTotal();
    final amountPaid = _amountPaid;

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
    final salesRepository = Provider.of<SalesRepository>(
      context,
      listen: false,
    );

    try {
      final shouldPop = widget.resumeSaleId != null;
      final now = DateTime.now();
      final saleIdString =
          _editingSale?.saleId ?? _buildSaleId(locationId, now);
      final saleDbId = _editingSale?.id ?? _uuid.v4();

      final sale = Sale(
        id: saleDbId,
        saleId: saleIdString,
        locationId: locationId,
        category:
            authService.currentCategory ?? AppConstants.categoryFillingStation,
        employeeId: authService.currentEmployee!.id,
        paymentMethod: suspend ? 'Suspended' : _paymentMethod,
        totalAmount: total,
        amountPaid: suspend ? 0 : amountPaid,
        changeGiven: suspend
            ? 0
            : (_paymentMethod == AppConstants.paymentCredit
                  ? 0
                  : (amountPaid - total)),
        profit: _calculateProfit(),
        isSuspended: suspend,
        suspensionNotes: suspend ? _suspendNotesController.text.trim() : null,
        timestamp: now,
      );

      final List<SaleItem> saleItems = [];
      for (final item in _cartItems) {
        final qty = _getEffectiveQuantity(item);
        final unitPrice = _getUnitPrice(item);

        // Calculate wholesale discount: retail price - wholesale price per unit
        double discount = 0;
        if (item.pricingType == AppConstants.pricingWholesale &&
            item.sellingPrice > item.wholesalePrice) {
          discount = (item.sellingPrice - item.wholesalePrice) * qty;
        }

        saleItems.add(
          SaleItem(
            id: _uuid.v4(),
            saleId: saleDbId,
            itemId: item.itemId,
            itemName: item.itemName,
            quantity: qty,
            buyingPrice: item.buyingPrice,
            sellingPrice: unitPrice,
            pricingType: item.pricingType,
            subtotal: _calculateItemSubtotal(item),
            discount: discount,
          ),
        );
      }

      Credit? credit;
      if (!suspend &&
          _paymentMethod == AppConstants.paymentCredit &&
          _selectedCustomer != null) {
        final balance = total - amountPaid;
        credit = Credit(
          id: _uuid.v4(),
          customerId: _selectedCustomer!.id,
          saleId: saleDbId,
          locationId: locationId,
          category:
              authService.currentCategory ??
              AppConstants.categoryFillingStation,
          totalOwed: total,
          amountPaid: amountPaid,
          balance: balance,
          createdAt: now,
        );
      }

      await salesRepository.processSale(
        sale: sale,
        items: saleItems,
        credit: credit,
      );

      if (!suspend) {
        ToastUtils.showSuccess('Sale completed');
        await _showReceiptPreview(saleIdString, now, total, amountPaid);
      } else {
        ToastUtils.showSuccess('Sale suspended');
      }

      _resetSale();

      if (shouldPop && mounted && Navigator.canPop(context)) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      ToastUtils.showError('Unable to save sale: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() => _isCompleting = false);
      }
    }
  }

  String _buildSaleId(String locationId, DateTime now) {
    final timestamp = DateFormat(AppConstants.dateFormatSaleId).format(now);
    final shortLoc = locationId.length >= 4
        ? locationId.substring(0, 4)
        : locationId;
    return '${shortLoc.toUpperCase()}-$timestamp-${_uuid.v4().substring(0, 4)}';
  }

  Future<void> _showReceiptPreview(
    String receiptId,
    DateTime timestamp,
    double totalAmount,
    double amountPaid,
  ) async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final locationRepository = Provider.of<AuthRepository>(
      context,
      listen: false,
    );
    final locationId = _getCurrentLocationId(authService);
    if (locationId == null) return;
    final location = await locationRepository.getLocation(locationId);
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
      _pricingType = AppConstants.pricingRetail;
    });
  }

  Future<void> _searchCustomers(String query) async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final customerRepository = Provider.of<CustomerRepository>(
      context,
      listen: false,
    );
    final locationId = _getCurrentLocationId(authService);
    if (locationId == null) return;
    if (query.trim().isEmpty) {
      setState(() {
        _selectedCustomer = null;
        _customerResults = [];
      });
      return;
    }

    final results = await customerRepository.searchCustomers(
      locationId,
      query.trim(),
    );
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

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth > 900;

    if (authService.isAdmin || authService.isSuperAdmin) {
      return const Scaffold(
        body: Center(child: Text('Admins cannot process sales.')),
      );
    }

    if (!authService.hasPermission('canProcessSales')) {
      return const Scaffold(
        body: Center(
          child: Text('You do not have permission to process sales.'),
        ),
      );
    }

    if (authService.currentCategory == AppConstants.categoryFillingStation &&
        _latestReading != null &&
        _latestReading!.readingType == AppConstants.readingTypeOpening &&
        _latestReading!.employeeId != authService.currentEmployee?.id) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                size: 64,
                color: AppTheme.primaryOrange,
              ),
              const SizedBox(height: 16),
              Text(
                'Another staff member is already selling',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${_occupyingEmployeeName ?? "Another employee"} has an active session.',
                style: const TextStyle(color: AppTheme.darkGray),
              ),
              const SizedBox(height: 24),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 40),
                child: Text(
                  'Please tell them to finish selling and close their meter readings before you can start a new session.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => _maybePromptOpeningReadings(),
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh Status'),
              ),
            ],
          ),
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
              const Icon(
                Icons.local_gas_station,
                size: 64,
                color: AppTheme.primaryOrange,
              ),
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
      return const Scaffold(
        body: Center(
          child: Text(
            'Selling is closed for this session. Log out to continue.',
          ),
        ),
      );
    }

    return Scaffold(
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : isWide
          ? _buildWideLayout()
          : _buildNarrowLayout(),
    );
  }

  // ---- Wide Layout (Tablet) ----
  Widget _buildWideLayout() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 3, child: _buildItemsPanel()),
          const SizedBox(width: 16),
          Expanded(flex: 2, child: _buildCartScrollable()),
        ],
      ),
    );
  }

  // ---- Narrow Layout (Phone) — Single Scrollable Column ----
  Widget _buildNarrowLayout() {
    return _buildCartScrollable(showSearchInline: true);
  }

  // ---- Items Panel (for wide layout left side) ----
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
            _buildSearchField(),
            const SizedBox(height: 12),
            if (_searchController.text.isNotEmpty)
              Expanded(
                child: _searchResults.isEmpty
                    ? const Center(child: Text('No items found'))
                    : _buildSearchResultsList(),
              )
            else
              const Expanded(
                child: Center(
                  child: Text(
                    'Search for items to add to cart',
                    style: TextStyle(color: AppTheme.darkGray),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      decoration: InputDecoration(
        labelText: 'Search items...',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _searchController.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear, size: 18),
                onPressed: () {
                  _searchController.clear();
                  setState(() => _searchResults = []);
                },
              )
            : null,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
      ),
      onChanged: _searchItems,
    );
  }

  Widget _buildSearchResultsList() {
    return ListView.builder(
      shrinkWrap: true,
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final item = _searchResults[index];
        return ListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          title: Text(item.name, style: const TextStyle(fontSize: 14)),
          subtitle: Row(
            children: [
              Text(
                'Price: KES ${item.sellingPrice.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(width: 8),
              Container(width: 1, height: 10, color: Colors.grey.shade300),
              const SizedBox(width: 8),
              Text(
                'Buy: KES ${item.buyingPrice.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
              const SizedBox(width: 8),
              Container(width: 1, height: 10, color: Colors.grey.shade300),
              const SizedBox(width: 8),
              Text(
                'Stock: ${item.quantity.toStringAsFixed(0)}',
                style: TextStyle(
                  fontSize: 11,
                  color: item.quantity > 0
                      ? Colors.green.shade700
                      : AppTheme.error,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          trailing: const Icon(
            Icons.add_circle,
            color: AppTheme.primaryOrange,
            size: 22,
          ),
          onTap: () => _selectSearchItem(item),
        );
      },
    );
  }

  // ============================================================
  // MAIN CART SCROLLABLE — works for both narrow and wide
  // ============================================================
  Widget _buildCartScrollable({bool showSearchInline = false}) {
    final authService = Provider.of<AuthService>(context, listen: false);
    final isFillingStation =
        authService.currentCategory == AppConstants.categoryFillingStation;
    final total = _calculateTotal();
    final amountPaid = _amountPaid;
    final isCredit = _paymentMethod == AppConstants.paymentCredit;

    return CustomScrollView(
      slivers: [
        // -- Search (only in narrow layout) --
        if (showSearchInline) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: _buildSearchField(),
            ),
          ),
          if (_searchResults.isNotEmpty)
            SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                constraints: const BoxConstraints(maxHeight: 200),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: AppTheme.mediumGray),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: _buildSearchResultsList(),
              ),
            ),
        ],

        // -- Pricing Type Toggle --
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: AppConstants.pricingRetail,
                        label: Text('Retail', style: TextStyle(fontSize: 13)),
                        icon: Icon(Icons.storefront, size: 16),
                      ),
                      ButtonSegment(
                        value: AppConstants.pricingWholesale,
                        label: Text(
                          'Wholesale',
                          style: TextStyle(fontSize: 13),
                        ),
                        icon: Icon(Icons.warehouse, size: 16),
                      ),
                    ],
                    selected: {_pricingType},
                    onSelectionChanged: (s) => _setPricingType(s.first),
                    style: ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // -- Cart Items --
        if (_cartItems.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.shopping_cart_outlined,
                      size: 48,
                      color: AppTheme.mediumGray,
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Cart is empty',
                      style: TextStyle(color: AppTheme.darkGray),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate((context, index) {
                final item = _cartItems[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: _buildCartItemCard(item, isFillingStation),
                );
              }, childCount: _cartItems.length),
            ),
          ),

        // -- Totals + Payment Section --
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Total Bar
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryBlack,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'TOTAL',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        'KES ${total.toStringAsFixed(2)}',
                        style: const TextStyle(
                          color: AppTheme.primaryOrange,
                          fontWeight: FontWeight.bold,
                          fontSize: 20,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),

                // Payment Method
                DropdownButtonFormField<String>(
                  value: _paymentMethod,
                  items:
                      [
                            AppConstants.paymentCash,
                            AppConstants.paymentMpesa,
                            AppConstants.paymentEquity,
                            AppConstants.paymentCredit,
                          ]
                          .map(
                            (m) => DropdownMenuItem(value: m, child: Text(m)),
                          )
                          .toList(),
                  onChanged: (val) => setState(() => _paymentMethod = val!),
                  decoration: const InputDecoration(
                    labelText: 'Payment Method',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                  ),
                ),

                // Credit Customer Search
                if (isCredit) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: _customerSearchController,
                    decoration: const InputDecoration(
                      labelText: 'Search Customer...',
                      prefixIcon: Icon(Icons.person, size: 20),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                    ),
                    onChanged: _searchCustomers,
                  ),
                  if (_customerResults.isNotEmpty)
                    Container(
                      constraints: const BoxConstraints(maxHeight: 120),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _customerResults.length,
                        itemBuilder: (context, index) {
                          final c = _customerResults[index];
                          return ListTile(
                            dense: true,
                            title: Text('${c.firstName} ${c.lastName}'),
                            subtitle: Text(c.phone),
                            onTap: () => _selectCustomer(c),
                          );
                        },
                      ),
                    ),
                  if (_selectedCustomer != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Customer: ${_selectedCustomer!.firstName} ${_selectedCustomer!.lastName}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryOrange,
                          fontSize: 13,
                        ),
                      ),
                    ),
                ],

                const SizedBox(height: 10),

                // Amount Paid
                TextField(
                  controller: _amountPaidController,
                  decoration: InputDecoration(
                    labelText: 'Amount Paid (KES)',
                    prefixIcon: const Icon(Icons.payments, size: 20),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                  ],
                ),
                const SizedBox(height: 8),

                // Real-Time Change Due / Insufficient
                if (_cartItems.isNotEmpty &&
                    _amountPaidController.text.isNotEmpty)
                  _buildChangeDueWidget(total, amountPaid, isCredit),

                const SizedBox(height: 12),

                // Action Buttons
                _buildActionButtons(isFillingStation, authService),

                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ---- Change Due Widget ----
  Widget _buildChangeDueWidget(double total, double amountPaid, bool isCredit) {
    if (isCredit) {
      final balance = total - amountPaid;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.orange.shade200),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Outstanding Balance',
              style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
            ),
            Text(
              'KES ${balance.toStringAsFixed(2)}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: balance > 0
                    ? AppTheme.primaryOrange
                    : Colors.green.shade700,
              ),
            ),
          ],
        ),
      );
    }

    final change = amountPaid - total;
    final isEnough = amountPaid >= total;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isEnough ? Colors.green.shade50 : Colors.red.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isEnough ? Colors.green.shade300 : Colors.red.shade300,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            isEnough ? 'Change Due' : 'Insufficient',
            style: TextStyle(
              fontWeight: FontWeight.w500,
              fontSize: 13,
              color: isEnough ? Colors.green.shade800 : Colors.red.shade800,
            ),
          ),
          Text(
            'KES ${change.abs().toStringAsFixed(2)}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: isEnough ? Colors.green.shade700 : Colors.red.shade700,
            ),
          ),
        ],
      ),
    );
  }

  // ---- Action Buttons ----
  Widget _buildActionButtons(bool isFillingStation, AuthService authService) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _cartItems.isEmpty
                    ? null
                    : () => _completeSale(suspend: true),
                icon: const Icon(Icons.pause_circle_outline, size: 18),
                label: const Text('Suspend'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: ElevatedButton.icon(
                onPressed: _canCompleteSale
                    ? () => _completeSale(suspend: false)
                    : null,
                icon: _isCompleting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      )
                    : const Icon(Icons.check_circle, size: 18),
                label: Text(
                  _isCompleting ? 'Processing...' : 'Complete Sale',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  backgroundColor: _canCompleteSale
                      ? Colors.green.shade600
                      : null,
                ),
              ),
            ),
          ],
        ),
        if (isFillingStation) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () async {
              final saved = await showDialog<bool>(
                context: context,
                builder: (context) => const MeterReadingsDialog(
                  readingType: AppConstants.readingTypeClosing,
                ),
              );
              if (saved == true) {
                authService.markMeterReadingsClosed();
                setState(() {});
              }
            },
            icon: const Icon(Icons.lock_clock, size: 18),
            label: const Text('Finish Selling'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.error,
              padding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        ],
      ],
    );
  }

  // ============================================================
  // CART ITEM CARD
  // ============================================================
  Widget _buildCartItemCard(_SaleCartItem item, bool isFillingStation) {
    final unitPrice = _getUnitPrice(item);
    final subtotal = _calculateItemSubtotal(item);

    return Card(
      elevation: 1,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row 1: Name + Delete
            Row(
              children: [
                Expanded(
                  child: Text(
                    item.itemName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  'KES ${subtotal.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: AppTheme.primaryOrange,
                  ),
                ),
                const SizedBox(width: 4),
                InkWell(
                  onTap: () => _removeCartItem(item),
                  borderRadius: BorderRadius.circular(12),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.close, size: 16, color: AppTheme.error),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(2),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Text(
                    'Stock: ${item.availableStock.toStringAsFixed(0)}',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'BP: ${item.buyingPrice.toStringAsFixed(0)}',
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // Row 2: Price info + Controls
            if (isFillingStation)
              _buildFillingStationControls(item, unitPrice)
            else
              _buildStandardControls(item, unitPrice),
          ],
        ),
      ),
    );
  }

  // ---- Filling Station Controls ----
  Widget _buildFillingStationControls(_SaleCartItem item, double unitPrice) {
    final effectiveLiters = _getEffectiveQuantity(item);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Price per liter info
        Text(
          'KES ${unitPrice.toStringAsFixed(2)}/liter'
          '${item.saleMode == _FuelSaleMode.price ? ' (retail)' : ''}',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 6),

        // Liters/Price toggle + Input in one row
        Row(
          children: [
            // Liters/Price Toggle
            SizedBox(
              height: 34,
              child: SegmentedButton<_FuelSaleMode>(
                segments: const [
                  ButtonSegment(
                    value: _FuelSaleMode.liters,
                    label: Text('Liters', style: TextStyle(fontSize: 11)),
                  ),
                  ButtonSegment(
                    value: _FuelSaleMode.price,
                    label: Text('Price', style: TextStyle(fontSize: 11)),
                  ),
                ],
                selected: {item.saleMode},
                onSelectionChanged: (selection) {
                  setState(() {
                    final index = _cartItems.indexOf(item);
                    item.quantityController.clear();
                    _cartItems[index] = item.copyWith(
                      saleMode: selection.first,
                      quantity: 0,
                    );
                  });
                },
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: WidgetStateProperty.all<EdgeInsetsGeometry>(
                    const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),

            // Quantity Input
            Expanded(
              child: SizedBox(
                height: 38,
                child: TextField(
                  controller: item.quantityController,
                  decoration: InputDecoration(
                    labelText: item.saleMode == _FuelSaleMode.liters
                        ? 'Liters'
                        : 'KES Amount',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  style: const TextStyle(fontSize: 14),
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                  ],
                  onChanged: (val) => _updateCartInput(item, val),
                ),
              ),
            ),
          ],
        ),

        // Show liter equivalent when in Price mode
        if (item.saleMode == _FuelSaleMode.price && item.quantity > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '≈ ${effectiveLiters.toStringAsFixed(3)} liters',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.blue.shade700,
              ),
            ),
          ),

        // Show KES equivalent when in Liters mode
        if (item.saleMode == _FuelSaleMode.liters && item.quantity > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '= KES ${(unitPrice * item.quantity).toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.blue.shade700,
              ),
            ),
          ),
      ],
    );
  }

  // ---- Standard (Car Sale) Controls ----
  Widget _buildStandardControls(_SaleCartItem item, double unitPrice) {
    return Row(
      children: [
        Text(
          'KES ${unitPrice.toStringAsFixed(2)} ×',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        const SizedBox(width: 6),
        // Quantity controls
        InkWell(
          onTap: () {
            final newQty = item.quantity - 1;
            if (newQty <= 0) {
              _removeCartItem(item);
            } else {
              _updateCartQuantity(item, newQty, syncText: true);
            }
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppTheme.darkGray),
            ),
            child: const Icon(Icons.remove, size: 14),
          ),
        ),
        const SizedBox(width: 4),
        SizedBox(
          width: 50,
          height: 32,
          child: TextField(
            controller: item.quantityController,
            textAlign: TextAlign.center,
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              border: OutlineInputBorder(),
            ),
            style: const TextStyle(fontSize: 13),
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
            ],
            onChanged: (val) => _updateCartInput(item, val),
          ),
        ),
        const SizedBox(width: 4),
        InkWell(
          onTap: () {
            _updateCartQuantity(item, item.quantity + 1, syncText: true);
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppTheme.darkGray),
            ),
            child: const Icon(Icons.add, size: 14),
          ),
        ),
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
  final double availableStock;

  _SaleCartItem({
    required this.itemId,
    required this.itemName,
    required this.buyingPrice,
    required this.sellingPrice,
    required this.wholesalePrice,
    required this.quantity,
    required this.pricingType,
    required this.saleMode,
    required this.quantityController,
    this.availableStock = 0,
  });

  _SaleCartItem copyWith({
    String? itemId,
    String? itemName,
    double? buyingPrice,
    double? sellingPrice,
    double? wholesalePrice,
    double? quantity,
    String? pricingType,
    _FuelSaleMode? saleMode,
    TextEditingController? quantityController,
    double? availableStock,
  }) {
    return _SaleCartItem(
      itemId: itemId ?? this.itemId,
      itemName: itemName ?? this.itemName,
      buyingPrice: buyingPrice ?? this.buyingPrice,
      sellingPrice: sellingPrice ?? this.sellingPrice,
      wholesalePrice: wholesalePrice ?? this.wholesalePrice,
      quantity: quantity ?? this.quantity,
      pricingType: pricingType ?? this.pricingType,
      saleMode: saleMode ?? this.saleMode,
      quantityController: quantityController ?? this.quantityController,
      availableStock: availableStock ?? this.availableStock,
    );
  }
}

enum _FuelSaleMode { liters, price }
