import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/constants/app_constants.dart';
import '../../data/models/employee.dart';
import '../../data/repositories/employee_repository.dart';
import '../../services/auth_service.dart';
import '../../services/connectivity_service.dart';
import '../../core/utils/toast_utils.dart';

class PermissionsPage extends StatefulWidget {
  final Employee employee;

  const PermissionsPage({super.key, required this.employee});

  @override
  State<PermissionsPage> createState() => _PermissionsPageState();
}

class _PermissionsPageState extends State<PermissionsPage> {
  // Permission flags
  bool _canManageLocations = false;
  bool _canManageEmployees = false;
  bool _canManageAdmins = false;
  bool _canManageInventory = false;
  bool _canProcessSales = false;
  bool _canViewReports = false;
  bool _canManageReceiving = false;
  bool _canAdjustPrices = false;
  bool _canVoidSales = false;

  bool _isSaving = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authService = Provider.of<AuthService>(context, listen: false);
      final isSelf = authService.currentEmployee?.id == widget.employee.id;
      if (isSelf && !authService.isSuperAdmin) {
        ToastUtils.showError(
          'You cannot edit your own permissions. Please ask another admin.',
        );
        Navigator.pop(context, false);
      }
    });
    _loadPermissions();
  }

  Future<void> _loadPermissions() async {
    setState(() => _isLoading = true);

    try {
      final employeeRepo = Provider.of<EmployeeRepository>(
        context,
        listen: false,
      );
      final freshEmployee = await employeeRepo.getEmployee(widget.employee.id);

      if (freshEmployee != null &&
          freshEmployee.permissions != null &&
          freshEmployee.permissions!.isNotEmpty) {
        final permissions =
            jsonDecode(freshEmployee.permissions!) as Map<String, dynamic>;
        setState(() {
          _canManageLocations = permissions['canManageLocations'] ?? false;
          _canManageEmployees = permissions['canManageEmployees'] ?? false;
          _canManageAdmins = permissions['canManageAdmins'] ?? false;
          // Admins cannot perform operational tasks - always false
          _canManageInventory = widget.employee.role == AppConstants.roleAdmin
              ? false
              : (permissions['canManageInventory'] ?? false);
          _canProcessSales = widget.employee.role == AppConstants.roleAdmin
              ? false
              : (permissions['canProcessSales'] ?? false);
          _canViewReports = permissions['canViewReports'] ?? false;
          _canManageReceiving = widget.employee.role == AppConstants.roleAdmin
              ? false
              : (permissions['canManageReceiving'] ?? false);
          _canAdjustPrices = permissions['canAdjustPrices'] ?? false;
          _canVoidSales = permissions['canVoidSales'] ?? false;
        });
      }
    } catch (e) {
      debugPrint('Error loading permissions: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _savePermissions() async {
    setState(() => _isSaving = true);

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final connectivityService = Provider.of<ConnectivityService>(
        context,
        listen: false,
      );
      final isSelf = authService.currentEmployee?.id == widget.employee.id;
      if (isSelf && !authService.isSuperAdmin) {
        if (mounted) {
          ToastUtils.showError(
            'You cannot edit your own permissions. Please ask another admin.',
          );
        }
        return;
      }

      if (!connectivityService.hasConnection) {
        ToastUtils.showError(
          'No internet connection. Permissions update failed.',
        );
        return;
      }

      final permissions = {
        'canManageLocations': _canManageLocations,
        'canManageEmployees': _canManageEmployees,
        'canManageAdmins': _canManageAdmins,
        'canManageInventory': _canManageInventory,
        'canProcessSales': _canProcessSales,
        'canViewReports': _canViewReports,
        'canManageReceiving': _canManageReceiving,
        'canAdjustPrices': _canAdjustPrices,
        'canVoidSales': _canVoidSales,
      };

      final employeeRepo = Provider.of<EmployeeRepository>(
        context,
        listen: false,
      );
      final updated = widget.employee.copyWith(
        permissions: jsonEncode(permissions),
      );

      await employeeRepo.upsertEmployee(updated);

      if (mounted) {
        ToastUtils.showSuccess('Permissions updated successfully');
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ToastUtils.showError('Unable to save permissions. Please try again.');
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Permissions'),
        backgroundColor: AppTheme.primaryOrange,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Employee Info Card
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                backgroundColor:
                                    widget.employee.role ==
                                        AppConstants.roleAdmin
                                    ? AppTheme.primaryOrange
                                    : AppTheme.primaryBlack,
                                child: Text(
                                  widget.employee.firstName[0].toUpperCase(),
                                  style: const TextStyle(
                                    color: AppTheme.primaryWhite,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${widget.employee.firstName} ${widget.employee.surname}',
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color:
                                            widget.employee.role ==
                                                AppConstants.roleAdmin
                                            ? AppTheme.primaryOrange
                                            : AppTheme.primaryBlack,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        widget.employee.role,
                                        style: const TextStyle(
                                          color: AppTheme.primaryWhite,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Permissions Section
                  const Text(
                    'Permissions',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Grant or revoke permissions for this user',
                    style: TextStyle(color: AppTheme.darkGray, fontSize: 14),
                  ),
                  const SizedBox(height: 16),

                  // Location Management
                  Card(
                    child: Column(
                      children: [
                        _buildPermissionTile(
                          title: 'Manage Locations',
                          subtitle:
                              widget.employee.role == AppConstants.roleEmployee
                              ? 'Not available for Employees'
                              : 'Add, edit, and delete store locations',
                          icon: Icons.location_on,
                          value: _canManageLocations,
                          onChanged:
                              widget.employee.role == AppConstants.roleEmployee
                              ? null
                              : (value) =>
                                    setState(() => _canManageLocations = value),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Employee Management
                  Card(
                    child: Column(
                      children: [
                        _buildPermissionTile(
                          title: 'Manage Employees',
                          subtitle:
                              widget.employee.role == AppConstants.roleEmployee
                              ? 'Not available for Employees'
                              : 'Add, edit, and delete regular employees',
                          icon: Icons.people,
                          value: _canManageEmployees,
                          onChanged:
                              widget.employee.role == AppConstants.roleEmployee
                              ? null
                              : (value) =>
                                    setState(() => _canManageEmployees = value),
                        ),
                        const Divider(height: 1),
                        _buildPermissionTile(
                          title: 'Manage Admins',
                          subtitle:
                              widget.employee.role == AppConstants.roleEmployee
                              ? 'Not available for Employees'
                              : 'Add, edit, and delete administrators',
                          icon: Icons.admin_panel_settings,
                          value: _canManageAdmins,
                          onChanged:
                              widget.employee.role == AppConstants.roleEmployee
                              ? null
                              : (value) =>
                                    setState(() => _canManageAdmins = value),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Inventory Management
                  Card(
                    child: Column(
                      children: [
                        _buildPermissionTile(
                          title: 'Manage Inventory',
                          subtitle:
                              widget.employee.role == AppConstants.roleAdmin
                              ? 'Not available for Admins (oversight only)'
                              : 'Add, edit, and delete inventory items',
                          icon: Icons.inventory,
                          value: _canManageInventory,
                          onChanged:
                              widget.employee.role == AppConstants.roleAdmin
                              ? null
                              : (value) =>
                                    setState(() => _canManageInventory = value),
                        ),
                        const Divider(height: 1),
                        _buildPermissionTile(
                          title: 'Adjust Prices',
                          subtitle: 'Change item prices',
                          icon: Icons.attach_money,
                          value: _canAdjustPrices,
                          onChanged: (value) =>
                              setState(() => _canAdjustPrices = value),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Sales
                  Card(
                    child: Column(
                      children: [
                        _buildPermissionTile(
                          title: 'Process Sales',
                          subtitle:
                              widget.employee.role == AppConstants.roleAdmin
                              ? 'Not available for Admins (oversight only)'
                              : 'Make sales and handle transactions',
                          icon: Icons.shopping_cart,
                          value: _canProcessSales,
                          onChanged:
                              widget.employee.role == AppConstants.roleAdmin
                              ? null
                              : (value) =>
                                    setState(() => _canProcessSales = value),
                        ),
                        const Divider(height: 1),
                        _buildPermissionTile(
                          title: 'Void Sales',
                          subtitle: 'Cancel or void completed sales',
                          icon: Icons.cancel,
                          value: _canVoidSales,
                          onChanged: (value) =>
                              setState(() => _canVoidSales = value),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Receiving
                  Card(
                    child: Column(
                      children: [
                        _buildPermissionTile(
                          title: 'Manage Receiving',
                          subtitle:
                              widget.employee.role == AppConstants.roleAdmin
                              ? 'Not available for Admins (oversight only)'
                              : 'Record incoming inventory and deliveries',
                          icon: Icons.local_shipping,
                          value: _canManageReceiving,
                          onChanged:
                              widget.employee.role == AppConstants.roleAdmin
                              ? null
                              : (value) =>
                                    setState(() => _canManageReceiving = value),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Reports
                  Card(
                    child: Column(
                      children: [
                        _buildPermissionTile(
                          title: 'View Reports',
                          subtitle: 'Access sales reports and analytics',
                          icon: Icons.analytics,
                          value: _canViewReports,
                          onChanged: (value) =>
                              setState(() => _canViewReports = value),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Save Button
                  ElevatedButton.icon(
                    onPressed: _isSaving ? null : _savePermissions,
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
                    label: const Text('Save Permissions'),
                  ),

                  // Extra padding to ensure button is visible above navigation bar
                  const SizedBox(height: 80),
                ],
              ),
            ),
    );
  }

  Widget _buildPermissionTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) {
    return SwitchListTile(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 13, color: AppTheme.darkGray),
      ),
      secondary: Icon(icon, color: AppTheme.primaryOrange),
      value: value,
      onChanged: onChanged,
      activeColor: AppTheme.primaryOrange,
    );
  }
}
