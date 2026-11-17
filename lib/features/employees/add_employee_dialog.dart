import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/validation_utils.dart';
import '../../data/models/location.dart';
import '../../data/repositories/location_repository.dart';
import '../../services/auth_service.dart';
import '../../core/utils/toast_utils.dart';

class AddEmployeeDialog extends StatefulWidget {
  final VoidCallback onEmployeeAdded;

  const AddEmployeeDialog({super.key, required this.onEmployeeAdded});

  @override
  State<AddEmployeeDialog> createState() => _AddEmployeeDialogState();
}

class _AddEmployeeDialogState extends State<AddEmployeeDialog> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _middleNameController = TextEditingController();
  final _surnameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  String _selectedRole = AppConstants.roleEmployee;
  Location? _selectedLocation;
  List<Location> _selectedLocations = []; // For admins
  List<Location> _locations = [];
  bool _isSaving = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
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
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadLocations() async {
    final locationRepo = Provider.of<LocationRepository>(
      context,
      listen: false,
    );
    final locations = await locationRepo.getAllLocations();

    setState(() {
      _locations = locations;
      if (locations.isNotEmpty) {
        _selectedLocation = locations.first;
      }
    });
  }

  Future<void> _saveEmployee() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final authService = Provider.of<AuthService>(context, listen: false);
    final isCreatingAdmin = _selectedRole == AppConstants.roleAdmin;
    final requiredPermission = isCreatingAdmin
        ? 'canManageAdmins'
        : 'canManageEmployees';

    if (!authService.hasPermission(requiredPermission)) {
      ToastUtils.showError(
        'You do not have permission to create ${isCreatingAdmin ? "admins" : "employees"}',
      );
      setState(() => _isSaving = false);
      return;
    }

    if (_selectedRole == AppConstants.roleAdmin) {
      if (_selectedLocations.isEmpty) {
        ToastUtils.showError('Admin must be assigned to at least one location');
        return;
      }
    } else {
      if (_selectedLocation == null) {
        ToastUtils.showError('Please select a location');
        return;
      }
    }

    setState(() => _isSaving = true);

    try {
      String locationIdValue;
      if (_selectedRole == AppConstants.roleAdmin &&
          _selectedLocations.isNotEmpty) {
        final locationIds = _selectedLocations.map((loc) => loc.id).toList();
        locationIdValue = jsonEncode(locationIds);
      } else {
        locationIdValue = _selectedLocation!.id;
      }

      // Define permissions based on role
      Map<String, bool>? permissions;
      if (_selectedRole == AppConstants.roleAdmin) {
        // Create an empty, but non-null, permissions map for new Admins.
        // The Super Admin will grant specific permissions later on the permissions page.
        permissions = {};
      }
      // For regular employees, permissions remain null as their access is determined by their role.

      final result = await authService.createEmployee(
        firstName: _firstNameController.text.trim(),
        middleName: _middleNameController.text.trim().isEmpty
            ? null
            : _middleNameController.text.trim(),
        surname: _surnameController.text.trim(),
        phone: _phoneController.text.trim(),
        email: _emailController.text.trim(),
        username: _usernameController.text.trim(),
        password: _passwordController.text,
        role: _selectedRole,
        locationId: locationIdValue,
        permissions: permissions, // Pass the new permissions map
      );

      if (mounted) {
        if (result.success) {
          ToastUtils.showSuccess(result.message);
          widget.onEmployeeAdded();
          Navigator.of(context).pop();
        } else {
          ToastUtils.showError(result.message);
        }
      }
    } catch (e) {
      if (mounted) {
        ToastUtils.showError('Failed to create employee: ${e.toString()}');
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenHeight < 600;

    final dialogWidth = screenWidth > 600 ? 600.0 : screenWidth * 0.9;
    final maxDialogHeight = screenHeight * 0.9;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Container(
        width: dialogWidth,
        constraints: BoxConstraints(
          maxHeight: maxDialogHeight,
          maxWidth: dialogWidth,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
              decoration: const BoxDecoration(
                color: AppTheme.primaryOrange,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(4),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.person_add,
                    color: AppTheme.primaryWhite,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Add Employee',
                    style: TextStyle(
                      fontSize: isSmallScreen ? 16 : 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryWhite,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(
                      Icons.close,
                      color: AppTheme.primaryWhite,
                      size: 20,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(isSmallScreen ? 16 : 24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DropdownButtonFormField<String>(
                        value: _selectedRole,
                        decoration: const InputDecoration(
                          labelText: 'Role',
                          prefixIcon: Icon(Icons.admin_panel_settings),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 16,
                          ),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: AppConstants.roleAdmin,
                            child: Text('Admin'),
                          ),
                          DropdownMenuItem(
                            value: AppConstants.roleEmployee,
                            child: Text('Employee'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              _selectedRole = value;
                              if (value == AppConstants.roleAdmin) {
                                _selectedLocation = null;
                                _selectedLocations.clear();
                              } else {
                                _selectedLocations.clear();
                                if (_locations.isNotEmpty) {
                                  _selectedLocation = _locations.first;
                                }
                              }
                            });
                          }
                        },
                      ),
                      SizedBox(height: isSmallScreen ? 12 : 16),

                      if (_selectedRole == AppConstants.roleAdmin) ...[
                        Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: AppTheme.mediumGray),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: const [
                                  Icon(
                                    Icons.location_on,
                                    size: 20,
                                    color: AppTheme.darkGray,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'Assigned Locations (Select multiple)',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.darkGray,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              ..._locations.map((location) {
                                final displayText =
                                    location.address != null &&
                                        location.address!.isNotEmpty
                                    ? '${location.name} - ${location.address}'
                                    : location.name;
                                final isSelected = _selectedLocations.any(
                                  (l) => l.id == location.id,
                                );

                                return CheckboxListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(
                                    displayText,
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                  value: isSelected,
                                  onChanged: (checked) {
                                    setState(() {
                                      if (checked == true) {
                                        _selectedLocations.add(location);
                                      } else {
                                        _selectedLocations.removeWhere(
                                          (l) => l.id == location.id,
                                        );
                                      }
                                    });
                                  },
                                  controlAffinity:
                                      ListTileControlAffinity.leading,
                                );
                              }).toList(),
                            ],
                          ),
                        ),
                      ] else ...[
                        DropdownButtonFormField<Location>(
                          value: _selectedLocation,
                          decoration: const InputDecoration(
                            labelText: 'Location/Address',
                            prefixIcon: Icon(Icons.location_on),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 16,
                            ),
                          ),
                          isExpanded: true,
                          items: _locations.map((location) {
                            final displayText =
                                location.address != null &&
                                    location.address!.isNotEmpty
                                ? location.address!
                                : location.name;
                            return DropdownMenuItem(
                              value: location,
                              child: Text(
                                displayText,
                                overflow: TextOverflow.ellipsis,
                              ),
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

                        if (_selectedLocation != null)
                          Padding(
                            padding: EdgeInsets.only(
                              top: isSmallScreen ? 8 : 12,
                            ),
                            child: TextFormField(
                              key: ValueKey(_selectedLocation!.id),
                              initialValue: _selectedLocation!.name,
                              decoration: const InputDecoration(
                                labelText: 'Shop Name',
                                prefixIcon: Icon(Icons.store),
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 16,
                                ),
                                filled: true,
                                fillColor: Color(0xFFF5F5F5),
                              ),
                              readOnly: true,
                              enabled: false,
                              style: const TextStyle(color: Colors.black87),
                            ),
                          ),
                      ],
                      SizedBox(height: isSmallScreen ? 12 : 16),

                      TextFormField(
                        controller: _firstNameController,
                        decoration: const InputDecoration(
                          labelText: 'First Name',
                          prefixIcon: Icon(Icons.person),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 16,
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'First name is required';
                          }
                          return null;
                        },
                      ),
                      SizedBox(height: isSmallScreen ? 12 : 16),

                      TextFormField(
                        controller: _middleNameController,
                        decoration: const InputDecoration(
                          labelText: 'Middle Name (Optional)',
                          prefixIcon: Icon(Icons.person_outline),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 16,
                          ),
                        ),
                      ),
                      SizedBox(height: isSmallScreen ? 12 : 16),

                      TextFormField(
                        controller: _surnameController,
                        decoration: const InputDecoration(
                          labelText: 'Surname',
                          prefixIcon: Icon(Icons.person),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 16,
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Surname is required';
                          }
                          return null;
                        },
                      ),
                      SizedBox(height: isSmallScreen ? 12 : 16),

                      TextFormField(
                        controller: _phoneController,
                        decoration: const InputDecoration(
                          labelText: 'Phone Number',
                          prefixIcon: Icon(Icons.phone),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 16,
                          ),
                        ),
                        keyboardType: TextInputType.phone,
                        validator: ValidationUtils.validatePhone,
                      ),
                      SizedBox(height: isSmallScreen ? 12 : 16),

                      TextFormField(
                        controller: _emailController,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          prefixIcon: Icon(Icons.email),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 16,
                          ),
                        ),
                        keyboardType: TextInputType.emailAddress,
                        validator: ValidationUtils.validateEmail,
                      ),
                      SizedBox(height: isSmallScreen ? 12 : 16),

                      TextFormField(
                        controller: _usernameController,
                        decoration: const InputDecoration(
                          labelText: 'Username',
                          prefixIcon: Icon(Icons.account_circle),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 16,
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Username is required';
                          }
                          return null;
                        },
                      ),
                      SizedBox(height: isSmallScreen ? 12 : 16),

                      TextFormField(
                        controller: _passwordController,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 16,
                          ),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              color: AppTheme.darkGray,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscurePassword = !_obscurePassword;
                              });
                            },
                          ),
                        ),
                        obscureText: _obscurePassword,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Password is required';
                          }
                          if (value.length < 6) {
                            return 'Password must be at least 6 characters';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),

            Container(
              padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: AppTheme.mediumGray)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: ElevatedButton.icon(
                      onPressed: _isSaving ? null : _saveEmployee,
                      style: ElevatedButton.styleFrom(
                        padding: EdgeInsets.symmetric(
                          horizontal: isSmallScreen ? 12 : 16,
                          vertical: isSmallScreen ? 10 : 12,
                        ),
                      ),
                      icon: _isSaving
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  AppTheme.primaryWhite,
                                ),
                              ),
                            )
                          : const Icon(Icons.save, size: 18),
                      label: Text(
                        'Create Employee',
                        style: TextStyle(fontSize: isSmallScreen ? 13 : 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
