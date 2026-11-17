import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' as drift;
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/toast_utils.dart';
import '../../data/database/app_database.dart';
import '../../services/auth_service.dart';

class ReceivingsPage extends StatefulWidget {
  const ReceivingsPage({super.key});

  @override
  State<ReceivingsPage> createState() => _ReceivingsPageState();
}

class _ReceivingsPageState extends State<ReceivingsPage> {
  final _searchController = TextEditingController();
  final _uuid = const Uuid();
  List<Item> _searchResults = [];
  final List<_ReceivingLine> _lines = [];
  bool _isSaving = false;

  @override
  void dispose() {
    _searchController.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  Future<void> _searchItems(String query) async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final db = Provider.of<AppDatabase>(context, listen: false);
    final locationId = _getCurrentLocationId(authService);
    if (locationId == null) return;

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

  void _addLine(Item item) {
    final existing = _lines.indexWhere((line) => line.item.id == item.id);
    if (existing != -1) {
      _lines[existing].incrementQuantity();
      setState(() {});
      return;
    }

    setState(() {
      _lines.add(_ReceivingLine(item));
      _searchResults = [];
      _searchController.clear();
    });
    FocusScope.of(context).unfocus();
  }

  void _removeLine(_ReceivingLine line) {
    setState(() {
      _lines.remove(line);
      line.dispose();
    });
  }

  double _calculateTotal() {
    return _lines.fold(0, (sum, line) => sum + line.subtotal);
  }

  Future<void> _completeReceiving() async {
    if (_lines.isEmpty) {
      ToastUtils.showError('Add at least one item.');
      return;
    }

    final authService = Provider.of<AuthService>(context, listen: false);
    if (!authService.hasPermission('canManageReceiving')) {
      ToastUtils.showError('You do not have permission to receive items.');
      return;
    }

    final locationId = _getCurrentLocationId(authService);
    if (locationId == null) return;

    setState(() => _isSaving = true);
    final db = Provider.of<AppDatabase>(context, listen: false);
    final now = DateTime.now();
    final receivingId = _buildReceivingId(locationId, now);
    final receivingDbId = _uuid.v4();
    final totalAmount = _calculateTotal();

    try {
      await db.insertReceiving(
        ReceivingsCompanion(
          id: drift.Value(receivingDbId),
          receivingId: drift.Value(receivingId),
          locationId: drift.Value(locationId),
          category: drift.Value(authService.currentCategory ?? AppConstants.categoryFillingStation),
          employeeId: drift.Value(authService.currentEmployee!.id),
          totalAmount: drift.Value(totalAmount),
          timestamp: drift.Value(now),
        ),
      );

      for (final line in _lines) {
        await db.insertReceivingItem(
          ReceivingItemsCompanion(
            id: drift.Value(_uuid.v4()),
            receivingId: drift.Value(receivingDbId),
            itemId: drift.Value(line.item.id),
            itemName: drift.Value(line.item.name),
            quantity: drift.Value(line.quantity),
            buyingPrice: drift.Value(line.buyingPrice),
            subtotal: drift.Value(line.subtotal),
          ),
        );

        await _updateItemAfterReceiving(db, line, now);
      }

      ToastUtils.showSuccess('Receiving saved successfully');
      _clearForm();
    } catch (e) {
      ToastUtils.showError('Unable to save receiving. Please try again.');
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _updateItemAfterReceiving(
    AppDatabase db,
    _ReceivingLine line,
    DateTime now,
  ) async {
    final item = await db.getItem(line.item.id);
    if (item == null) return;

    final newQty = item.quantity + line.quantity;
    final updated = ItemsCompanion(
      id: drift.Value(item.id),
      locationId: drift.Value(item.locationId),
      category: drift.Value(item.category),
      name: drift.Value(item.name),
      barcode: drift.Value(item.barcode),
      buyingPrice: drift.Value(line.buyingPrice),
      wholesalePrice: drift.Value(item.wholesalePrice),
      sellingPrice: drift.Value(item.sellingPrice),
      quantity: drift.Value(newQty),
      createdBy: drift.Value(item.createdBy),
      createdAt: drift.Value(item.createdAt),
      updatedAt: drift.Value(now),
      syncedAt: drift.Value(item.syncedAt),
    );

    await db.updateItem(updated);
  }

  String _buildReceivingId(String locationId, DateTime now) {
    final timestamp = DateFormat(AppConstants.dateFormatSaleId).format(now);
    final shortLoc = locationId.length >= 4 ? locationId.substring(0, 4) : locationId;
    return 'RCV-${shortLoc.toUpperCase()}-$timestamp';
  }

  void _clearForm() {
    for (final line in _lines) {
      line.dispose();
    }
    setState(() {
      _lines.clear();
      _searchResults.clear();
      _searchController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth > 900;
    final authService = Provider.of<AuthService>(context);

    if (!authService.hasPermission('canManageReceiving')) {
      return const Scaffold(
        body: Center(
          child: Text('You do not have permission to receive items.'),
        ),
      );
    }

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: isWide
            ? Row(
                children: [
                  Expanded(child: _buildSearchPanel()),
                  const SizedBox(width: 16),
                  Expanded(child: _buildReceivingPanel()),
                ],
              )
            : ListView(
                children: [
                  _buildSearchPanel(),
                  const SizedBox(height: 16),
                  _buildReceivingPanel(),
                ],
              ),
      ),
    );
  }

  Widget _buildSearchPanel() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Search Items',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                labelText: 'Search by name or barcode',
                prefixIcon: Icon(Icons.search),
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
                      return ListTile(
                        title: Text(item.name),
                        subtitle: Text('Buying: KES ${item.buyingPrice.toStringAsFixed(0)}'),
                        trailing: const Icon(Icons.add_circle_outline, color: AppTheme.primaryOrange),
                        onTap: () => _addLine(item),
                      );
                    },
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildReceivingPanel() {
    final total = _calculateTotal();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Receiving',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            if (_lines.isEmpty)
              const Text(
                'No items added',
                style: TextStyle(color: AppTheme.darkGray),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _lines.length,
                itemBuilder: (context, index) {
                  final line = _lines[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  line.item.name,
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close, color: AppTheme.error),
                                onPressed: () => _removeLine(line),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: line.priceController,
                                  decoration: const InputDecoration(
                                    labelText: 'Buying Price',
                                  ),
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                                  ],
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextField(
                                  controller: line.quantityController,
                                  decoration: const InputDecoration(
                                    labelText: 'Quantity',
                                  ),
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                                  ],
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Subtotal: KES ${line.subtotal.toStringAsFixed(0)}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            const SizedBox(height: 12),
            Text(
              'Total: KES ${total.toStringAsFixed(0)}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _isSaving ? null : _completeReceiving,
              icon: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryWhite),
                      ),
                    )
                  : const Icon(Icons.check_circle),
              label: const Text('Complete Receiving'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReceivingLine {
  final Item item;
  final TextEditingController priceController;
  final TextEditingController quantityController;

  _ReceivingLine(this.item)
      : priceController = TextEditingController(text: item.buyingPrice.toStringAsFixed(2)),
        quantityController = TextEditingController(text: '1');

  double get buyingPrice => double.tryParse(priceController.text) ?? item.buyingPrice;
  double get quantity => double.tryParse(quantityController.text) ?? 1;
  double get subtotal => buyingPrice * quantity;

  void incrementQuantity() {
    final current = double.tryParse(quantityController.text) ?? 0;
    quantityController.text = (current + 1).toStringAsFixed(0);
  }

  void dispose() {
    priceController.dispose();
    quantityController.dispose();
  }
}
