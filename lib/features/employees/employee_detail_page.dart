import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:drift/drift.dart' as drift;
import '../../core/theme/app_theme.dart';
import '../../core/constants/app_constants.dart';
import '../../data/database/app_database.dart';
import '../../services/auth_service.dart';
import '../../services/connectivity_service.dart';
import '../../services/supabase_service.dart';
import '../../core/utils/toast_utils.dart';
import 'permissions_page.dart';

class EmployeeDetailPage extends StatefulWidget {
  final Employee employee;
  
  const EmployeeDetailPage({
    super.key,
    required this.employee,
  });

  @override
  State<EmployeeDetailPage> createState() => _EmployeeDetailPageState();
}

class _EmployeeDetailPageState extends State<EmployeeDetailPage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _firstNameController;
  late TextEditingController _middleNameController;
  late TextEditingController _surnameController;
  late TextEditingController _phoneController;
  late TextEditingController _emailController;
  late TextEditingController _usernameController;
  
  bool _isEditing = false;
  bool _isSaving = false;
  List<Location> _locations = [];
  String? _assignedLocationNames;
  
  // For editing locations
  Location? _selectedLocation; // For employees
  List<Location> _selectedLocations = []; // For admins

  @override
  void initState() {
    super.initState();
    _firstNameController = TextEditingController(text: widget.employee.firstName);
    _middleNameController = TextEditingController(text: widget.employee.middleName ?? '');
    _surnameController = TextEditingController(text: widget.employee.surname);
    _phoneController = TextEditingController(text: widget.employee.phone);
    _emailController = TextEditingController(text: widget.employee.email);
    _usernameController = TextEditingController(text: widget.employee.username);
    _loadLocations();
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _middleNameController.dispose();
    _surnameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _loadLocations() async {
    final db = Provider.of<AppDatabase>(context, listen: false);
    final locations = await db.getAllLocations();
    
    setState(() {
      _locations = locations;
      _assignedLocationNames = _getAssignedLocationNames();
      _initializeLocationSelection();
    });
  }

  void _initializeLocationSelection() {
    if (widget.employee.locationId == null) return;
    
    try {
      // Try to parse as JSON array (for admins with multiple locations)
      final locationIds = jsonDecode(widget.employee.locationId!) as List;
      _selectedLocations = _locations
          .where((loc) => locationIds.contains(loc.id))
          .toList();
    } catch (e) {
      // Single location ID (for employees)
      _selectedLocation = _locations.firstWhere(
        (loc) => loc.id == widget.employee.locationId,
        orElse: () => _locations.first,
      );
    }
  }

  String _getAssignedLocationNames() {
    if (widget.employee.locationId == null) return 'No location assigned';
    
    try {
      // Try to parse as JSON array (for admins with multiple locations)
      final locationIds = jsonDecode(widget.employee.locationId!) as List;
      final assignedLocations = _locations
          .where((loc) => locationIds.contains(loc.id))
          .map(_formatLocationDisplay)
          .toList();
      return assignedLocations.isEmpty ? 'No location assigned' : assignedLocations.join(', ');
    } catch (e) {
      // Single location ID (for employees)
      final location = _locations.firstWhere(
        (loc) => loc.id == widget.employee.locationId,
        orElse: () => Location(
          id: '',
          name: 'Unknown Location',
          agoPumps: 0,
          pmsPumps: 0,
          createdAt: DateTime.now(),
        ),
      );
      return _formatLocationDisplay(location);
    }
  }

  String _formatLocationDisplay(Location location) {
    final address = location.address?.trim();
    if (address == null || address.isEmpty) {
      return location.name;
    }
    return address;
  }

  Map<String, dynamic> _getPermissions() {
    if (widget.employee.permissions == null || widget.employee.permissions!.isEmpty) {
      return {};
    }
    try {
      return jsonDecode(widget.employee.permissions!) as Map<String, dynamic>;
    } catch (e) {
      return {};
    }
  }

  Future<void> _saveChanges() async {
    // Check permission based on employee role (allow self-editing)
    final authService = Provider.of<AuthService>(context, listen: false);
    final connectivityService = Provider.of<ConnectivityService>(context, listen: false);
    final isAdmin = widget.employee.role == AppConstants.roleAdmin;
    final isSelf = authService.currentEmployee?.id == widget.employee.id;
    final requiredPermission = isAdmin ? 'canManageAdmins' : 'canManageEmployees';
    
    // Allow self-editing or check permission
    if (!isSelf && !authService.hasPermission(requiredPermission)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('You do not have permission to edit ${isAdmin ? "admins" : "employees"}'),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }

    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (!connectivityService.hasConnection) {
      ToastUtils.showError('No internet connection. Employee update failed.');
      return;
    }

    // Validate location selection
    if (widget.employee.role == AppConstants.roleAdmin) {
      if (_selectedLocations.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Admin must be assigned to at least one location'),
            backgroundColor: AppTheme.error,
          ),
        );
        return;
      }
    } else {
      if (_selectedLocation == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select a location'),
            backgroundColor: AppTheme.error,
          ),
        );
        return;
      }
    }

    setState(() => _isSaving = true);

    try {
      // Prepare location ID value
      String locationIdValue;
      if (widget.employee.role == AppConstants.roleAdmin && _selectedLocations.isNotEmpty) {
        final locationIds = _selectedLocations.map((loc) => loc.id).toList();
        locationIdValue = jsonEncode(locationIds);
      } else {
        locationIdValue = _selectedLocation!.id;
      }

      // Update Supabase first so changes are enforced immediately
      final supabase = SupabaseService.instance;
      await supabase.client
          .from('employees')
          .update({
            'first_name': _firstNameController.text.trim(),
            'middle_name': _middleNameController.text.trim().isEmpty
                ? null
                : _middleNameController.text.trim(),
            'surname': _surnameController.text.trim(),
            'phone': _phoneController.text.trim(),
            'email': _emailController.text.trim(),
            'username': _usernameController.text.trim(),
            'location_id': locationIdValue,
          })
          .eq('id', widget.employee.id)
          .timeout(const Duration(seconds: 10));

      final db = Provider.of<AppDatabase>(context, listen: false);
      
      // Use updateEmployeePartial (write) instead of updateEmployee (replace)
      // to only update the specified fields without requiring ALL non-nullable columns
      final updated = EmployeesCompanion(
        firstName: drift.Value(_firstNameController.text.trim()),
        middleName: drift.Value(_middleNameController.text.trim().isEmpty 
            ? null 
            : _middleNameController.text.trim()),
        surname: drift.Value(_surnameController.text.trim()),
        phone: drift.Value(_phoneController.text.trim()),
        email: drift.Value(_emailController.text.trim()),
        username: drift.Value(_usernameController.text.trim()),
        locationId: drift.Value(locationIdValue),
        syncedAt: drift.Value(DateTime.now()),
      );

      await db.updateEmployeePartial(widget.employee.id, updated);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Employee updated successfully'),
            backgroundColor: AppTheme.success,
          ),
        );
        setState(() => _isEditing = false);
        Navigator.pop(context, true); // Return true to indicate changes were made
      }
    } catch (e) {
      print('Update employee error: $e'); // Log for debugging
      if (mounted) {
        ToastUtils.showError('Unable to update employee. Please try again.');
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final permissions = _getPermissions();
    final authService = Provider.of<AuthService>(context, listen: false);
    final isAdmin = widget.employee.role == AppConstants.roleAdmin;
    final isSelf = authService.currentEmployee?.id == widget.employee.id;
    final requiredPermission = isAdmin ? 'canManageAdmins' : 'canManageEmployees';
    final canEdit = isSelf || authService.hasPermission(requiredPermission);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Employee Details'),
        backgroundColor: AppTheme.primaryOrange,
        actions: [
          if (!_isEditing && canEdit)
            IconButton(
              icon: const Icon(Icons.edit),
              tooltip: 'Edit',
              onPressed: () => setState(() => _isEditing = true),
            )
          else if (_isEditing)
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Cancel',
              onPressed: () {
                setState(() {
                  _isEditing = false;
                  // Reset form fields
                  _firstNameController.text = widget.employee.firstName;
                  _middleNameController.text = widget.employee.middleName ?? '';
                  _surnameController.text = widget.employee.surname;
                  _phoneController.text = widget.employee.phone;
                  _emailController.text = widget.employee.email;
                  _usernameController.text = widget.employee.username;
                  // Reset location selection
                  _initializeLocationSelection();
                });
              },
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Profile Header
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 40,
                        backgroundColor: widget.employee.role == AppConstants.roleAdmin
                            ? AppTheme.primaryOrange
                            : AppTheme.primaryBlack,
                        child: Text(
                          widget.employee.firstName[0].toUpperCase(),
                          style: const TextStyle(
                            color: AppTheme.primaryWhite,
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${widget.employee.firstName} ${widget.employee.surname}',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: widget.employee.role == AppConstants.roleAdmin
                                    ? AppTheme.primaryOrange
                                    : AppTheme.primaryBlack,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                widget.employee.role.toUpperCase(),
                                style: const TextStyle(
                                  color: AppTheme.primaryWhite,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Personal Information Section
              const Text(
                'Personal Information',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _firstNameController,
                        decoration: const InputDecoration(
                          labelText: 'First Name',
                          prefixIcon: Icon(Icons.person),
                        ),
                        enabled: _isEditing,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'First name is required';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _middleNameController,
                        decoration: const InputDecoration(
                          labelText: 'Middle Name (Optional)',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        enabled: _isEditing,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _surnameController,
                        decoration: const InputDecoration(
                          labelText: 'Surname',
                          prefixIcon: Icon(Icons.person),
                        ),
                        enabled: _isEditing,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Surname is required';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Contact Information
              const Text(
                'Contact Information',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _phoneController,
                        decoration: const InputDecoration(
                          labelText: 'Phone Number',
                          prefixIcon: Icon(Icons.phone),
                        ),
                        enabled: _isEditing,
                        keyboardType: TextInputType.phone,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Phone number is required';
                          }
                          final phoneDigits = value.replaceAll(RegExp(r'[^0-9]'), '');
                          if (phoneDigits.length != 10) {
                            return 'Phone number must be 10 digits';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _emailController,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          prefixIcon: Icon(Icons.email),
                        ),
                        enabled: _isEditing,
                        keyboardType: TextInputType.emailAddress,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Email is required';
                          }
                          // Use a regular expression for stricter email validation
                          final emailRegex = RegExp(r'^[a-zA-Z0-9.]+@[a-zA-Z0-9]+\.[a-zA-Z]+');
                          if (!emailRegex.hasMatch(value)) {
                            return 'Please enter a valid email address (e.g., user@domain.com)';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Account Information
              const Text(
                'Account Information',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _usernameController,
                        decoration: const InputDecoration(
                          labelText: 'Username',
                          prefixIcon: Icon(Icons.account_circle),
                        ),
                        enabled: _isEditing,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Username is required';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      
                      // Location Assignment - Editable
                      if (_isEditing) ...[
                        if (widget.employee.role == AppConstants.roleAdmin) ...[
                          // Admin: Multi-select locations
                          const Text(
                            'Assigned Locations (Select multiple)',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            decoration: BoxDecoration(
                              border: Border.all(color: AppTheme.mediumGray),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            padding: const EdgeInsets.all(8),
                            child: Column(
                              children: _locations.map((location) {
                                final isSelected = _selectedLocations.any((l) => l.id == location.id);
                                return CheckboxListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(location.name),
                                  subtitle: location.address != null 
                                      ? Text(location.address!, style: const TextStyle(fontSize: 12))
                                      : null,
                                  value: isSelected,
                                  onChanged: (checked) {
                                    setState(() {
                                      if (checked == true) {
                                        _selectedLocations.add(location);
                                      } else {
                                        _selectedLocations.removeWhere((l) => l.id == location.id);
                                      }
                                    });
                                  },
                                  controlAffinity: ListTileControlAffinity.leading,
                                );
                              }).toList(),
                            ),
                          ),
                        ] else ...[
                          // Employee: Single location dropdown
                          DropdownButtonFormField<Location>(
                            value: _selectedLocation,
                            decoration: const InputDecoration(
                              labelText: 'Assigned Location',
                              prefixIcon: Icon(Icons.location_on),
                            ),
                            items: _locations.map((location) {
                              return DropdownMenuItem(
                                value: location,
                                child: Text(_formatLocationDisplay(location)),
                              );
                            }).toList(),
                            onChanged: (value) {
                              setState(() => _selectedLocation = value);
                            },
                            validator: (value) {
                              if (value == null) {
                                return 'Please select a location';
                              }
                              return null;
                            },
                          ),
                        ],
                      ] else ...[
                        // View mode - just show location names
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.location_on),
                          title: const Text('Assigned Location(s)'),
                          subtitle: Text(_assignedLocationNames ?? 'Loading...'),
                        ),
                      ],
                      const SizedBox(height: 16),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.calendar_today),
                        title: const Text('Created At'),
                        subtitle: Text(
                          '${widget.employee.createdAt.day}/${widget.employee.createdAt.month}/${widget.employee.createdAt.year}',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Permissions Section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Permissions',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      // Check permission
                      final authService = Provider.of<AuthService>(context, listen: false);
                      
                      // Prevent self-editing of permissions (except super admin)
                      if (authService.currentEmployee?.id == widget.employee.id && !authService.isSuperAdmin) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('You cannot edit your own permissions. Please ask another admin.'),
                            backgroundColor: AppTheme.error,
                          ),
                        );
                        return;
                      }
                      
                      // Check for appropriate permission based on role
                      final isAdmin = widget.employee.role == AppConstants.roleAdmin;
                      final requiredPermission = isAdmin ? 'canManageAdmins' : 'canManageEmployees';
                      
                      if (!authService.hasPermission(requiredPermission)) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('You do not have permission to manage ${isAdmin ? "admin" : "employee"} permissions'),
                            backgroundColor: AppTheme.error,
                          ),
                        );
                        return;
                      }

                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => PermissionsPage(employee: widget.employee),
                        ),
                      );
                      if (result == true && mounted) {
                        // Reload employee data if permissions were updated
                        Navigator.pop(context, true);
                      }
                    },
                    icon: const Icon(Icons.edit, size: 18),
                    label: const Text('Manage'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: permissions.isEmpty
                      ? const Text(
                          'No permissions set. Click "Manage" to configure permissions.',
                          style: TextStyle(color: AppTheme.darkGray),
                        )
                      : Column(
                          children: [
                            _buildPermissionItem('Manage Locations', permissions['canManageLocations'] ?? false),
                            _buildPermissionItem('Manage Employees', permissions['canManageEmployees'] ?? false),
                            _buildPermissionItem('Manage Admins', permissions['canManageAdmins'] ?? false),
                            _buildPermissionItem('Manage Inventory', permissions['canManageInventory'] ?? false),
                            _buildPermissionItem('Process Sales', permissions['canProcessSales'] ?? false),
                            _buildPermissionItem('Void Sales', permissions['canVoidSales'] ?? false),
                            _buildPermissionItem('Manage Receiving', permissions['canManageReceiving'] ?? false),
                            _buildPermissionItem('Adjust Prices', permissions['canAdjustPrices'] ?? false),
                            _buildPermissionItem('View Reports', permissions['canViewReports'] ?? false),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 24),

              // Save Button (only shown when editing)
              if (_isEditing)
                ElevatedButton.icon(
                  onPressed: _isSaving ? null : _saveChanges,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  icon: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              AppTheme.primaryWhite,
                            ),
                          ),
                        )
                      : const Icon(Icons.save),
                  label: const Text('Save Changes'),
                ),
              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPermissionItem(String label, bool hasPermission) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            hasPermission ? Icons.check_circle : Icons.cancel,
            color: hasPermission ? AppTheme.success : AppTheme.darkGray,
            size: 20,
          ),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              color: hasPermission ? Colors.black87 : AppTheme.darkGray,
            ),
          ),
        ],
      ),
    );
  }
}
