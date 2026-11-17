import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/item.dart';

class InventoryRepository {
  final SupabaseClient _client;

  InventoryRepository(this._client);

  Future<List<Item>> getItemsByLocation(String locationId) async {
    final response = await _client
        .from('items')
        .select()
        .eq('location_id', locationId);
    return (response as List).map((json) => Item.fromJson(json)).toList();
  }

  Future<List<Item>> getItemsByLocationAndCategory(
    String locationId,
    String category,
  ) async {
    final response = await _client
        .from('items')
        .select()
        .eq('location_id', locationId)
        .eq('category', category);
    return (response as List).map((json) => Item.fromJson(json)).toList();
  }

  Future<List<Item>> getItemsByLocationsAndCategory(
    List<String> locationIds,
    String category,
  ) async {
    final response = await _client
        .from('items')
        .select()
        .inFilter('location_id', locationIds)
        .eq('category', category);
    return (response as List).map((json) => Item.fromJson(json)).toList();
  }

  Future<Item?> getItem(String id) async {
    final response = await _client
        .from('items')
        .select()
        .eq('id', id)
        .maybeSingle();
    return response != null ? Item.fromJson(response) : null;
  }

  Future<List<Item>> searchItems(
    String locationId,
    String query, {
    String? category,
  }) async {
    var builder = _client
        .from('items')
        .select()
        .eq('location_id', locationId)
        .or('name.ilike.%$query%,barcode.eq.$query'); // simple search

    if (category != null) {
      builder = builder.eq('category', category);
    }

    // Applying limit to avoid too many results
    final response = await builder.limit(50);
    return (response as List).map((json) => Item.fromJson(json)).toList();
  }

  Future<void> updateItemQuantity(String itemId, double newQuantity) async {
    await _client
        .from('items')
        .update({
          'quantity': newQuantity,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', itemId);
  }

  Future<void> upsertItem(Item item) async {
    await _client.from('items').upsert(item.toJson());
  }

  Future<void> deleteItem(String itemId) async {
    await _client.from('items').delete().eq('id', itemId);
  }

  Future<List<Item>> searchItemsByCategory(
    String locationId,
    String category,
    String query,
  ) async {
    final response = await _client
        .from('items')
        .select()
        .eq('location_id', locationId)
        .eq('category', category)
        .or('name.ilike.%$query%,barcode.ilike.%$query%');
    return (response as List).map((json) => Item.fromJson(json)).toList();
  }

  /// Ensures default AGO and PMS items exist for a filling station location.
  /// Creates them with quantity=0 and price=0 if missing.
  Future<void> ensureDefaultFuelItems(
    String locationId,
    String employeeId,
  ) async {
    const fuelNames = ['AGO (diesel)', 'PMS (Super Petrol)'];
    const category = 'Filling Station';

    for (final name in fuelNames) {
      // Check if item already exists
      final existing = await _client
          .from('items')
          .select('id')
          .eq('location_id', locationId)
          .eq('category', category)
          .eq('name', name)
          .maybeSingle();

      if (existing == null) {
        final now = DateTime.now();
        final item = Item(
          id: 'fuel_${name.toLowerCase()}_${locationId}_${now.millisecondsSinceEpoch}',
          locationId: locationId,
          category: category,
          name: name,
          buyingPrice: 0,
          sellingPrice: 0,
          wholesalePrice: 0,
          quantity: 0,
          reorderLevel: 0,
          createdBy: employeeId,
          createdAt: now,
          updatedAt: now,
        );
        await _client.from('items').insert(item.toJson());
      }
    }
  }
}
