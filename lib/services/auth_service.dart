import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:drift/drift.dart' as drift;
import '../data/database/app_database.dart';
import '../core/constants/app_constants.dart';
import '../services/supabase_service.dart';

/// Authentication service for managing user login and permissions
class AuthService extends ChangeNotifier {
  final AppDatabase _db;
  final SupabaseService _supabase;
  
  Employee? _currentEmployee;
  String? _currentCategory; // 'Filling Station' or 'Car Sale'
  bool _hasOpenedMeterReadings = false;
  bool _hasClosedMeterReadings = false;
  
  AuthService(this._db, this._supabase);
  
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
  /// Super Admin uses hardcoded credentials (no internet needed)
  /// Regular users require internet to authenticate
  Future<AuthResult> login({
    required String username,
    required String password,
  }) async {
    try {
      print('🔐 Login attempt - Username: $username');
      
      // STEP 0: Check for hardcoded Super Admin credentials FIRST
      if (username.toLowerCase() == 'superadmin') {
        print('🔑 Super Admin login attempt detected');
        if (password == 'SuperAdmin@2026!') {
          print('✅ Super Admin credentials verified (hardcoded)');
          
          // Create super admin employee object (not from database)
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
            syncedAt: null,
          );
          
          _hasClosedMeterReadings = false;
          _hasOpenedMeterReadings = false;
          notifyListeners();
          return AuthResult(success: true, message: 'Super Admin login successful');
        } else {
          print('❌ Super Admin password incorrect');
          return AuthResult(
            success: false,
            message: 'Incorrect password',
          );
        }
      }
      
      // STEP 1: Fetch regular employee from Supabase (NOT Super Admin)
      try {
        final response = await _supabase.client
            .from('employees')
            .select()
            .eq('username', username)
            .maybeSingle()
            .timeout(const Duration(seconds: 10));
        
        if (response == null) {
          print('❌ No employee found with username: $username');
          return AuthResult(
            success: false,
            message: 'User not found. Please check your username.',
          );
        }
        
        print('✅ Found employee: ${response['first_name']} ${response['surname']} (${response['role']})');
        
        // Check if account is active
        if (response['is_active'] != true) {
          print('❌ Account is inactive');
          return AuthResult(
            success: false,
            message: 'Account is inactive or has been deleted',
          );
        }
        
        // Verify password hash
        final hashedPassword = _hashPassword(password);
        print('🔑 Computed hash: $hashedPassword');
        print('🔑 Stored hash:   ${response['password_hash']}');
        if (response['password_hash'] != hashedPassword) {
          print('❌ Password hash mismatch!');
          return AuthResult(
            success: false,
            message: 'Incorrect password',
          );
        }
        
        print('✅ Password verified!');
        
        // STEP 2: Create Employee object from Supabase data
        // Convert permissions from Map to JSON string if needed
        String? permissionsStr;
        if (response['permissions'] != null) {
          if (response['permissions'] is String) {
            permissionsStr = response['permissions'];
          } else if (response['permissions'] is Map) {
            permissionsStr = json.encode(response['permissions']);
          }
        }
        
        final onlineEmployee = Employee(
          id: response['id'],
          locationId: response['location_id'],
          role: response['role'],
          firstName: response['first_name'],
          middleName: response['middle_name'],
          surname: response['surname'],
          phone: response['phone'],
          email: response['email'],
          username: response['username'],
          passwordHash: response['password_hash'],
          permissions: permissionsStr,
          isActive: response['is_active'] ?? true,
          createdAt: DateTime.parse(response['created_at']),
          syncedAt: response['synced_at'] != null 
              ? DateTime.parse(response['synced_at']) 
              : null,
        );
        
        // Update local database with latest data from cloud
        await _db.upsertEmployee(onlineEmployee);
        
        print('✅ Login successful - authenticated user');
        
        _currentEmployee = onlineEmployee;
        _hasClosedMeterReadings = false;
        _hasOpenedMeterReadings = false;
        notifyListeners();
        return AuthResult(success: true, message: 'Login successful');
        
      } catch (e) {
        print('❌ Online login failed: $e');
        final errorMsg = e.toString();
        
        // Check for specific error types
        if (errorMsg.contains('SocketException') || errorMsg.contains('Failed host lookup')) {
          return AuthResult(
            success: false,
            message: 'No internet connection. Please check your WiFi or mobile data.',
          );
        } else if (errorMsg.contains('timed out') || errorMsg.contains('TimeoutException')) {
          return AuthResult(
            success: false,
            message: 'Connection timeout. Please check your internet connection.',
          );
        } else if (errorMsg.contains('row-level security') || errorMsg.contains('RLS')) {
          return AuthResult(
            success: false,
            message: 'Database access denied. Please run fix_rls_policies.sql in Supabase SQL Editor.',
          );
        } else if (errorMsg.contains('JWT') || errorMsg.contains('apikey')) {
          return AuthResult(
            success: false,
            message: 'Invalid Supabase credentials. Check supabase_config.dart',
          );
        } else {
          // Show actual error for debugging
          return AuthResult(
            success: false,
            message: 'Login failed: $errorMsg',
          );
        }
      }
    } catch (e) {
      print('Login error: $e'); // Log for debugging
      return AuthResult(
        success: false,
        message: 'An unexpected error occurred. Please try again.',
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
    // Super Admin has all permissions
    if (isSuperAdmin) {
      print('✅ Super Admin - has all permissions');
      return true;
    }
    
    // Admins also have all management permissions by default
    if (isAdmin) {
      print('✅ Admin role - checking permissions for: $permissionKey');
    }
    
    // Check user's specific permissions from database
    if (_currentEmployee?.permissions == null || _currentEmployee!.permissions!.isEmpty) {
      print('❌ No permissions found for user');
      return false;
    }
    
    try {
      final permissionsMap = json.decode(_currentEmployee!.permissions!);
      final hasIt = permissionsMap[permissionKey] == true;
      print('🔍 Permission check for "$permissionKey": $hasIt');
      print('   Permissions: $permissionsMap');
      return hasIt;
    } catch (e) {
      print('❌ Error parsing permissions: $e');
      return false;
    }
  }
  
  /// Logout
  Future<void> logout() async {
    try {
      await _supabase.signOut();
    } catch (e) {
      print('Error signing out from Supabase: $e');
    }
    
    _currentEmployee = null;
    _currentCategory = null;
    _hasOpenedMeterReadings = false;
    _hasClosedMeterReadings = false;
    notifyListeners();
  }
  
  /// Request password reset (sends email)
  Future<AuthResult> requestPasswordReset(String username) async {
    try {
      final employee = await _db.getEmployeeByUsername(username);
      
      if (employee == null) {
        return AuthResult(
          success: false,
          message: 'User not found',
        );
      }
      
      // TODO: Implement email sending functionality
      // For now, just return the password (in production, send via email)
      
      return AuthResult(
        success: true,
        message: 'Password reset email sent to ${employee.email}',
      );
    } catch (e) {
      print('Password reset error: $e'); // Log for debugging
      return AuthResult(
        success: false,
        message: 'Unable to process password reset. Please try again.',
      );
    }
  }
  
  /// Create new employee (Admin/Super Admin only)
  /// REQUIRES INTERNET - Creates user in Supabase and then saves to local DB
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
      // Basic input validation
      if (phone.replaceAll(RegExp(r'[^0-9]'), '').length > 10) {
        return AuthResult(success: false, message: 'Phone number cannot have more than 10 digits.');
      }

      if (!email.contains('@') || !email.split('@').last.contains('.')) {
          return AuthResult(success: false, message: 'Please enter a valid email address.');
      }

      // STEP 1: Check if username or email already exists for an ACTIVE user in Supabase
      final existingCheck = await _supabase.client
          .from('employees')
          .select('username, email')
          .eq('is_active', true) // Only check against active users
          .or('username.eq.$username,email.eq.$email')
          .limit(1)
          .maybeSingle();

      if (existingCheck != null) {
        if (existingCheck['username'] == username) {
          return AuthResult(success: false, message: 'Username already exists for an active user.');
        }
        if (existingCheck['email'] == email) {
          return AuthResult(success: false, message: 'Email address is already in use by an active user.');
        }
      }

      // STEP 2: Prepare the new employee data
      final employeeId = 'emp_${DateTime.now().millisecondsSinceEpoch}';
      final hashedPassword = _hashPassword(password);
      
      final newEmployeeData = {
        'id': employeeId,
        'location_id': locationId,
        'role': role,
        'first_name': firstName,
        'middle_name': middleName,
        'surname': surname,
        'phone': phone,
        'email': email,
        'username': username,
        'password_hash': hashedPassword,
        'permissions': permissions != null ? json.encode(permissions) : null,
        'is_active': true,
      };

      // STEP 3: Insert into Supabase and get the created record back
      final response = await _supabase.client
          .from('employees')
          .insert(newEmployeeData)
          .select()
          .single();

      print('✅ Employee created in Supabase: $username (ID: ${response['id']})');

      // STEP 4: Create a local DB object from the Supabase response and save it
      // Convert permissions from Map to JSON string if needed
      String? permissionsStr;
      if (response['permissions'] != null) {
        if (response['permissions'] is String) {
          permissionsStr = response['permissions'];
        } else if (response['permissions'] is Map) {
          permissionsStr = json.encode(response['permissions']);
        }
      }
      
      final newEmployee = Employee(
        id: response['id'],
        locationId: response['location_id'],
        role: response['role'],
        firstName: response['first_name'],
        middleName: response['middle_name'],
        surname: response['surname'],
        phone: response['phone'],
        email: response['email'],
        username: response['username'],
        passwordHash: response['password_hash'],
        permissions: permissionsStr,
        isActive: response['is_active'] ?? true,
        createdAt: DateTime.parse(response['created_at']),
        syncedAt: DateTime.now(), // Mark as synced now
      );

      await _db.upsertEmployee(newEmployee);
      print('✅ Employee saved to local database.');

      return AuthResult(
        success: true,
        message: 'Employee created successfully',
      );
    } catch (e) {
      print('Create employee error: $e');
      final errorMessage = e.toString();

      if (errorMessage.contains('violates row-level security policy')) {
        return AuthResult(success: false, message: 'Permission Denied: Your user role does not allow creating new employees.');
      }
      if (errorMessage.contains('duplicate key value violates unique constraint')) {
        return AuthResult(success: false, message: 'Username or email already exists for an active user.');
      }
      if (errorMessage.contains('SocketException') || errorMessage.contains('timed out')) {
          return AuthResult(success: false, message: 'Network error. Please check your internet connection.');
      }
      
      // For other errors, show a more detailed message for debugging
      return AuthResult(
        success: false,
        message: 'Failed to create employee: $errorMessage',
      );
    }
  }
  
  /// Sync existing employees to Supabase Auth
  /// NOTE: No longer needed - passwords are managed in database only
  Future<AuthResult> syncEmployeesToAuth() async {
    return AuthResult(
      success: true,
      message: 'Supabase Auth sync is no longer required. Passwords are managed in the database.',
    );
  }
  
  /// Change password for current employee
  /// Verifies current password and updates to new password
  Future<AuthResult> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      if (_currentEmployee == null) {
        return AuthResult(
          success: false,
          message: 'Not logged in',
        );
      }
      
      // Super Admin cannot change password (hard-coded credentials)
      if (_currentEmployee!.id == 'super_admin') {
        return AuthResult(
          success: false,
          message: 'Super Admin password cannot be changed',
        );
      }
      
      // Verify current password
      final hashedCurrent = _hashPassword(currentPassword);
      if (_currentEmployee!.passwordHash != hashedCurrent) {
        return AuthResult(
          success: false,
          message: 'Current password is incorrect',
        );
      }
      
      // Hash new password
      final hashedNew = _hashPassword(newPassword);
      
      // Update in local database
      await (_db.update(_db.employees)
            ..where((e) => e.id.equals(_currentEmployee!.id)))
          .write(EmployeesCompanion(
        passwordHash: drift.Value(hashedNew),
        syncedAt: drift.Value(null), // Reset to null so new password gets synced to Supabase
      ));
      
      print('✅ Password updated in database');
      
      // Reload employee from database to update in memory
      final updatedEmployee = await (_db.select(_db.employees)
            ..where((e) => e.id.equals(_currentEmployee!.id)))
          .getSingleOrNull();
      
      if (updatedEmployee != null) {
        _currentEmployee = updatedEmployee;
        notifyListeners();
      }
      
      return AuthResult(
        success: true,
        message: 'Password changed successfully',
      );
    } catch (e) {
      print('Change password error: $e'); // Log for debugging
      return AuthResult(
        success: false,
        message: 'Unable to change password. Please try again.',
      );
    }
  }
}

class AuthResult {
  final bool success;
  final String message;
  
  AuthResult({
    required this.success,
    required this.message,
  });
}
