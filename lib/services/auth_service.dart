import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import '../core/constants/app_constants.dart';
import '../data/models/employee.dart';
import '../data/repositories/auth_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/config/supabase_config.dart';

/// Authentication service for managing user login and permissions
class AuthService extends ChangeNotifier {
  final AuthRepository _authRepository;

  Employee? _currentEmployee;
  String? _currentCategory; // 'Filling Station' or 'Car Sale'
  bool _hasOpenedMeterReadings = false;
  bool _hasClosedMeterReadings = false;

  AuthService(this._authRepository);

  Employee? get currentEmployee => _currentEmployee;
  String? get currentCategory => _currentCategory;
  bool get isLoggedIn => _currentEmployee != null;
  bool get hasOpenedMeterReadings => _hasOpenedMeterReadings;
  bool get hasClosedMeterReadings => _hasClosedMeterReadings;

  String get userRole => _currentEmployee?.role ?? '';
  bool get isSuperAdmin => userRole == AppConstants.roleSuperAdmin;
  bool get isAdmin => userRole == AppConstants.roleAdmin;
  bool get isEmployee => userRole == AppConstants.roleEmployee;

  /// Get location IDs that current employee has access to
  List<String> get allowedLocationIds {
    if (_currentEmployee?.locationId == null) return [];

    // Try to parse as JSON array (for admins)
    if (_currentEmployee!.locationId!.startsWith('[')) {
      try {
        final locationIds = json.decode(_currentEmployee!.locationId!) as List;
        return locationIds.cast<String>();
      } catch (e) {
        print('Error parsing admin location IDs: $e');
        return [];
      }
    }

    // Single location (for employees)
    return [_currentEmployee!.locationId!];
  }

  /// Check if current employee has access to multiple locations
  bool get hasMultipleLocations => allowedLocationIds.length > 1;

  /// Check if current employee has access to specific location
  bool hasAccessToLocation(String locationId) {
    return allowedLocationIds.contains(locationId);
  }

  /// Hash password using SHA256
  String _hashPassword(String password) {
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Login with username and password
  Future<AuthResult> login({
    required String username,
    required String password,
  }) async {
    try {
      print('🔐 Login attempt - Username: $username');

      // STEP 0: Check for hardcoded Super Admin credentials FIRST
      if (username.toLowerCase() == 'superadmin') {
        if (password == 'SuperAdmin@2026!') {
          _currentEmployee = Employee(
            id: 'super_admin',
            locationId: null,
            role: AppConstants.roleSuperAdmin,
            firstName: 'Super',
            middleName: null,
            surname: 'Administrator',
            phone: '0000000000',
            email: 'superadmin@lucasa.pos',
            username: 'superadmin',
            passwordHash: _hashPassword('SuperAdmin@2026!'),
            permissions: null,
            isActive: true,
            createdAt: DateTime.now(),
          );

          _hasClosedMeterReadings = false;
          _hasOpenedMeterReadings = false;
          notifyListeners();
          return AuthResult(
            success: true,
            message: 'Super Admin login successful',
          );
        } else {
          return AuthResult(success: false, message: 'Incorrect password');
        }
      }

      // STEP 1: Fetch employee from Repository
      final employee = await _authRepository.login(username, password);

      if (employee == null) {
        return AuthResult(success: false, message: 'User not found');
      }

      // STEP 2: Verify password
      final hashedPassword = _hashPassword(password);
      if (employee.passwordHash != hashedPassword) {
        return AuthResult(success: false, message: 'Incorrect password');
      }

      _currentEmployee = employee;
      _hasClosedMeterReadings = false;
      _hasOpenedMeterReadings = false;
      notifyListeners();
      return AuthResult(success: true, message: 'Login successful');
    } catch (e) {
      print('❌ Login failed: $e');
      return AuthResult(
        success: false,
        message: e.toString().contains('Exception:')
            ? e.toString().replaceAll('Exception: ', '')
            : 'Login failed. Please check your connection.',
      );
    }
  }

  /// Set category after login (Filling Station or Car Sale)
  void setCategory(String category) {
    _currentCategory = category;
    notifyListeners();
  }

  /// Mark that employee has closed meter readings
  void markMeterReadingsClosed() {
    _hasClosedMeterReadings = true;
    notifyListeners();
  }

  /// Mark that employee has opened meter readings
  void markMeterReadingsOpened() {
    _hasOpenedMeterReadings = true;
    notifyListeners();
  }

  /// Check if user has specific permission
  bool hasPermission(String permissionKey) {
    if (isSuperAdmin) return true;

    if (_currentEmployee?.permissions == null ||
        _currentEmployee!.permissions!.isEmpty) {
      return false;
    }

    try {
      final permissionsMap = json.decode(_currentEmployee!.permissions!);
      return permissionsMap[permissionKey] == true;
    } catch (e) {
      print('❌ Error parsing permissions: $e');
      return false;
    }
  }

  /// Logout
  Future<void> logout() async {
    _currentEmployee = null;
    _currentCategory = null;
    _hasOpenedMeterReadings = false;
    _hasClosedMeterReadings = false;
    notifyListeners();
  }

  /// Request password reset
  Future<AuthResult> requestPasswordReset(String username) async {
    try {
      final supabase = Supabase.instance.client;

      final response = await supabase.functions.invoke(
        'reset-password',
        body: {'username': username},
      );

      final data = response.data;
      if (data != null && data['success'] == true) {
        return AuthResult(
          success: true,
          message: data['message'] ?? 'Password reset email sent.',
        );
      } else {
        return AuthResult(
          success: false,
          message: data?['message'] ?? 'Failed to reset password.',
        );
      }
    } catch (e) {
      if (e is FunctionException) {
        final details = e.details;
        if (details is Map && details['message'] != null) {
          return AuthResult(success: false, message: details['message']);
        }
      }
      return AuthResult(success: false, message: 'Error: ${e.toString()}');
    }
  }

  /// Create new employee (Admin/Super Admin only)
  Future<AuthResult> createEmployee({
    required String firstName,
    String? middleName,
    required String surname,
    required String phone,
    required String email,
    required String username,
    required String password,
    required String role,
    String? locationId,
    Map<String, bool>? permissions,
  }) async {
    try {
      final employeeId = 'emp_${DateTime.now().millisecondsSinceEpoch}';
      final hashedPassword = _hashPassword(password);

      final newEmployee = Employee(
        id: employeeId,
        locationId: locationId,
        role: role,
        firstName: firstName,
        middleName: middleName,
        surname: surname,
        phone: phone,
        email: email,
        username: username,
        passwordHash: hashedPassword,
        permissions: permissions != null ? json.encode(permissions) : null,
        isActive: true,
        createdAt: DateTime.now(),
      );

      await _authRepository.createEmployee(newEmployee);

      return AuthResult(
        success: true,
        message: 'Employee created successfully',
      );
    } on PostgrestException catch (e) {
      String message = 'Failed to create employee';

      if (e.code == '23505') {
        if (e.message.contains('username') ||
            e.details.toString().contains('username')) {
          message = 'Username is already taken. Please choose another one.';
        } else if (e.message.contains('email') ||
            e.details.toString().contains('email')) {
          message = 'Email is already registered. Please use another email.';
        } else {
          message = 'This record already exists (duplicate username or email).';
        }
      } else {
        message = 'Database error: ${e.message}';
      }

      print('Supabase error: ${e.code} - ${e.message}');
      return AuthResult(success: false, message: message);
    } catch (e) {
      print('Create employee error: $e');
      return AuthResult(
        success: false,
        message: 'Failed to create employee: ${e.toString()}',
      );
    }
  }

  /// Reset password for an employee (Super Admin/Admin only)
  Future<AuthResult> adminResetPassword({
    required String employeeId,
    required String newPassword,
  }) async {
    try {
      final hashedPassword = _hashPassword(newPassword);
      await _authRepository.updatePassword(employeeId, hashedPassword);
      return AuthResult(success: true, message: 'Password reset successfully');
    } catch (e) {
      print('Admin reset password error: $e');
      return AuthResult(
        success: false,
        message: 'Failed to reset password: ${e.toString()}',
      );
    }
  }

  /// Change password for current employee
  Future<AuthResult> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      if (_currentEmployee == null || _currentEmployee!.id == 'super_admin') {
        return AuthResult(success: false, message: 'Invalid operation');
      }

      final hashedCurrent = _hashPassword(currentPassword);
      if (_currentEmployee!.passwordHash != hashedCurrent) {
        return AuthResult(
          success: false,
          message: 'Current password is incorrect',
        );
      }

      final hashedNew = _hashPassword(newPassword);
      await _authRepository.updatePassword(_currentEmployee!.id, hashedNew);

      // Update local state
      _currentEmployee = Employee(
        id: _currentEmployee!.id,
        locationId: _currentEmployee!.locationId,
        role: _currentEmployee!.role,
        firstName: _currentEmployee!.firstName,
        middleName: _currentEmployee!.middleName,
        surname: _currentEmployee!.surname,
        phone: _currentEmployee!.phone,
        email: _currentEmployee!.email,
        username: _currentEmployee!.username,
        passwordHash: hashedNew,
        permissions: _currentEmployee!.permissions,
        isActive: _currentEmployee!.isActive,
        createdAt: _currentEmployee!.createdAt,
      );

      notifyListeners();
      return AuthResult(
        success: true,
        message: 'Password changed successfully',
      );
    } catch (e) {
      return AuthResult(
        success: false,
        message: 'Failed to change password: ${e.toString()}',
      );
    }
  }

  /// Sync existing employees to Supabase Auth
  Future<AuthResult> syncEmployeesToAuth() async {
    try {
      print('🔄 Syncing employees to Supabase Auth...');

      // 1. Create a Supabase client with SERVICE ROLE KEY to manage users
      final adminClient = SupabaseClient(
        SupabaseConfig.supabaseUrl,
        SupabaseConfig.supabaseSecretKey,
      );

      // 2. Fetch all employees from database
      final employeesResponse = await adminClient.from('employees').select();
      final employees = (employeesResponse as List)
          .map((e) => Employee.fromJson(e))
          .toList();

      int successCount = 0;
      int failCount = 0;

      for (final employee in employees) {
        if (employee.email.isEmpty) continue;

        try {
          // Check if user already exists (by trying to create)
          // Admin API to create user
          final attrs = AdminUserAttributes(
            email: employee.email,
            emailConfirm: true,
            userMetadata: {
              'role': employee.role,
              'username': employee.username,
              'employee_id': employee.id,
              'full_name': '${employee.firstName} ${employee.surname}',
            },
            password: 'Change@123', // Default password
          );

          await adminClient.auth.admin.createUser(attrs);
          print('✅ Created auth user for ${employee.username}');
          successCount++;
        } on AuthException catch (e) {
          // User likely already exists
          if (e.message.contains('already has been registered') ||
              e.message.contains('already registered') ||
              e.statusCode == '422') {
            print('ℹ️ User ${employee.username} already exists');
          } else {
            print('❌ Failed to create user ${employee.username}: ${e.message}');
            failCount++;
          }
        } catch (e) {
          print('❌ Error processing ${employee.username}: $e');
          failCount++;
        }
      }

      return AuthResult(
        success: true,
        message:
            'Sync complete. Created: $successCount, Failed/Exists: $failCount',
      );
    } catch (e) {
      print('Sync error: $e');
      return AuthResult(
        success: false,
        message: 'Sync failed: ${e.toString()}',
      );
    }
  }
}

class AuthResult {
  final bool success;
  final String message;

  AuthResult({required this.success, required this.message});
}
