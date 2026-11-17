import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/sale.dart';
import '../models/customer.dart'; // For Credit updates
import '../models/sale_audit_log.dart';

class SalesRepository {
  final SupabaseClient _client;

  SalesRepository(this._client);

  /// Create a sale, its items, and optionally a credit record
  /// This should ideally be a Postgres Function (RPC) for atomicity
  /// but for now we do it sequentially.
  Future<void> processSale({
    required Sale sale,
    required List<SaleItem> items,
    Credit? credit,
  }) async {
    // 1. Save/Update Sale (use upsert to support completing suspended sales)
    await _client.from('sales').upsert(sale.toJson());

    // 2. Refresh Sale Items (Delete existing and insert new)
    await _client.from('sale_items').delete().eq('sale_id', sale.id);
    if (items.isNotEmpty) {
      final itemsJson = items.map((e) => e.toJson()).toList();
      await _client.from('sale_items').insert(itemsJson);
    }

    // 3. Save Credit (if any)
    if (credit != null) {
      await _client.from('credits').insert(credit.toJson());
    }

    // 4. Update Inventory Quantities (Batch or sequential)
    // NOTE: This is slow if done sequentially for many items over network
    // Better to use an RPC `process_sale` that handles all of this on server
    // For now, simple loop
    for (final item in items) {
      // We fetch current qty first to be safe? Or just decrement?
      // To be safe against race conditions, we should use an RPC 'decrement_stock'
      // But we'll trust the checked value for now or use `quantity = quantity - x` if Supabase supported it directly in update (it does via rpc usually)

      // We'll just decrement based on what we think is there, or simple fetch-update
      final currentItem = await _client
          .from('items')
          .select('quantity')
          .eq('id', item.itemId)
          .single();
      final currentQty = (currentItem['quantity'] as num).toDouble();
      final newQty =
          currentQty - item.quantity; // Assuming sale mode reduces qty

      // Note: logic for 'FuelSaleMode.price' vs 'liters' is handled in UI,
      // here `item.quantity` is the actual quantity to deduct.

      await _client
          .from('items')
          .update({'quantity': newQty})
          .eq('id', item.itemId);
    }
  }

  Future<List<Sale>> getSuspendedSales(
    String locationId,
    String category,
  ) async {
    final response = await _client
        .from('sales')
        .select()
        .eq('location_id', locationId)
        .eq('category', category)
        .eq('is_suspended', true);

    return (response as List).map((json) => Sale.fromJson(json)).toList();
  }

  Future<List<Sale>> getSalesByLocationsAndCategory(
    List<String> locationIds,
    String category, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    var query = _client
        .from('sales')
        .select()
        .inFilter('location_id', locationIds)
        .eq('category', category);

    if (startDate != null) {
      query = query.gte('timestamp', startDate.toIso8601String());
    }
    if (endDate != null) {
      query = query.lte('timestamp', endDate.toIso8601String());
    }

    final response = await query;
    return (response as List).map((json) => Sale.fromJson(json)).toList();
  }

  Future<List<Sale>> getSalesByLocationAndCategory(
    String locationId,
    String category, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    var query = _client
        .from('sales')
        .select()
        .eq('location_id', locationId)
        .eq('category', category);

    if (startDate != null) {
      query = query.gte('timestamp', startDate.toIso8601String());
    }
    if (endDate != null) {
      query = query.lte('timestamp', endDate.toIso8601String());
    }

    final response = await query;
    return (response as List).map((json) => Sale.fromJson(json)).toList();
  }

  Future<List<SaleItem>> getSaleItems(String saleId) async {
    final response = await _client
        .from('sale_items')
        .select()
        .eq('sale_id', saleId);

    return (response as List).map((json) => SaleItem.fromJson(json)).toList();
  }

  Future<List<SaleItem>> getSaleItemsBySaleIds(List<String> saleIds) async {
    if (saleIds.isEmpty) return [];

    final List<SaleItem> allItems = [];
    // Chunk requests to avoid hitting URL limit or query param limit
    const int chunkSize = 50;

    for (var i = 0; i < saleIds.length; i += chunkSize) {
      final end = (i + chunkSize < saleIds.length)
          ? i + chunkSize
          : saleIds.length;
      final chunk = saleIds.sublist(i, end);

      final response = await _client
          .from('sale_items')
          .select()
          .inFilter('sale_id', chunk);

      final items = (response as List)
          .map((json) => SaleItem.fromJson(json))
          .toList();
      allItems.addAll(items);
    }

    return allItems;
  }

  /// Delete a sale and REVERSE inventory for every item that was sold.
  /// Also writes an audit log entry.
  Future<void> deleteSaleWithInventoryReversal({
    required String saleId,
    required List<SaleItem> saleItems,
    required Sale sale,
    required String performedBy,
  }) async {
    // 1. Build full snapshot BEFORE deleting anything
    final snapshot = {
      'sale': sale.toJson(),
      'items': saleItems.map((i) => i.toJson()).toList(),
    };

    // 2. Reverse inventory for each item sold
    for (final item in saleItems) {
      try {
        final currentRow = await _client
            .from('items')
            .select('quantity')
            .eq('id', item.itemId)
            .maybeSingle();
        if (currentRow != null) {
          final currentQty = (currentRow['quantity'] as num).toDouble();
          final restoredQty = currentQty + item.quantity;
          await _client
              .from('items')
              .update({'quantity': restoredQty})
              .eq('id', item.itemId);
        }
      } catch (_) {
        // Item might have been deleted from inventory — skip gracefully
      }
    }

    // 3. Write audit log
    await _writeAuditLog(
      action: 'DELETE',
      saleReceiptId: sale.saleId,
      performedBy: performedBy,
      locationId: sale.locationId,
      category: sale.category,
      snapshot: snapshot,
    );

    // 4. Delete related records then the sale
    await _client.from('credits').delete().eq('sale_id', saleId);
    await _client.from('sale_items').delete().eq('sale_id', saleId);
    await _client.from('sales').delete().eq('id', saleId);
  }

  /// Update item quantities in an existing sale and adjust inventory accordingly.
  /// Also updates the sale totals and writes an audit log entry.
  Future<void> updateSaleItems({
    required Sale sale,
    required List<SaleItem> oldItems,
    required List<SaleItem> newItems,
    required String performedBy,
  }) async {
    // 1. Build before/after snapshot for audit
    final List<Map<String, dynamic>> changes = [];
    for (final newItem in newItems) {
      final oldItem = oldItems.firstWhere(
        (o) => o.id == newItem.id,
        orElse: () => newItem,
      );
      if (oldItem.quantity != newItem.quantity) {
        changes.add({
          'item_name': newItem.itemName,
          'old_qty': oldItem.quantity,
          'new_qty': newItem.quantity,
        });
      }
    }

    final snapshot = {
      'sale_id': sale.saleId,
      'changes': changes,
      'before_items': oldItems.map((i) => i.toJson()).toList(),
      'after_items': newItems.map((i) => i.toJson()).toList(),
    };

    // 2. Adjust inventory per item (delta = newQty - oldQty)
    for (final newItem in newItems) {
      final oldItem = oldItems.firstWhere(
        (o) => o.id == newItem.id,
        orElse: () => newItem.copyWith(quantity: newItem.quantity),
      );
      final delta = newItem.quantity - oldItem.quantity;
      if (delta == 0) continue;

      try {
        final currentRow = await _client
            .from('items')
            .select('quantity')
            .eq('id', newItem.itemId)
            .maybeSingle();
        if (currentRow != null) {
          final currentQty = (currentRow['quantity'] as num).toDouble();
          // Selling more → decrement; selling less → increment
          final adjustedQty = currentQty - delta;
          await _client
              .from('items')
              .update({'quantity': adjustedQty})
              .eq('id', newItem.itemId);
        }
      } catch (_) {
        // Item removed from inventory — skip
      }
    }

    // 3. Recalculate totals
    final newTotal = newItems.fold<double>(0, (sum, i) => sum + i.subtotal);
    final newProfit = newItems.fold<double>(
      0,
      (sum, i) => sum + (i.sellingPrice - i.buyingPrice) * i.quantity,
    );

    // 4. Delete and re-insert sale_items
    await _client.from('sale_items').delete().eq('sale_id', sale.id);
    if (newItems.isNotEmpty) {
      await _client
          .from('sale_items')
          .insert(newItems.map((i) => i.toJson()).toList());
    }

    // 5. Update sale totals
    await _client
        .from('sales')
        .update({'total_amount': newTotal, 'profit': newProfit})
        .eq('id', sale.id);

    // 6. Write audit log
    await _writeAuditLog(
      action: 'EDIT',
      saleReceiptId: sale.saleId,
      performedBy: performedBy,
      locationId: sale.locationId,
      category: sale.category,
      snapshot: snapshot,
    );
  }

  /// Simple delete for SUSPENDED sales only — these never decremented inventory.
  /// For completed sales, use [deleteSaleWithInventoryReversal] instead.
  Future<void> deleteSale(String saleId) async {
    await _client.from('credits').delete().eq('sale_id', saleId);
    await _client.from('sale_items').delete().eq('sale_id', saleId);
    await _client.from('sales').delete().eq('id', saleId);
  }

  /// Update only the sale-level fields (payment method, amount paid, notes).
  /// No inventory change needed.
  Future<void> updateSale(Sale sale) async {
    await _client.from('sales').update(sale.toJson()).eq('id', sale.id);
  }

  Future<Sale?> getSale(String saleId) async {
    final response = await _client
        .from('sales')
        .select()
        .eq('id', saleId)
        .maybeSingle();

    return response != null ? Sale.fromJson(response) : null;
  }

  Future<List<Sale>> getSuspendedSalesByCategory(
    String locationId,
    String category,
  ) async {
    final response = await _client
        .from('sales')
        .select()
        .eq('location_id', locationId)
        .eq('category', category)
        .eq('is_suspended', true)
        .order('timestamp', ascending: false);
    return (response as List).map((json) => Sale.fromJson(json)).toList();
  }

  // ── Audit Log ──────────────────────────────────────────────────────────────

  Future<void> _writeAuditLog({
    required String action,
    required String saleReceiptId,
    required String performedBy,
    required String locationId,
    required String category,
    required Map<String, dynamic> snapshot,
  }) async {
    try {
      await _client.from('sale_audit_logs').insert({
        'action': action,
        'sale_id': saleReceiptId,
        'performed_by': performedBy,
        'performed_at': DateTime.now().toIso8601String(),
        'location_id': locationId,
        'category': category,
        'snapshot': snapshot,
      });
    } catch (e) {
      // Audit log failure should never block the main operation
      // but we log it for debugging
      // ignore: avoid_print
      print('[AuditLog] Failed to write audit entry: $e');
    }
  }

  Future<List<SaleAuditLog>> getAuditLogs({
    required List<String> locationIds,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    if (locationIds.isEmpty) return [];

    var query = _client
        .from('sale_audit_logs')
        .select()
        .inFilter('location_id', locationIds);

    if (startDate != null) {
      query = query.gte('performed_at', startDate.toIso8601String());
    }
    if (endDate != null) {
      query = query.lte('performed_at', endDate.toIso8601String());
    }

    final response = await query.order('performed_at', ascending: false);
    return (response as List)
        .map((json) => SaleAuditLog.fromJson(json))
        .toList();
  }
}
