import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:drift/drift.dart' as drift;
import '../../core/theme/app_theme.dart';
import '../../core/utils/toast_utils.dart';
import '../../data/database/app_database.dart';

class ItemDetailPage extends StatefulWidget {
  final Item item;
  final bool canEdit;

  const ItemDetailPage({
    super.key,
    required this.item,
    required this.canEdit,
  });

  @override
  State<ItemDetailPage> createState() => _ItemDetailPageState();
}

class _ItemDetailPageState extends State<ItemDetailPage> {
  late final TextEditingController _nameController;
  late final TextEditingController _barcodeController;
  late final TextEditingController _buyingController;
  late final TextEditingController _sellingController;
  late final TextEditingController _wholesaleController;
  late final TextEditingController _quantityController;
  late final TextEditingController _reorderLevelController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.item.name);
    _barcodeController = TextEditingController(text: widget.item.barcode ?? '');
    _buyingController = TextEditingController(
      text: widget.item.buyingPrice.toStringAsFixed(2),
    );
    _sellingController = TextEditingController(
      text: widget.item.sellingPrice.toStringAsFixed(2),
    );
    _wholesaleController = TextEditingController(
      text: widget.item.wholesalePrice.toStringAsFixed(2),
    );
    _quantityController = TextEditingController(
      text: widget.item.quantity.toStringAsFixed(3),
    );
    _reorderLevelController = TextEditingController(
      text: widget.item.reorderLevel.toStringAsFixed(0),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _barcodeController.dispose();
    _buyingController.dispose();
    _sellingController.dispose();
    _wholesaleController.dispose();
    _quantityController.dispose();
    _reorderLevelController.dispose();
    super.dispose();
  }

  double? _parseNumber(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return double.tryParse(trimmed.replaceAll(',', '.'));
  }

  Future<void> _save() async {
    if (!widget.canEdit || _isSaving) {
      return;
    }

    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ToastUtils.showError('Item name is required.');
      return;
    }

    final buying = _parseNumber(_buyingController.text);
    final selling = _parseNumber(_sellingController.text);
    final wholesale = _parseNumber(_wholesaleController.text);
    final quantity = _parseNumber(_quantityController.text);
    final reorderLevel = _parseNumber(_reorderLevelController.text);

    if (buying == null || selling == null || wholesale == null || quantity == null || reorderLevel == null) {
      ToastUtils.showError('Enter valid numbers for prices, quantity, and reorder level.');
      return;
    }

    if (reorderLevel <= 0) {
      ToastUtils.showError('Reorder level must be greater than 0.');
      return;
    }

    setState(() => _isSaving = true);
    final db = Provider.of<AppDatabase>(context, listen: false);
    final now = DateTime.now();

    try {
      final updated = ItemsCompanion(
        id: drift.Value(widget.item.id),
        locationId: drift.Value(widget.item.locationId),
        category: drift.Value(widget.item.category),
        name: drift.Value(name),
        barcode: drift.Value(
          _barcodeController.text.trim().isEmpty
              ? null
              : _barcodeController.text.trim(),
        ),
        buyingPrice: drift.Value(buying),
        wholesalePrice: drift.Value(wholesale),
        sellingPrice: drift.Value(selling),
        quantity: drift.Value(quantity),
        reorderLevel: drift.Value(reorderLevel),
        createdBy: drift.Value(widget.item.createdBy),
        createdAt: drift.Value(widget.item.createdAt),
        updatedAt: drift.Value(now),
        syncedAt: drift.Value(widget.item.syncedAt),
      );

      await db.updateItem(updated);
      if (mounted) {
        ToastUtils.showSuccess('Item updated');
        Navigator.pop(context, true);
      }
    } catch (e) {
      ToastUtils.showError('Unable to update item.');
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final readOnly = !widget.canEdit || _isSaving;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Item Details'),
        actions: [
          if (widget.canEdit)
            TextButton(
              onPressed: readOnly ? null : _save,
              child: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Name'),
            readOnly: readOnly,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _barcodeController,
            decoration: const InputDecoration(labelText: 'Barcode'),
            readOnly: readOnly,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _buyingController,
            decoration: const InputDecoration(labelText: 'Buying Price'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
            ],
            readOnly: readOnly,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _wholesaleController,
            decoration: const InputDecoration(labelText: 'Wholesale Price'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
            ],
            readOnly: readOnly,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _sellingController,
            decoration: const InputDecoration(labelText: 'Selling Price'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
            ],
            readOnly: readOnly,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _quantityController,
            decoration: const InputDecoration(labelText: 'Quantity'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,3}')),
            ],
            readOnly: readOnly,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _reorderLevelController,
            decoration: const InputDecoration(labelText: 'Reorder Level'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,3}')),
            ],
            readOnly: readOnly,
          ),
          if (!widget.canEdit)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                'You do not have permission to edit items.',
                style: TextStyle(color: AppTheme.darkGray),
              ),
            ),
        ],
      ),
    );
  }
}
