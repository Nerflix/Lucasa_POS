import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:drift/drift.dart' as drift;
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../data/database/app_database.dart';
import '../../services/auth_service.dart';
import '../../core/utils/toast_utils.dart';
import 'customer_detail_page.dart';

class CustomersPage extends StatefulWidget {
  const CustomersPage({super.key});

  @override
  State<CustomersPage> createState() => _CustomersPageState();
}

class _CustomersPageState extends State<CustomersPage> {
  final _searchController = TextEditingController();
  List<Customer> _customers = [];
  List<Customer> _filteredCustomers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCustomers() async {
    setState(() => _isLoading = true);
    
    final db = Provider.of<AppDatabase>(context, listen: false);
    final authService = Provider.of<AuthService>(context, listen: false);
    
    // Get customers for current employee's allowed locations
    final allowedLocationIds = authService.allowedLocationIds;
    final category = authService.currentCategory ?? AppConstants.categoryFillingStation;
    List<Customer> customers = [];
    
    if (allowedLocationIds.isNotEmpty) {
      if (authService.hasMultipleLocations) {
        // Admin with multiple locations - get customers from all locations
        customers = await db.getCustomersByLocationsAndCategory(allowedLocationIds, category);
      } else {
        // Employee or admin with single location  
        customers = await db.getCustomersByLocationAndCategory(allowedLocationIds.first, category);
      }
    }
    
    setState(() {
      _customers = customers;
      _filteredCustomers = customers;
      _isLoading = false;
    });
  }

  void _filterCustomers(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredCustomers = _customers;
      } else {
        _filteredCustomers = _customers.where((customer) {
          return customer.firstName.toLowerCase().contains(query.toLowerCase()) ||
                 customer.lastName.toLowerCase().contains(query.toLowerCase()) ||
                 customer.phone.contains(query);
        }).toList();
      }
    });
  }

  void _showAddCustomerDialog() {
    showDialog(
      context: context,
      builder: (context) => _AddCustomerDialog(onCustomerAdded: _loadCustomers),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth <= 600;
    final authService = Provider.of<AuthService>(context);
    final canProcessSales = authService.hasPermission('canProcessSales');

    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Customers',
                      style: TextStyle(
                        fontSize: isMobile ? 24 : 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.person_add, color: AppTheme.primaryOrange, size: 32),
                      onPressed: canProcessSales ? _showAddCustomerDialog : null,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (!canProcessSales)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text(
                      'You do not have permission to manage customers.',
                      style: TextStyle(color: AppTheme.darkGray),
                    ),
                  ),
                TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    hintText: 'Search by name or phone',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: _filterCustomers,
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadCustomers,
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredCustomers.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                _customers.isEmpty ? Icons.people_outline : Icons.search_off,
                                size: 64,
                                color: AppTheme.darkGray,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _customers.isEmpty ? 'No customers yet' : 'No customers found',
                                style: const TextStyle(fontSize: 16, color: AppTheme.darkGray),
                              ),
                              if (_customers.isEmpty) ...[
                                const SizedBox(height: 16),
                                ElevatedButton.icon(
                                  onPressed: _showAddCustomerDialog,
                                  icon: const Icon(Icons.add),
                                  label: const Text('Add First Customer'),
                                ),
                              ],
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _filteredCustomers.length,
                          itemBuilder: (context, index) {
                            final customer = _filteredCustomers[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: AppTheme.primaryOrange,
                                  child: Text(
                                    customer.firstName[0].toUpperCase(),
                                    style: const TextStyle(
                                      color: AppTheme.primaryWhite,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                title: Text(
                                  '${customer.firstName} ${customer.lastName}',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                subtitle: Text(customer.phone),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => CustomerDetailPage(customer: customer),
                                    ),
                                  ).then((_) => _loadCustomers());
                                },
                              ),
                            );
                          },
                        ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddCustomerDialog extends StatefulWidget {
  final VoidCallback onCustomerAdded;
  
  const _AddCustomerDialog({required this.onCustomerAdded});

  @override
  State<_AddCustomerDialog> createState() => _AddCustomerDialogState();
}

class _AddCustomerDialogState extends State<_AddCustomerDialog> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _isSaving = false;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _saveCustomer() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    final db = Provider.of<AppDatabase>(context, listen: false);
    final authService = Provider.of<AuthService>(context, listen: false);
    if (!authService.hasPermission('canProcessSales')) {
      ToastUtils.showError('You do not have permission to add customers.');
      setState(() => _isSaving = false);
      return;
    }
    
    try {
      final customerId = 'cust_${DateTime.now().millisecondsSinceEpoch}';
      final locationId = authService.allowedLocationIds.isNotEmpty
          ? authService.allowedLocationIds.first
          : '';
      final customer = CustomersCompanion.insert(
        id: customerId,
        locationId: locationId,
        category: drift.Value(
          authService.currentCategory ?? AppConstants.categoryFillingStation,
        ),
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        phone: _phoneController.text.trim(),
      );
      
      await db.insertCustomer(customer);
      
      if (mounted) {
        ToastUtils.showSuccess('Customer added successfully');
        widget.onCustomerAdded();
        Navigator.of(context).pop();
      }
    } catch (e) {
      print('Save customer error: $e'); // Log for debugging
      if (mounted) {
        ToastUtils.showError('Unable to save customer. Please try again.');
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 400,
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Add Customer',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _firstNameController,
                decoration: const InputDecoration(
                  labelText: 'First Name',
                  prefixIcon: Icon(Icons.person),
                ),
                validator: (v) => v?.trim().isEmpty ?? true ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _lastNameController,
                decoration: const InputDecoration(
                  labelText: 'Last Name',
                  prefixIcon: Icon(Icons.person),
                ),
                validator: (v) => v?.trim().isEmpty ?? true ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _phoneController,
                decoration: const InputDecoration(
                  labelText: 'Phone Number',
                  prefixIcon: Icon(Icons.phone),
                ),
                keyboardType: TextInputType.phone,
                validator: (v) => v?.trim().isEmpty ?? true ? 'Required' : null,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _isSaving ? null : _saveCustomer,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryWhite),
                          ),
                        )
                      : const Icon(Icons.save),
                  label: const Text('Add Customer'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
