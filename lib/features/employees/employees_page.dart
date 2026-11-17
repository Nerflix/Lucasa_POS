import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/constants/app_constants.dart';
import '../../data/database/app_database.dart';
import '../../services/auth_service.dart';
import '../../services/connectivity_service.dart';
import '../../services/supabase_service.dart';
import '../../core/utils/toast_utils.dart';
import 'add_employee_dialog.dart';
import 'permissions_page.dart';
import 'employee_detail_page.dart';
import 'sync_auth_users_dialog.dart';

class EmployeesPage extends StatefulWidget {
  const EmployeesPage({super.key});

  @override
  State<EmployeesPage> createState() => _EmployeesPageState();
}

class _EmployeesPageState extends State<EmployeesPage> {
  List<Employee> _employees = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadEmployees();
  }

  Future<void> _loadEmployees() async {
    setState(() => _isLoading = true);
    
    final db = Provider.of<AppDatabase>(context, listen: false);
    final employees = await db.getAllEmployees();
    
    setState(() {
      _employees = employees;
      _isLoading = false;
    });
  }

  void _showSyncAuthDialog() {
    showDialog(
      context: context,
      builder: (context) => const SyncAuthUsersDialog(),
    );
  }

  void _showAddEmployeeDialog() {
    // Check permission
    final authService = Provider.of<AuthService>(context, listen: false);
    if (!authService.hasPermission('canManageEmployees')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You do not have permission to add employees'),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AddEmployeeDialog(
        onEmployeeAdded: _loadEmployees,
      ),
    );
  }

  Future<void> _confirmDeleteEmployee(Employee employee) async {
    // Check permission based on employee role
    final authService = Provider.of<AuthService>(context, listen: false);
    final connectivityService = Provider.of<ConnectivityService>(context, listen: false);
    
    // Prevent deleting yourself
    if (authService.currentEmployee?.id == employee.id) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You cannot delete yourself. Ask another admin to remove your account.'),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }
    
    final isAdmin = employee.role == AppConstants.roleAdmin;
    final requiredPermission = isAdmin ? 'canManageAdmins' : 'canManageEmployees';
    
    if (!authService.hasPermission(requiredPermission)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('You do not have permission to delete ${isAdmin ? "admins" : "employees"}'),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Employee'),
        content: Text(
          'Are you sure you want to delete "${employee.firstName} ${employee.surname}"?\n\n'
          'This will permanently delete their account from both the cloud and this device. '
          'They will NOT be able to login anymore.\n\n'
          '⚠️ Internet connection is required for this action.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      if (!connectivityService.hasConnection) {
        ToastUtils.showError('No internet connection. Delete failed.');
        return;
      }
      try {
        // Show loading indicator
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(child: CircularProgressIndicator()),
        );
        
        // STEP 1: Hard delete from Supabase FIRST (requires internet)
        final supabase = SupabaseService.instance;
        await supabase.client
            .from('employees')
            .delete()
            .eq('id', employee.id)
            .timeout(const Duration(seconds: 10));
        
        print('✅ Employee deleted from Supabase: ${employee.email}');
        
        // STEP 2: Delete from local database
        final db = Provider.of<AppDatabase>(context, listen: false);
        await db.deleteEmployee(employee.id);
        
        print('✅ Employee deleted from local database: ${employee.email}');
        
        if (mounted) {
          Navigator.pop(context); // Close loading indicator
          ToastUtils.showSuccess('Employee deleted permanently from cloud and local.');
          
          await _loadEmployees();
        }
      } catch (e) {
        print('Delete employee error: $e'); // Log for debugging
        if (mounted) {
          Navigator.pop(context); // Close loading indicator
          ToastUtils.showError(
            'No internet connection. Delete failed. Please connect and try again.',
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth <= 600;

    return Scaffold(
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: isMobile
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Employees',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            ElevatedButton.icon(
                              onPressed: _showAddEmployeeDialog,
                              icon: const Icon(Icons.person_add),
                              label: const Text('Add Employee'),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                minimumSize: const Size.fromHeight(52),
                              ),
                            ),
                          ],
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Employees',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Row(
                              children: [
                                OutlinedButton.icon(
                                  onPressed: _showSyncAuthDialog,
                                  icon: const Icon(Icons.sync),
                                  label: const Text('Sync Auth'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppTheme.primaryOrange,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                ElevatedButton.icon(
                                  onPressed: _showAddEmployeeDialog,
                                  icon: const Icon(Icons.person_add),
                                  label: const Text('Add Employee'),
                                ),
                              ],
                            ),
                          ],
                        ),
                ),
                
                // Employees list
                Expanded(
                  child: _employees.isEmpty
                      ? const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.people_outline, size: 64, color: AppTheme.darkGray),
                              SizedBox(height: 16),
                              Text(
                                'No employees yet',
                                style: TextStyle(color: AppTheme.darkGray),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: EdgeInsets.fromLTRB(
                            16,
                            0,
                            16,
                            96 + MediaQuery.of(context).padding.bottom,
                          ),
                          itemCount: _employees.length,
                          itemBuilder: (context, index) {
                            final employee = _employees[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              child: InkWell(
                                onTap: () async {
                                  final result = await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => EmployeeDetailPage(employee: employee),
                                    ),
                                  );
                                  if (result == true) {
                                    _loadEmployees(); // Reload if changes were made
                                  }
                                },
                                child: Padding(
                                  padding: const EdgeInsets.all(12.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        CircleAvatar(
                                          backgroundColor: employee.role == AppConstants.roleAdmin
                                              ? AppTheme.primaryOrange
                                              : AppTheme.primaryBlack,
                                          child: Text(
                                            employee.firstName[0].toUpperCase(),
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
                                                '${employee.firstName} ${employee.middleName ?? ""} ${employee.surname}',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 16,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Container(
                                                padding: const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 2,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: employee.role == AppConstants.roleAdmin
                                                      ? AppTheme.primaryOrange
                                                      : AppTheme.primaryBlack,
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  employee.role,
                                                  style: const TextStyle(
                                                    color: AppTheme.primaryWhite,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        PopupMenuButton(
                                          icon: const Icon(Icons.more_vert),
                                          itemBuilder: (context) => [
                                            const PopupMenuItem(
                                              value: 'permissions',
                                              child: Row(
                                                children: [
                                                  Icon(Icons.security, size: 20, color: AppTheme.primaryOrange),
                                                  SizedBox(width: 8),
                                                  Text('Permissions'),
                                                ],
                                              ),
                                            ),
                                            const PopupMenuItem(
                                              value: 'edit',
                                              child: Row(
                                                children: [
                                                  Icon(Icons.edit, size: 20, color: AppTheme.primaryOrange),
                                                  SizedBox(width: 8),
                                                  Text('Edit'),
                                                ],
                                              ),
                                            ),
                                          const PopupMenuItem(
                                            value: 'delete',
                                            child: Row(
                                              children: [
                                                Icon(Icons.delete, size: 20, color: AppTheme.error),
                                                SizedBox(width: 8),
                                                Text('Delete'),
                                              ],
                                            ),
                                          ),
                                          ],
                                          onSelected: (value) {
                                            if (value == 'permissions') {
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (context) => PermissionsPage(employee: employee),
                                                ),
                                              );
                                            } else if (value == 'edit') {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (context) => EmployeeDetailPage(employee: employee),
                                              ),
                                            ).then((_) => _loadEmployees());
                                            } else if (value == 'delete') {
                                              _confirmDeleteEmployee(employee);
                                            }
                                          },
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    const Divider(height: 1),
                                    const SizedBox(height: 12),
                                    Row(
                                      children: [
                                        const Icon(Icons.person, size: 16, color: AppTheme.darkGray),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            employee.username,
                                            style: const TextStyle(fontSize: 14),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        const Icon(Icons.phone, size: 16, color: AppTheme.darkGray),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            employee.phone,
                                            style: const TextStyle(fontSize: 14),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        const Icon(Icons.email, size: 16, color: AppTheme.darkGray),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            employee.email,
                                            style: const TextStyle(fontSize: 14),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                ),
              ],
            ),
    );
  }
}
