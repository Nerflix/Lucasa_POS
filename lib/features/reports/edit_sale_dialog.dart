import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/sale.dart';
import '../../data/repositories/sales_repository.dart';
import '../../services/auth_service.dart';

class EditSaleDialog extends StatefulWidget {
  final Sale sale;
  final List<SaleItem> items;

  const EditSaleDialog({super.key, required this.sale, required this.items});

  @override
  State<EditSaleDialog> createState() => _EditSaleDialogState();
}

class _EditSaleDialogState extends State<EditSaleDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _amountPaidController;
  late TextEditingController _notesController;
  late String _selectedPaymentMethod;
  bool _isSaving = false;

  // Editable item quantities — maps item index → qty controller
  late List<TextEditingController> _qtyControllers;

  @override
  void initState() {
    super.initState();
    _amountPaidController = TextEditingController(
      text: widget.sale.amountPaid.toStringAsFixed(0),
    );
    _notesController = TextEditingController(text: widget.sale.notes ?? '');
    _selectedPaymentMethod = widget.sale.paymentMethod;

    _qtyControllers = widget.items.map((item) {
      return TextEditingController(
        text: item.quantity.toStringAsFixed(
          item.quantity == item.quantity.truncate() ? 0 : 2,
        ),
      );
    }).toList();
  }

  @override
  void dispose() {
    _amountPaidController.dispose();
    _notesController.dispose();
    for (final c in _qtyControllers) {
      c.dispose();
    }
    super.dispose();
  }

  /// Build updated SaleItem list from controller values
  List<SaleItem> _buildUpdatedItems() {
    return List.generate(widget.items.length, (i) {
      final item = widget.items[i];
      final newQty = double.tryParse(_qtyControllers[i].text) ?? item.quantity;
      final newSubtotal = item.sellingPrice * newQty;
      return item.copyWith(quantity: newQty, subtotal: newSubtotal);
    });
  }

  double get _computedTotal {
    final updated = _buildUpdatedItems();
    return updated.fold(0.0, (sum, i) => sum + i.subtotal);
  }

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final salesRepo = Provider.of<SalesRepository>(context, listen: false);
      final authService = Provider.of<AuthService>(context, listen: false);
      final actor =
          authService.currentEmployee?.firstName ??
          authService.currentEmployee?.id ??
          'Unknown';

      final updatedItems = _buildUpdatedItems();
      final newTotal = updatedItems.fold<double>(0, (s, i) => s + i.subtotal);
      final newAmountPaid =
          double.tryParse(_amountPaidController.text) ?? widget.sale.amountPaid;
      final changeGiven = newAmountPaid - newTotal;

      final qtyChanged = updatedItems.any((ui) {
        final original = widget.items.firstWhere((o) => o.id == ui.id);
        return original.quantity != ui.quantity;
      });

      if (qtyChanged) {
        // Quantities changed — inventory adjustment + audit log
        await salesRepo.updateSaleItems(
          sale: widget.sale,
          oldItems: widget.items,
          newItems: updatedItems,
          performedBy: actor,
        );
      }

      // Also update sale-level fields (payment, amount paid, notes, new total)
      final updatedSale = Sale(
        id: widget.sale.id,
        saleId: widget.sale.saleId,
        locationId: widget.sale.locationId,
        category: widget.sale.category,
        employeeId: widget.sale.employeeId,
        paymentMethod: _selectedPaymentMethod,
        totalAmount: newTotal,
        amountPaid: newAmountPaid,
        changeGiven: changeGiven > 0 ? changeGiven : 0,
        profit: updatedItems.fold<double>(
          0,
          (s, i) => s + (i.sellingPrice - i.buyingPrice) * i.quantity,
        ),
        isSuspended: widget.sale.isSuspended,
        suspensionNotes: widget.sale.suspensionNotes,
        employeeName: widget.sale.employeeName,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        timestamp: widget.sale.timestamp,
      );

      await salesRepo.updateSale(updatedSale);

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating sale: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentPaid =
        double.tryParse(_amountPaidController.text) ?? widget.sale.amountPaid;
    final total = _computedTotal;
    final currentChange = currentPaid - total;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SingleChildScrollView(
        child: Container(
          width: 560,
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header ──────────────────────────────────────────────
                Row(
                  children: [
                    const Icon(Icons.edit, color: AppTheme.primaryOrange),
                    const SizedBox(width: 12),
                    const Text(
                      'Edit Sale',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // ── Sale ID Info ─────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.lightGray,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Sale ID: ${widget.sale.saleId}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'New Total: KES ${total.toStringAsFixed(0)}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // ── Items Table ──────────────────────────────────────────
                if (widget.items.isNotEmpty) ...[
                  const Text(
                    'Items (edit quantities)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  Table(
                    columnWidths: const {
                      0: FlexColumnWidth(3),
                      1: FlexColumnWidth(2),
                      2: FlexColumnWidth(2),
                      3: FlexColumnWidth(2),
                    },
                    border: TableBorder.all(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    children: [
                      // Header row
                      TableRow(
                        decoration: BoxDecoration(color: Colors.grey.shade100),
                        children: const [
                          Padding(
                            padding: EdgeInsets.all(8),
                            child: Text(
                              'Item',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.all(8),
                            child: Text(
                              'Qty',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.all(8),
                            child: Text(
                              'Price',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.all(8),
                            child: Text(
                              'Subtotal',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      // Data rows
                      for (int i = 0; i < widget.items.length; i++)
                        _buildItemRow(i),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],

                // ── Payment Method ───────────────────────────────────────
                DropdownButtonFormField<String>(
                  value: _selectedPaymentMethod,
                  decoration: const InputDecoration(
                    labelText: 'Payment Method',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.payment),
                  ),
                  items:
                      [
                        AppConstants.paymentCash,
                        AppConstants.paymentMpesa,
                        AppConstants.paymentEquity,
                        AppConstants.paymentCredit,
                      ].map((method) {
                        return DropdownMenuItem(
                          value: method,
                          child: Text(method),
                        );
                      }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _selectedPaymentMethod = val);
                    }
                  },
                ),
                const SizedBox(height: 16),

                // ── Amount Paid ──────────────────────────────────────────
                TextFormField(
                  controller: _amountPaidController,
                  decoration: const InputDecoration(
                    labelText: 'Amount Paid (KES)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.attach_money),
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (_) => setState(() {}),
                  validator: (val) {
                    if (val == null || val.isEmpty) return 'Required';
                    if (double.tryParse(val) == null) return 'Invalid number';
                    return null;
                  },
                ),
                const SizedBox(height: 8),

                // ── Change / Balance ─────────────────────────────────────
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    currentChange >= 0
                        ? 'Change: KES ${currentChange.toStringAsFixed(0)}'
                        : 'Balance: KES ${(-currentChange).toStringAsFixed(0)}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: currentChange >= 0
                          ? AppTheme.success
                          : AppTheme.error,
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // ── Notes ────────────────────────────────────────────────
                TextFormField(
                  controller: _notesController,
                  decoration: const InputDecoration(
                    labelText: 'Notes',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.note),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 32),

                // ── Actions ──────────────────────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: _isSaving ? null : _saveChanges,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.save),
                      label: const Text('Save Changes'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryOrange,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  TableRow _buildItemRow(int index) {
    final item = widget.items[index];
    final qtyCtrl = _qtyControllers[index];
    final qty = double.tryParse(qtyCtrl.text) ?? item.quantity;
    final subtotal = item.sellingPrice * qty;

    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Text(item.itemName, style: const TextStyle(fontSize: 13)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: TextFormField(
            controller: qtyCtrl,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              border: OutlineInputBorder(),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
            ],
            onChanged: (_) => setState(() {}),
            validator: (val) {
              if (val == null || val.isEmpty) return '?';
              final v = double.tryParse(val);
              if (v == null || v < 0) return '?';
              return null;
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Text(
            'KES ${item.sellingPrice.toStringAsFixed(0)}',
            style: const TextStyle(fontSize: 13),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Text(
            'KES ${subtotal.toStringAsFixed(0)}',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}
