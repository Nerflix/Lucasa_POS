import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/employee.dart';

class EmployeeRepository {
  final SupabaseClient _client;

  EmployeeRepository(this._client);

  Future<List<Employee>> getAllEmployees() async {
    final response = await _client.from('employees').select();
    return (response as List).map((json) => Employee.fromJson(json)).toList();
  }

  Future<List<Employee>> getEmployeesByLocation(String locationId) async {
    final response = await _client
        .from('employees')
        .select()
        .eq('location_id', locationId);
    return (response as List).map((json) => Employee.fromJson(json)).toList();
  }

  Future<void> createEmployee(Employee employee) async {
    await _client.from('employees').insert(employee.toJson());
  }

  Future<void> updateEmployee(Employee employee) async {
    await _client
        .from('employees')
        .update(employee.toJson())
        .eq('id', employee.id);
  }

  Future<Employee?> getEmployee(String employeeId) async {
    final response = await _client
        .from('employees')
        .select()
        .eq('id', employeeId)
        .maybeSingle();

    if (response == null) return null;
    return Employee.fromJson(response);
  }

  Future<void> upsertEmployee(Employee employee) async {
    await _client.from('employees').upsert(employee.toJson());
  }

  Future<void> deactivateEmployee(String employeeId) async {
    await _client
        .from('employees')
        .update({'is_active': false})
        .eq('id', employeeId);
  }

  Future<void> deleteEmployee(String employeeId) async {
    await _client.from('employees').delete().eq('id', employeeId);
  }
}
