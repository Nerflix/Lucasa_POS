import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/supabase_service.dart';
import '../models/employee.dart';
import '../models/location.dart';

class AuthRepository {
  final SupabaseService _supabase;

  AuthRepository(this._supabase);

  /// Authenticate user via Supabase
  /// Returns [Employee] if successful, throws error otherwise
  Future<Employee?> login(String username, String password) async {
    try {
      // 1. Fetch employee by username
      final response = await _supabase.client
          .from('employees')
          .select()
          .eq('username', username)
          .maybeSingle();

      if (response == null) {
        throw Exception('User not found');
      }

      // 2. Check active status
      if (response['is_active'] != true) {
        throw Exception('Account is inactive');
      }

      // 3. Verify password hash (Assuming simple comparison for now as per previous implementation)
      // Ideally, simple comparison is BAD. But migrating existing logic.
      // The previous logic hashed the input and compared.
      // I don't have the hash method here.
      // I'll rely on the AuthService to handle Hashing and pass the HASHED password here?
      // Or I should move the hashing logic here?
      // Use existing pattern: Return the employee data, let AuthService verify password.
      // actually, a repository usually handles data fetching.
      // Validating password is business logic -> Service.

      // Let's return the employee model and let AuthService verify the password hash.
      return Employee.fromJson(response);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> updatePassword(String employeeId, String newPasswordHash) async {
    await _supabase.client
        .from('employees')
        .update({'password_hash': newPasswordHash})
        .eq('id', employeeId);
  }

  Future<Employee> createEmployee(Employee employee) async {
    final data = employee.toJson();
    // remove ID if it's auto-generated, but here we generate it on client side usually?
    // Previous code generated ID on client side: 'emp_${DateTime.now().millisecondsSinceEpoch}'

    final response = await _supabase.client
        .from('employees')
        .insert(data)
        .select()
        .single();

    return Employee.fromJson(response);
  }

  Future<List<Location>> getActiveLocations() async {
    final response = await _supabase.client
        .from('locations')
        .select()
        .eq('is_active', true);

    return (response as List).map((e) => Location.fromJson(e)).toList();
  }

  Future<Location?> getLocation(String id) async {
    final response = await _supabase.client
        .from('locations')
        .select()
        .eq('id', id)
        .maybeSingle();

    if (response == null) return null;
    return Location.fromJson(response);
  }
}
