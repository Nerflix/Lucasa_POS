import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/receiving.dart';

class ReceivingRepository {
  final SupabaseClient _client;

  ReceivingRepository(this._client);

  Future<void> insertReceiving({
    required Receiving receiving,
    required List<ReceivingItem> items,
  }) async {
    // 1. Insert Receiving
    await _client.from('receivings').insert(receiving.toJson());

    // 2. Insert Items
    if (items.isNotEmpty) {
      final itemsJson = items.map((e) => e.toJson()).toList();
      await _client.from('receiving_items').insert(itemsJson);
    }

    // 3. Update Inventory Quantities
    for (final item in items) {
      final currentItem = await _client
          .from('items')
          .select('quantity')
          .eq('id', item.itemId)
          .single();
      final currentQty = (currentItem['quantity'] as num).toDouble();
      final newQty = currentQty + item.quantity;

      await _client
          .from('items')
          .update({'quantity': newQty})
          .eq('id', item.itemId);
    }
  }

  Future<List<Receiving>> getReceivingsByLocationAndCategory(
    String locationId,
    String category, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    var builder = _client
        .from('receivings')
        .select()
        .eq('location_id', locationId)
        .eq('category', category);

    if (startDate != null) {
      builder = builder.gte('timestamp', startDate.toIso8601String());
    }
    if (endDate != null) {
      builder = builder.lte('timestamp', endDate.toIso8601String());
    }

    final response = await builder.order('timestamp', ascending: false);
    return (response as List).map((json) => Receiving.fromJson(json)).toList();
  }

  Future<List<Receiving>> getReceivingsByLocationsAndCategory(
    List<String> locationIds,
    String category, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    var builder = _client
        .from('receivings')
        .select()
        .inFilter('location_id', locationIds)
        .eq('category', category);

    if (startDate != null) {
      builder = builder.gte('timestamp', startDate.toIso8601String());
    }
    if (endDate != null) {
      builder = builder.lte('timestamp', endDate.toIso8601String());
    }

    final response = await builder.order('timestamp', ascending: false);
    return (response as List).map((json) => Receiving.fromJson(json)).toList();
  }

  Future<List<ReceivingItem>> getReceivingItems(String receivingId) async {
    final response = await _client
        .from('receiving_items')
        .select()
        .eq('receiving_id', receivingId);

    return (response as List)
        .map((json) => ReceivingItem.fromJson(json))
        .toList();
  }
}
