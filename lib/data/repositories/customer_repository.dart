import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/customer.dart';

class CustomerRepository {
  final SupabaseClient _client;

  CustomerRepository(this._client);

  Future<List<Customer>> searchCustomers(
    String locationId,
    String query,
  ) async {
    final response = await _client
        .from('customers')
        .select()
        .eq('location_id', locationId)
        .or(
          'first_name.ilike.%$query%,last_name.ilike.%$query%,phone.ilike.%$query%',
        )
        .limit(20);

    return (response as List).map((json) => Customer.fromJson(json)).toList();
  }

  Future<List<Customer>> getAllCustomers(String locationId) async {
    final response = await _client
        .from('customers')
        .select()
        .eq('location_id', locationId)
        .order('first_name');

    return (response as List).map((json) => Customer.fromJson(json)).toList();
  }

  Future<List<Customer>> getCustomersByLocationAndCategory(
    String locationId,
    String category,
  ) async {
    final response = await _client
        .from('customers')
        .select()
        .eq('location_id', locationId)
        .eq('category', category)
        .order('first_name');

    return (response as List).map((json) => Customer.fromJson(json)).toList();
  }

  Future<List<Customer>> getCustomersByLocationsAndCategory(
    List<String> locationIds,
    String category,
  ) async {
    final response = await _client
        .from('customers')
        .select()
        .filter('location_id', 'in', locationIds)
        .eq('category', category)
        .order('first_name');

    return (response as List).map((json) => Customer.fromJson(json)).toList();
  }

  Future<Customer?> getCustomer(String id) async {
    final response = await _client
        .from('customers')
        .select()
        .eq('id', id)
        .maybeSingle();

    if (response == null) return null;
    return Customer.fromJson(response);
  }

  Future<void> createCustomer(Customer customer) async {
    await _client.from('customers').insert(customer.toJson());
  }

  Future<void> upsertCustomer(Customer customer) async {
    await _client.from('customers').upsert(customer.toJson());
  }

  Future<void> deleteCustomer(String id) async {
    await _client.from('customers').delete().eq('id', id);
  }
}
