import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/meter_reading.dart';

class MeterReadingRepository {
  final SupabaseClient _client;

  MeterReadingRepository(this._client);

  Future<void> insertMeterReading(MeterReading reading) async {
    await _client.from('meter_readings').insert(reading.toJson());
  }

  Future<String?> getLatestMeterReadingType(
    String locationId,
    String employeeId,
    String category,
  ) async {
    final response = await _client
        .from('meter_readings')
        .select('reading_type')
        .eq('location_id', locationId)
        .eq('employee_id', employeeId)
        .eq('category', category)
        .order('timestamp', ascending: false)
        .limit(1)
        .maybeSingle();

    return response?['reading_type'] as String?;
  }

  /// Gets the most recent meter reading for a location and category, across all employees.
  Future<MeterReading?> getLatestMeterReading(
    String locationId,
    String category,
  ) async {
    final response = await _client
        .from('meter_readings')
        .select()
        .eq('location_id', locationId)
        .eq('category', category)
        .order('timestamp', ascending: false)
        .limit(1)
        .maybeSingle();

    return response != null ? MeterReading.fromJson(response) : null;
  }

  Future<List<MeterReading>> getMeterReadingsByLocationAndCategory(
    String locationId,
    String category, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    var builder = _client
        .from('meter_readings')
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
    return (response as List)
        .map((json) => MeterReading.fromJson(json))
        .toList();
  }

  Future<void> updateMeterReading(MeterReading reading) async {
    await _client
        .from('meter_readings')
        .update(reading.toJson())
        .eq('id', reading.id);
  }

  Future<List<MeterReading>> getMeterReadingsByLocationAndRange(
    String locationId,
    DateTime start,
    DateTime end,
  ) async {
    final response = await _client
        .from('meter_readings')
        .select()
        .eq('location_id', locationId)
        .gte('timestamp', start.toIso8601String())
        .lte('timestamp', end.toIso8601String())
        .order('timestamp', ascending: false);
    return (response as List)
        .map((json) => MeterReading.fromJson(json))
        .toList();
  }

  Future<List<MeterReading>> getMeterReadingsByLocationsAndRange(
    List<String> locationIds,
    DateTime start,
    DateTime end,
  ) async {
    final response = await _client
        .from('meter_readings')
        .select()
        .inFilter('location_id', locationIds)
        .gte('timestamp', start.toIso8601String())
        .lte('timestamp', end.toIso8601String())
        .order('timestamp', ascending: false);
    return (response as List)
        .map((json) => MeterReading.fromJson(json))
        .toList();
  }
}
