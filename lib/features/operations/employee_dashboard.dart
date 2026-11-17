import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../services/connectivity_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/constants/app_constants.dart';
import '../auth/login_page.dart';
import '../employees/change_password_dialog.dart';
import '../items/items_page.dart';
import '../sales/sales_page.dart';
import '../receivings/receivings_page.dart';
import '../customers/customers_page.dart';
import '../credits/credits_page.dart';
import '../suspended_sales/suspended_sales_page.dart';
import '../reports/reports_page.dart';
import '../meter_readings/meter_readings_dialog.dart';
import '../../widgets/overdue_credits_banner.dart';
import '../../data/repositories/inventory_repository.dart';

/// Employee operational dashboard - for regular employees only
/// Admins/Super Admins use MainDashboard instead
class EmployeeDashboard extends StatefulWidget {
  final String selectedCategory; // 'Filling Station' or 'Car Sale'

  const EmployeeDashboard({super.key, required this.selectedCategory});

  @override
  State<EmployeeDashboard> createState() => _EmployeeDashboardState();
}

class _EmployeeDashboardState extends State<EmployeeDashboard> {
  late String _currentCategory;
  int _selectedIndex = 0;
  DateTime? _lastBackPress;
  String? _resumeSaleId;

  @override
  void initState() {
    super.initState();
    _currentCategory = widget.selectedCategory;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<AuthService>(
        context,
        listen: false,
      ).setCategory(_currentCategory);
      _ensureDefaultFuelItems();
    });
  }

  Future<void> _ensureDefaultFuelItems() async {
    if (_currentCategory != AppConstants.categoryFillingStation) return;
    final authService = Provider.of<AuthService>(context, listen: false);
    final employee = authService.currentEmployee;
    if (employee == null) return;
    final locationId = authService.allowedLocationIds.isNotEmpty
        ? authService.allowedLocationIds.first
        : null;
    if (locationId == null) return;
    try {
      final inventoryRepo = Provider.of<InventoryRepository>(
        context,
        listen: false,
      );
      await inventoryRepo.ensureDefaultFuelItems(locationId, employee.id);
    } catch (_) {
      // Silent — non-critical, items may already exist
    }
  }

  void _onNavigationItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
      if (index != 0) {
        _resumeSaleId = null;
      }
    });
  }

  Widget _getCurrentPage() {
    switch (_selectedIndex) {
      case 0:
        return SalesPage(
          key: ValueKey('sales_$_resumeSaleId'),
          resumeSaleId: _resumeSaleId,
        );
      case 1:
        return const ItemsPage();
      case 2:
        return const ReceivingsPage();
      case 3:
        return const CustomersPage();
      case 4:
        return const CreditsPage();
      case 5:
        return SuspendedSalesPage(
          onResume: (saleId) {
            setState(() {
              _resumeSaleId = saleId;
              _selectedIndex = 0;
            });
          },
        );
      case 6:
        return const ReportsPage();
      default:
        return const SalesPage();
    }
  }

  Future<bool> _onWillPop() async {
    final now = DateTime.now();
    if (_lastBackPress == null ||
        now.difference(_lastBackPress!) > const Duration(seconds: 2)) {
      _lastBackPress = now;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Press back again to exit'),
          duration: Duration(seconds: 2),
        ),
      );
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final connectivityService = Provider.of<ConnectivityService>(context);

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              Icon(
                _currentCategory == AppConstants.categoryFillingStation
                    ? Icons.local_gas_station
                    : Icons.shopping_cart,
                size: 24,
              ),
              const SizedBox(width: 8),
              Text(_currentCategory),
            ],
          ),
          backgroundColor: AppTheme.primaryOrange,
          actions: [
            // Sync status indicator
            // Sync status indicator
            StreamBuilder<bool>(
              stream: connectivityService.connectionStatus,
              builder: (context, snapshot) {
                final isOnline =
                    snapshot.data ?? connectivityService.hasConnection;
                return IconButton(
                  icon: Icon(
                    isOnline ? Icons.cloud_done : Icons.cloud_off,
                    color: AppTheme.primaryWhite,
                  ),
                  onPressed: () {},
                  tooltip: isOnline ? 'Online' : 'Offline',
                );
              },
            ),
          ],
        ),
        drawer: _buildDrawer(authService),
        body: Column(
          children: [
            OverdueCreditsBanner(
              category: _currentCategory,
              locationIds: authService.allowedLocationIds,
            ),
            Expanded(child: _getCurrentPage()),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawer(AuthService authService) {
    final switchToCategory =
        _currentCategory == AppConstants.categoryFillingStation
        ? AppConstants.categoryCarSale
        : AppConstants.categoryFillingStation;
    final switchIcon = _currentCategory == AppConstants.categoryFillingStation
        ? Icons.shopping_cart
        : Icons.local_gas_station;

    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppTheme.primaryOrange, AppTheme.accentOrange],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                CircleAvatar(
                  backgroundColor: AppTheme.primaryWhite,
                  radius: 32,
                  child: Text(
                    authService.currentEmployee?.firstName[0].toUpperCase() ??
                        'E',
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryOrange,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '${authService.currentEmployee?.firstName ?? ""} ${authService.currentEmployee?.surname ?? ""}',
                  style: const TextStyle(
                    color: AppTheme.primaryWhite,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  authService.currentEmployee?.role ?? 'Employee',
                  style: TextStyle(
                    color: AppTheme.primaryWhite.withOpacity(0.9),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),

          // Category indicator
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              decoration: BoxDecoration(
                color: AppTheme.primaryOrange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    _currentCategory == AppConstants.categoryFillingStation
                        ? Icons.local_gas_station
                        : Icons.shopping_cart,
                    size: 20,
                    color: AppTheme.primaryOrange,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Mode: $_currentCategory',
                    style: const TextStyle(
                      fontWeight: FontWeight.w500,
                      color: AppTheme.primaryOrange,
                    ),
                  ),
                ],
              ),
            ),
          ),

          ListTile(
            leading: Icon(switchIcon, color: AppTheme.primaryOrange),
            title: Text('Switch to $switchToCategory'),
            onTap: () {
              Navigator.of(context).pop();
              setState(() {
                _currentCategory = switchToCategory;
                _selectedIndex = 0;
                _resumeSaleId = null;
              });
              authService.setCategory(_currentCategory);
            },
          ),

          // Operational pages
          _buildDrawerItem(
            Icons.point_of_sale,
            'Sales',
            0,
            _selectedIndex == 0,
          ),
          _buildDrawerItem(Icons.inventory, 'Items', 1, _selectedIndex == 1),
          _buildDrawerItem(
            Icons.local_shipping,
            'Receivings',
            2,
            _selectedIndex == 2,
          ),
          _buildDrawerItem(
            Icons.people_outline,
            'Customers',
            3,
            _selectedIndex == 3,
          ),
          _buildDrawerItem(
            Icons.credit_card,
            'Credits',
            4,
            _selectedIndex == 4,
          ),
          _buildDrawerItem(
            Icons.pause_circle,
            'Suspended Sales',
            5,
            _selectedIndex == 5,
          ),
          if (authService.hasPermission('canViewReports'))
            _buildDrawerItem(
              Icons.assessment,
              'Reports',
              6,
              _selectedIndex == 6,
            ),

          const Divider(),

          // Change Password
          ListTile(
            leading: const Icon(
              Icons.lock_outline,
              color: AppTheme.primaryOrange,
            ),
            title: const Text('Change Password'),
            onTap: () {
              Navigator.of(context).pop();
              showDialog(
                context: context,
                builder: (context) => const ChangePasswordDialog(),
              );
            },
          ),

          // Logout
          ListTile(
            leading: const Icon(Icons.logout, color: AppTheme.error),
            title: const Text('Logout'),
            onTap: () async {
              await authService.logout();
              if (context.mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (context) => const LoginPage()),
                  (route) => false,
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDrawerItem(
    IconData icon,
    String title,
    int index,
    bool isSelected,
  ) {
    return ListTile(
      leading: Icon(
        icon,
        color: isSelected ? AppTheme.primaryOrange : AppTheme.darkGray,
      ),
      title: Text(
        title,
        style: TextStyle(
          color: isSelected ? AppTheme.primaryOrange : AppTheme.primaryBlack,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      selected: isSelected,
      selectedTileColor: AppTheme.primaryOrange.withOpacity(0.1),
      onTap: () {
        Navigator.of(context).pop();
        _onNavigationItemTapped(index);
      },
    );
  }
}
