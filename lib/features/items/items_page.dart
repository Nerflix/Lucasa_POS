import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:drift/drift.dart' as drift;
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/toast_utils.dart';
import '../../data/database/app_database.dart';
import '../../services/auth_service.dart';
import 'item_detail_page.dart';

class ItemsPage extends StatefulWidget {
  const ItemsPage({super.key});

  @override
  State<ItemsPage> createState() => _ItemsPageState();
}

class _ItemsPageState extends State<ItemsPage> {
  final _searchController = TextEditingController();
  List<Item> _items = [];
  List<Item> _filteredItems = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadItems() async {
    setState(() => _isLoading = true);
    
    final db = Provider.of<AppDatabase>(context, listen: false);
    final authService = Provider.of<AuthService>(context, listen: false);
    
    // Get items for current employee's allowed locations
    final allowedLocationIds = authService.allowedLocationIds;
    final category = authService.currentCategory ?? AppConstants.categoryFillingStation;
    List<Item> items = [];
    
    if (allowedLocationIds.isNotEmpty) {
      if (authService.hasMultipleLocations) {
        // Admin with multiple locations - get items from all locations
        items = await db.getItemsByLocationsAndCategory(allowedLocationIds, category);
      } else {
        // Employee or admin with single location
        items = await db.getItemsByLocationAndCategory(allowedLocationIds.first, category);
      }
    }
    
    setState(() {
      _items = items;
      _filteredItems = items;
      _isLoading = false;
    });
  }

  void _filterItems(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredItems = _items;
      } else {
        _filteredItems = _items.where((item) {
          return item.name.toLowerCase().contains(query.toLowerCase()) ||
                 (item.barcode?.contains(query) ?? false);
        }).toList();
      }
    });
  }

  void _showAddItemDialog() {
    showDialog(
      context: context,
      builder: (context) => _AddItemDialog(onItemAdded: _loadItems),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth <= 600;
    final authService = Provider.of<AuthService>(context);
    final canManageInventory = authService.hasPermission('canManageInventory');

    return Scaffold(
      body: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Items',
                      style: TextStyle(
                        fontSize: isMobile ? 24 : 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle, color: AppTheme.primaryOrange, size: 32),
                      onPressed: canManageInventory ? _showAddItemDialog : null,
                      tooltip: 'Add Item',
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (!canManageInventory)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text(
                      'You do not have permission to manage inventory.',
                      style: TextStyle(color: AppTheme.darkGray),
                    ),
                  ),
                TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    hintText: 'Search by name or barcode',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: _filterItems,
                ),
              ],
            ),
          ),
          
          // Items list
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadItems,
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredItems.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                _items.isEmpty ? Icons.inventory_2_outlined : Icons.search_off,
                                size: 64,
                                color: AppTheme.darkGray,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _items.isEmpty ? 'No items yet' : 'No items found',
                                style: const TextStyle(
                                  fontSize: 16,
                                  color: AppTheme.darkGray,
                                ),
                              ),
                              if (_items.isEmpty) ...[
                                const SizedBox(height: 16),
                                ElevatedButton.icon(
                                  onPressed: canManageInventory ? _showAddItemDialog : null,
                                  icon: const Icon(Icons.add),
                                  label: const Text('Add First Item'),
                                ),
                              ],
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _filteredItems.length,
                          itemBuilder: (context, index) {
                            final item = _filteredItems[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () async {
                                  final changed = await Navigator.of(context).push<bool>(
                                    MaterialPageRoute(
                                      builder: (context) => ItemDetailPage(
                                        item: item,
                                        canEdit: canManageInventory,
                                      ),
                                    ),
                                  );
                                  if (changed == true) {
                                    _loadItems();
                                  }
                                },
                                child: Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            width: 48,
                                            height: 48,
                                            decoration: BoxDecoration(
                                              color: AppTheme.primaryOrange.withOpacity(0.1),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: const Icon(
                                              Icons.inventory_2,
                                              color: AppTheme.primaryOrange,
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
                                                    fontSize: 16,
                                                  ),
                                                ),
                                                if (item.barcode != null)
                                                  Text(
                                                    'Barcode: ${item.barcode}',
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                      color: AppTheme.darkGray,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 6,
                                            ),
                                            decoration: BoxDecoration(
                                              color: item.quantity <= 0
                                                  ? AppTheme.error.withOpacity(0.1)
                                                  : item.quantity <= item.reorderLevel
                                                      ? AppTheme.primaryOrange.withOpacity(0.1)
                                                      : AppTheme.success.withOpacity(0.1),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Column(
                                              children: [
                                                Text(
                                                  'Qty: ${item.quantity}',
                                                  style: TextStyle(
                                                    color: item.quantity <= 0
                                                        ? AppTheme.error
                                                        : item.quantity <= item.reorderLevel
                                                            ? AppTheme.primaryOrange
                                                            : AppTheme.success,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                                if (item.quantity <= item.reorderLevel && item.quantity > 0)
                                                  const Text(
                                                    'LOW',
                                                    style: TextStyle(
                                                      color: AppTheme.primaryOrange,
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 9,
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
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                                        children: [
                                          _buildPriceChip('Buying', item.buyingPrice),
                                          _buildPriceChip('Wholesale', item.wholesalePrice),
                                          _buildPriceChip('Retail', item.sellingPrice),
                                        ],
                                      ),
                                    ],
                                  ),
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

  Widget _buildPriceChip(String label, double price) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: AppTheme.darkGray,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'KES ${price.toStringAsFixed(2)}',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}

class _AddItemDialog extends StatefulWidget {
  final VoidCallback onItemAdded;
  
  const _AddItemDialog({required this.onItemAdded});

  @override
  State<_AddItemDialog> createState() => _AddItemDialogState();
}

class _AddItemDialogState extends State<_AddItemDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _barcodeController = TextEditingController();
  final _buyingPriceController = TextEditingController();
  final _wholesalePriceController = TextEditingController();
  final _sellingPriceController = TextEditingController();
  final _quantityController = TextEditingController(text: '0');
  final _reorderLevelController = TextEditingController();
  bool _isSaving = false;
  List<Location> _locations = [];
  String? _selectedLocationId;

  @override
  void initState() {
    super.initState();
    _loadLocations();
  }

  Future<void> _loadLocations() async {
    final db = Provider.of<AppDatabase>(context, listen: false);
    final authService = Provider.of<AuthService>(context, listen: false);
    final allowed = authService.allowedLocationIds;

    if (allowed.isEmpty) return;

    final allLocations = await db.getAllLocations();
    final filtered = allLocations.where((loc) => allowed.contains(loc.id)).toList();

    setState(() {
      _locations = filtered;
      _selectedLocationId = filtered.isNotEmpty ? filtered.first.id : null;
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _barcodeController.dispose();
    _buyingPriceController.dispose();
    _wholesalePriceController.dispose();
    _sellingPriceController.dispose();
    _quantityController.dispose();
    _reorderLevelController.dispose();
    super.dispose();
  }

  Future<void> _saveItem() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    final db = Provider.of<AppDatabase>(context, listen: false);
    final authService = Provider.of<AuthService>(context, listen: false);
    final category = authService.currentCategory ?? AppConstants.categoryFillingStation;
    if (!authService.hasPermission('canManageInventory')) {
      ToastUtils.showError('You do not have permission to add items.');
      setState(() => _isSaving = false);
      return;
    }

    if (_selectedLocationId == null) {
      ToastUtils.showError('Please select a location.');
      setState(() => _isSaving = false);
      return;
    }
    
    try {
      final itemId = 'item_${DateTime.now().millisecondsSinceEpoch}';
      final item = ItemsCompanion.insert(
        id: itemId,
        locationId: _selectedLocationId!,
        category: drift.Value(category),
        name: _nameController.text.trim(),
        barcode: drift.Value(_barcodeController.text.trim().isEmpty ? null : _barcodeController.text.trim()),
        buyingPrice: double.parse(_buyingPriceController.text),
        wholesalePrice: double.parse(_wholesalePriceController.text),
        sellingPrice: double.parse(_sellingPriceController.text),
        quantity: drift.Value(double.parse(_quantityController.text)),
        reorderLevel: drift.Value(double.parse(_reorderLevelController.text)),
        createdBy: authService.currentEmployee?.id ?? 'unknown',
      );
      
      await db.insertItem(item);
      
      if (mounted) {
        ToastUtils.showSuccess('Item added successfully');
        widget.onItemAdded();
        Navigator.of(context).pop();
      }
    } catch (e) {
      print('Save item error: $e'); // Log for debugging
      if (mounted) {
        ToastUtils.showError('Unable to save item. Please try again.');
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final dialogWidth = screenWidth > 600 ? 500.0 : screenWidth * 0.9;

    return Dialog(
      child: Container(
        width: dialogWidth,
        constraints: const BoxConstraints(maxHeight: 700),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: AppTheme.primaryOrange,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(4),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.add_shopping_cart, color: AppTheme.primaryWhite),
                  const SizedBox(width: 12),
                  const Text(
                    'Add Item',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryWhite,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: AppTheme.primaryWhite),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      if (_locations.length > 1) ...[
                        DropdownButtonFormField<String>(
                          value: _selectedLocationId,
                          decoration: const InputDecoration(
                            labelText: 'Location',
                            prefixIcon: Icon(Icons.location_on),
                          ),
                          items: _locations
                              .map((loc) => DropdownMenuItem(
                                    value: loc.id,
                                    child: Text(loc.name),
                                  ))
                              .toList(),
                          onChanged: (value) => setState(() => _selectedLocationId = value),
                          validator: (value) => value == null ? 'Required' : null,
                        ),
                        const SizedBox(height: 16),
                      ],
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Item Name',
                          prefixIcon: Icon(Icons.inventory_2),
                        ),
                        validator: (v) => v?.trim().isEmpty ?? true ? 'Required' : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _barcodeController,
                        decoration: const InputDecoration(
                          labelText: 'Barcode (Optional)',
                          prefixIcon: Icon(Icons.qr_code),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _buyingPriceController,
                        decoration: const InputDecoration(
                          labelText: 'Buying Price (KES)',
                          prefixIcon: Icon(Icons.attach_money),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
                        validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _wholesalePriceController,
                        decoration: const InputDecoration(
                          labelText: 'Wholesale Price (KES)',
                          prefixIcon: Icon(Icons.attach_money),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
                        validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _sellingPriceController,
                        decoration: const InputDecoration(
                          labelText: 'Selling Price (KES)',
                          prefixIcon: Icon(Icons.attach_money),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
                        validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _quantityController,
                        decoration: const InputDecoration(
                          labelText: 'Quantity',
                          prefixIcon: Icon(Icons.production_quantity_limits),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
                        validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _reorderLevelController,
                        decoration: const InputDecoration(
                          labelText: 'Reorder Level',
                          prefixIcon: Icon(Icons.warning_amber),
                          hintText: 'Minimum stock before alert',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Required';
                          final parsed = double.tryParse(v.trim());
                          if (parsed == null || parsed <= 0) return 'Must be greater than 0';
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppTheme.mediumGray)),
              ),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _isSaving ? null : _saveItem,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryWhite),
                          ),
                        )
                      : const Icon(Icons.save),
                  label: const Text('Add Item'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
