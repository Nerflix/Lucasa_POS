import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../services/connectivity_service.dart';
import '../../services/sync_service.dart';
import '../../data/database/app_database.dart';
import '../../core/theme/app_theme.dart';
import '../../core/constants/app_constants.dart';
import '../auth/login_page.dart';
import '../configuration/configuration_page.dart';
import '../employees/employees_page.dart';
import '../employees/change_password_dialog.dart';
import '../reports/reports_page.dart';
import '../items/items_page.dart';
import '../sales/sales_page.dart';
import '../receivings/receivings_page.dart';
import '../customers/customers_page.dart';
import '../credits/credits_page.dart';
import '../suspended_sales/suspended_sales_page.dart';
import '../../widgets/overdue_credits_banner.dart';
import '../../widgets/alerts_bell_icon.dart';

class MainDashboard extends StatefulWidget {
  final String selectedCategory;
  
  const MainDashboard({
    super.key,
    required this.selectedCategory,
  });

  @override
  State<MainDashboard> createState() => _MainDashboardState();
}

class _MainDashboardState extends State<MainDashboard> {
  late String _currentCategory;
  int _selectedIndex = 0;
  DateTime? _lastBackPress;
  bool _openNewLocation = false;

  @override
  void initState() {
    super.initState();
    _currentCategory = widget.selectedCategory;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<AuthService>(context, listen: false).setCategory(_currentCategory);
    });
  }

  void _onNavigationItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
      _openNewLocation = false;
    });
  }

  void _openAddLocation() {
    setState(() {
      _selectedIndex = 1;
      _openNewLocation = true;
    });
  }

  Future<void> _handlePullToSync(
    SyncService syncService,
    ConnectivityService connectivityService,
  ) async {
    final isOnline = connectivityService.hasConnection;
    if (!isOnline) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No internet connection. Connect to WiFi or mobile data to sync.'),
            backgroundColor: AppTheme.warning,
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    final result = await syncService.syncNow(reason: 'Pull to refresh');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message),
          backgroundColor: result.success ? AppTheme.success : AppTheme.error,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Widget _getCurrentPage() {
    final authService = Provider.of<AuthService>(context, listen: false);
    
    // For Super Admin and Admin - different pages
    if (authService.isSuperAdmin || authService.isAdmin) {
      switch (_selectedIndex) {
        case 0:
          return _buildDashboardHome();
        case 1:
          return ConfigurationPage(
            key: ValueKey('config_${_openNewLocation ? 'new' : 'list'}'),
            openNewLocation: _openNewLocation,
          );
        case 2:
          return const EmployeesPage();
        case 3:
          return const ReportsPage();
        default:
          return _buildDashboardHome();
      }
    }
    
    // For Employee - operational pages
    switch (_selectedIndex) {
      case 0:
        return const SalesPage();
      case 1:
        return const ItemsPage();
      case 2:
        return const ReceivingsPage();
      case 3:
        return const CustomersPage();
      case 4:
        return const CreditsPage();
      case 5:
        return const SuspendedSalesPage();
      default:
        return const SalesPage();
    }
  }

  Widget _buildDashboardHome() {
    final authService = Provider.of<AuthService>(context);
    final db = Provider.of<AppDatabase>(context, listen: false);
    final screenWidth = MediaQuery.of(context).size.width;
    final crossAxisCount = screenWidth > 600 ? 4 : 2;
    
    return Scaffold(
      body: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Welcome, ${authService.currentEmployee?.firstName ?? "User"}!',
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: AppTheme.primaryBlack,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              authService.isSuperAdmin ? 'Super Administrator' : 'Administrator',
              style: const TextStyle(
                fontSize: 16,
                color: AppTheme.darkGray,
              ),
            ),
            const SizedBox(height: 32),
            
            // Quick Stats Cards
            FutureBuilder<Map<String, dynamic>>(
              future: _loadDashboardStats(db, _currentCategory),
              builder: (context, snapshot) {
                final stats = snapshot.data ?? {
                  'locations': 0,
                  'employees': 0,
                  'totalSales': 0.0,
                };
                
                return GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  children: [
                    _buildStatCard(
                      'Locations',
                      '${stats['locations']}',
                      Icons.location_on,
                      AppTheme.primaryOrange,
                      onTap: () {
                        setState(() {
                          _selectedIndex = 1; // Configuration page
                        });
                      },
                    ),
                    _buildStatCard(
                      'Employees',
                      '${stats['employees']}',
                      Icons.people,
                      AppTheme.primaryBlack,
                      onTap: () {
                        setState(() {
                          _selectedIndex = 2; // Employees page
                        });
                      },
                    ),
                    _buildStatCard(
                      'Total Sales',
                      'KES ${stats['totalSales'].toStringAsFixed(0)}',
                      Icons.trending_up,
                      AppTheme.success,
                      onTap: () {
                        // Could navigate to sales report in future
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Sales report coming soon'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                    ),
                    _buildStatCard(
                      'Reports',
                      'View',
                      Icons.assessment,
                      AppTheme.info,
                      onTap: () {
                        setState(() {
                          _selectedIndex = 3; // Reports page
                        });
                      },
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<Map<String, dynamic>> _loadDashboardStats(
    AppDatabase db,
    String category,
  ) async {
    final locations = await db.getAllLocations();
    final employees = await db.getAllEmployees();
    
    // Get all sales by querying all locations
    double totalSales = 0.0;
    for (final location in locations) {
      final locationSales = await db.getSalesByLocationAndCategory(
        location.id,
        category,
      );
      for (final sale in locationSales) {
        if (!sale.isSuspended) {
          totalSales += sale.totalAmount;
        }
      }
    }
    
    return {
      'locations': locations.length,
      'employees': employees.length,
      'totalSales': totalSales,
    };
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color, {VoidCallback? onTap}) {
    return Card(
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 48, color: color),
              const SizedBox(height: 12),
              Text(
                value,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppTheme.darkGray,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReportsPlaceholder() {
    return const ReportsPage();
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final connectivityService = Provider.of<ConnectivityService>(context);
    final syncService = Provider.of<SyncService>(context);

    return PopScope(
      canPop: false,
      onPopInvoked: (bool didPop) async {
        if (didPop) return;
        
        // If not on home page (index 0), navigate back to home
        if (_selectedIndex != 0) {
          setState(() {
            _selectedIndex = 0;
          });
          return;
        }
        
        // On home page - show "press again to exit" behavior
        final now = DateTime.now();
        final backButtonHasTwoSecondsPassed = _lastBackPress == null ||
            now.difference(_lastBackPress!) > const Duration(seconds: 2);
            
        if (backButtonHasTwoSecondsPassed) {
          _lastBackPress = now;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Press back again to exit'),
              duration: Duration(seconds: 2),
              backgroundColor: AppTheme.darkGray,
            ),
          );
          return;
        }
        
        // Exit the app
        Navigator.of(context).pop();
      },
      child: Scaffold(
      appBar: AppBar(
        title: Text(
          authService.isEmployee 
              ? _currentCategory 
              : 'Lucasa POS',
        ),
        actions: [
          // Category toggle for employees
          if (authService.isEmployee)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: AppConstants.categoryFillingStation,
                    label: Text('Filling Station'),
                    icon: Icon(Icons.local_gas_station, size: 16),
                  ),
                  ButtonSegment(
                    value: AppConstants.categoryCarSale,
                    label: Text('Car Sale'),
                    icon: Icon(Icons.shopping_cart, size: 16),
                  ),
                ],
                selected: {_currentCategory},
                onSelectionChanged: (Set<String> selection) {
                  setState(() {
                    _currentCategory = selection.first;
                    authService.setCategory(_currentCategory);
                  });
                },
              ),
            ),
          
          // Alerts notification bell
          const AlertsBellIcon(),

          // Sync status icon
          StreamBuilder<bool>(
            stream: connectivityService.connectionStatus,
            builder: (context, snapshot) {
              final isOnline = snapshot.data ?? connectivityService.hasConnection;
              return IconButton(
                icon: Icon(
                  isOnline ? Icons.cloud_done : Icons.cloud_off,
                  color: isOnline ? AppTheme.success : AppTheme.error,
                ),
                onPressed: () async {
                  if (isOnline) {
                    // Manual sync
                    final result = await syncService.syncNow();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(result.message),
                          backgroundColor: result.success ? AppTheme.success : AppTheme.error,
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  } else {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('No internet connection. Connect to WiFi or mobile data to sync.'),
                          backgroundColor: AppTheme.warning,
                          duration: Duration(seconds: 3),
                        ),
                      );
                    }
                  }
                },
                tooltip: isOnline ? 'Tap to sync' : 'Offline',
              );
            },
          ),
        ],
      ),
      drawer: _buildDrawer(context, authService),
      body: RefreshIndicator(
        onRefresh: () => _handlePullToSync(syncService, connectivityService),
        child: Column(
          children: [
            OverdueCreditsBanner(
              category: authService.isEmployee ? _currentCategory : null,
              locationIds: authService.isEmployee
                  ? authService.allowedLocationIds
                  : null,
            ),
            Expanded(child: _getCurrentPage()),
          ],
        ),
      ),
      ),
    );
  }

  Drawer _buildDrawer(BuildContext context, AuthService authService) {
    final switchToCategory = _currentCategory == AppConstants.categoryFillingStation
        ? AppConstants.categoryCarSale
        : AppConstants.categoryFillingStation;
    final switchIcon = _currentCategory == AppConstants.categoryFillingStation
        ? Icons.shopping_cart
        : Icons.local_gas_station;

    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          InkWell(
            onTap: () {
              Navigator.of(context).pop();
              if (_selectedIndex != 0) {
                _onNavigationItemTapped(0);
              }
            },
            child: DrawerHeader(
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
                  const CircleAvatar(
                    radius: 32,
                    backgroundColor: AppTheme.primaryWhite,
                    child: Icon(
                      Icons.person,
                      size: 40,
                      color: AppTheme.primaryOrange,
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
                  Text(
                    authService.userRole,
                    style: const TextStyle(
                      color: AppTheme.primaryWhite,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // Menu items based on role
          if (authService.isSuperAdmin || authService.isAdmin) ...[
            _buildDrawerItem(
              Icons.dashboard,
              'Dashboard',
              0,
              _selectedIndex == 0,
            ),
            _buildDrawerItem(
              Icons.settings,
              'Store Config',
              1,
              _selectedIndex == 1,
            ),
            _buildDrawerItem(
              Icons.people,
              'Employees',
              2,
              _selectedIndex == 2,
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'Quick Actions',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.darkGray,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.person_add, color: AppTheme.primaryOrange),
              title: const Text('Add Employee/Admin'),
              onTap: () {
                Navigator.of(context).pop();
                _onNavigationItemTapped(2); // Go to Employees page
              },
            ),
            if (authService.hasPermission('canManageLocations'))
              ListTile(
                leading: const Icon(Icons.add_location, color: AppTheme.primaryOrange),
                title: const Text('Add Location'),
                onTap: () {
                  Navigator.of(context).pop();
                  _openAddLocation();
                },
              ),
            const Divider(),
            _buildDrawerItem(
              Icons.assessment,
              'Reports',
              3,
              _selectedIndex == 3,
            ),
          ] else ...[
            ListTile(
              leading: Icon(switchIcon, color: AppTheme.primaryOrange),
              title: Text('Switch to $switchToCategory'),
              onTap: () {
                Navigator.of(context).pop();
                setState(() {
                  _currentCategory = switchToCategory;
                  _selectedIndex = 0;
                });
                authService.setCategory(_currentCategory);
              },
            ),
            _buildDrawerItem(
              Icons.point_of_sale,
              'Sales',
              0,
              _selectedIndex == 0,
            ),
            _buildDrawerItem(
              Icons.inventory,
              'Items',
              1,
              _selectedIndex == 1,
            ),
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
          ],
          
          const Divider(),
          
          // Change Password
          ListTile(
            leading: const Icon(Icons.lock_outline, color: AppTheme.primaryOrange),
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

  Widget _buildDrawerItem(IconData icon, String title, int index, bool isSelected) {
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
