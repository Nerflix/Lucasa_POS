import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/location.dart';

class LocationRepository {
  final SupabaseClient _client;

  LocationRepository(this._client);

  Future<List<Location>> getAllLocations() async {
    final response = await _client.from('locations').select().order('name');

    return (response as List).map((json) => Location.fromJson(json)).toList();
  }

  Future<Location?> getLocation(String id) async {
    final response = await _client
        .from('locations')
        .select()
        .eq('id', id)
        .maybeSingle();

    if (response == null) return null;
    return Location.fromJson(response);
  }

  Future<void> upsertLocation(Location location) async {
    await _client.from('locations').upsert(location.toJson());
  }

  Future<void> deleteLocation(String id) async {
    await _client.from('locations').delete().eq('id', id);
  }
}
