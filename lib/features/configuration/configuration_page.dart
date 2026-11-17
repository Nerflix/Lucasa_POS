import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:drift/drift.dart' as drift;
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import '../../core/theme/app_theme.dart';
import '../../data/database/app_database.dart';
import '../../services/auth_service.dart';
import '../../services/logo_service.dart';
import '../../services/connectivity_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ConfigurationPage extends StatefulWidget {
  final bool openNewLocation;

  const ConfigurationPage({
    super.key,
    this.openNewLocation = false,
  });

  @override
  State<ConfigurationPage> createState() => _ConfigurationPageState();
}

class _ConfigurationPageState extends State<ConfigurationPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _tillNumberController = TextEditingController();
  final _paybillNumberController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _agoPumpsController = TextEditingController(text: '0');
  final _pmsPumpsController = TextEditingController(text: '0');
  
  File? _selectedLogoFile;
  String? _currentLogoPath;
  
  Location? _selectedLocation;
  List<Location> _locations = [];
  bool _isLoading = true;
  bool _isSaving = false;
  bool _showForm = false; // For mobile: toggle between list and form

  @override
  void initState() {
    super.initState();
    _loadLocations();
    if (widget.openNewLocation) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _clearForm();
        }
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _tillNumberController.dispose();
    _paybillNumberController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _agoPumpsController.dispose();
    _pmsPumpsController.dispose();
    super.dispose();
  }

  Future<void> _loadLocations() async {
    setState(() => _isLoading = true);
    
    final db = Provider.of<AppDatabase>(context, listen: false);
    final locations = await db.getAllLocations();
    
    setState(() {
      _locations = locations;
      _isLoading = false;
    });
  }

  void _loadLocationData(Location location) {
    // Check permission
    final authService = Provider.of<AuthService>(context, listen: false);
    if (!authService.hasPermission('canManageLocations')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You do not have permission to edit locations'),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }

    setState(() {
      _selectedLocation = location;
      _nameController.text = location.name;
      _tillNumberController.text = location.tillNumber ?? '';
      _paybillNumberController.text = location.paybillNumber ?? '';
      _addressController.text = location.address ?? '';
      _phoneController.text = location.phone ?? '';
      _emailController.text = location.email ?? '';
      _agoPumpsController.text = location.agoPumps.toString();
      _pmsPumpsController.text = location.pmsPumps.toString();
      _currentLogoPath = location.logoLocalPath;
      _selectedLogoFile = null;
      _showForm = true; // Show form on mobile
    });
  }

  void _clearForm() {
    setState(() {
      _selectedLocation = null;
      _nameController.clear();
      _tillNumberController.clear();
      _paybillNumberController.clear();
      _addressController.clear();
      _phoneController.clear();
      _emailController.clear();
      _agoPumpsController.text = '0';
      _pmsPumpsController.text = '0';
      _selectedLogoFile = null;
      _currentLogoPath = null;
      _showForm = true; // Show form when creating new
    });
  }

  void _backToList() {
    setState(() {
      _showForm = false;
      _selectedLocation = null;
      _clearFormControllers();
    });
  }

  void _clearFormControllers() {
    _nameController.clear();
    _tillNumberController.clear();
    _paybillNumberController.clear();
    _addressController.clear();
    _phoneController.clear();
    _emailController.clear();
    _agoPumpsController.text = '0';
    _pmsPumpsController.text = '0';
  }

  Future<void> _pickLogo() async {
    try {
      final logoService = LogoService(
        Supabase.instance.client,
        Provider.of<ConnectivityService>(context, listen: false),
      );
      
      final pickedFile = await logoService.pickLogo();
      if (pickedFile != null) {
        setState(() {
          _selectedLogoFile = File(pickedFile.path);
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Logo selected successfully'),
              backgroundColor: AppTheme.success,
              duration: Duration(seconds: 2),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No image selected'),
              backgroundColor: AppTheme.warning,
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      print('Image picker error: $e'); // Log for debugging
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to select image. Please try again.'),
            backgroundColor: AppTheme.error,
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _saveLocation() async {
    // Check permission
    final authService = Provider.of<AuthService>(context, listen: false);
    if (!authService.hasPermission('canManageLocations')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You do not have permission to manage locations'),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }

    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isSaving = true);

    final db = Provider.of<AppDatabase>(context, listen: false);
    final logoService = LogoService(
      Supabase.instance.client,
      Provider.of<ConnectivityService>(context, listen: false),
    );
    
    try {
      String? logoLocalPath = _currentLogoPath;
      String? logoUrl = _selectedLocation?.logoUrl;
      
      // Handle logo upload if a new logo was selected
      if (_selectedLogoFile != null) {
        try {
          final xFile = XFile(_selectedLogoFile!.path);
          final locationId = _selectedLocation?.id ?? 'loc_${DateTime.now().millisecondsSinceEpoch}';
          
          final logoData = await logoService.saveLogoForLocation(
            locationId: locationId,
            imageFile: xFile,
            db: db,
          );
          
          if (logoData['localPath'] != null) {
            logoLocalPath = logoData['localPath'];
          }
          if (logoData['supabaseUrl'] != null) {
            logoUrl = logoData['supabaseUrl'];
          }
        } catch (logoError) {
          // Log logo error but continue with location save
          print('Error saving logo: $logoError');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Warning: Logo upload failed but location will be saved'),
                backgroundColor: AppTheme.warning,
                duration: const Duration(seconds: 3),
              ),
            );
          }
        }
      }
      
      if (_selectedLocation == null) {
        // Create new location
        final locationId = 'loc_${DateTime.now().millisecondsSinceEpoch}';
        final location = LocationsCompanion.insert(
          id: locationId,
          name: _nameController.text.trim(),
          tillNumber: drift.Value(_tillNumberController.text.trim().isEmpty ? null : _tillNumberController.text.trim()),
          paybillNumber: drift.Value(_paybillNumberController.text.trim().isEmpty ? null : _paybillNumberController.text.trim()),
          address: drift.Value(_addressController.text.trim().isEmpty ? null : _addressController.text.trim()),
          phone: drift.Value(_phoneController.text.trim().isEmpty ? null : _phoneController.text.trim()),
          email: drift.Value(_emailController.text.trim().isEmpty ? null : _emailController.text.trim()),
          logoLocalPath: drift.Value(logoLocalPath),
          logoUrl: drift.Value(logoUrl),
          agoPumps: drift.Value(int.tryParse(_agoPumpsController.text) ?? 0),
          pmsPumps: drift.Value(int.tryParse(_pmsPumpsController.text) ?? 0),
        );
        
        await db.insertLocation(location);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location created successfully'),
              backgroundColor: AppTheme.success,
            ),
          );
        }
      } else {
        // Update existing location
        final location = LocationsCompanion(
          id: drift.Value(_selectedLocation!.id),
          name: drift.Value(_nameController.text.trim()),
          tillNumber: drift.Value(_tillNumberController.text.trim().isEmpty ? null : _tillNumberController.text.trim()),
          paybillNumber: drift.Value(_paybillNumberController.text.trim().isEmpty ? null : _paybillNumberController.text.trim()),
          address: drift.Value(_addressController.text.trim().isEmpty ? null : _addressController.text.trim()),
          phone: drift.Value(_phoneController.text.trim().isEmpty ? null : _phoneController.text.trim()),
          email: drift.Value(_emailController.text.trim().isEmpty ? null : _emailController.text.trim()),
          logoLocalPath: drift.Value(logoLocalPath),
          logoUrl: drift.Value(logoUrl),
          agoPumps: drift.Value(int.tryParse(_agoPumpsController.text) ?? 0),
          pmsPumps: drift.Value(int.tryParse(_pmsPumpsController.text) ?? 0),
        );
        
        await db.updateLocation(_selectedLocation!.id, location);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location updated successfully'),
              backgroundColor: AppTheme.success,
            ),
          );
        }
      }
      
      _clearForm();
      await _loadLocations();
    } catch (e) {
      print('Save location error: $e'); // Log for debugging
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to save location. Please try again.'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Future<void> _confirmDeleteLocation(Location location) async {
    // Check permission
    final authService = Provider.of<AuthService>(context, listen: false);
    if (!authService.hasPermission('canManageLocations')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You do not have permission to delete locations'),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Location'),
        content: Text(
          'Are you sure you want to delete "${location.name}"?\n\n'
          'This will also delete all related data including items, sales, and receivings for this location.',
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
      try {
        final db = Provider.of<AppDatabase>(context, listen: false);
        await db.deleteLocation(location.id);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location deleted successfully'),
              backgroundColor: AppTheme.success,
            ),
          );
          
          // Clear form if this was the selected location
          if (_selectedLocation?.id == location.id) {
            _clearForm();
          }
          
          await _loadLocations();
        }
      } catch (e) {
        print('Delete location error: $e'); // Log for debugging
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Unable to delete location. Please try again.'),
              backgroundColor: AppTheme.error,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final canCreateLocation = authService.isSuperAdmin;
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > 600;

    return Scaffold(
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : isTablet
              ? _buildTabletLayout(canCreateLocation)
              : _buildMobileLayout(canCreateLocation),
    );
  }

  // Tablet/Desktop Layout - Side by side
  Widget _buildTabletLayout(bool canCreateLocation) {
    return Row(
      children: [
        // Left side - Locations list
        SizedBox(
          width: 300,
          child: _buildLocationsList(canCreateLocation),
        ),
        
        // Right side - Location form
        Expanded(
          child: _buildLocationForm(),
        ),
      ],
    );
  }

  // Mobile Layout - Either list OR form
  Widget _buildMobileLayout(bool canCreateLocation) {
    if (_showForm) {
      return _buildLocationForm();
    } else {
      return _buildLocationsList(canCreateLocation);
    }
  }

  Widget _buildLocationsList(bool canCreateLocation) {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Locations',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (canCreateLocation)
                  IconButton(
                    icon: const Icon(Icons.add_circle, color: AppTheme.primaryOrange),
                    onPressed: _clearForm,
                    tooltip: 'New Location',
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _locations.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.location_off,
                          size: 64,
                          color: AppTheme.darkGray,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'No locations yet',
                          style: TextStyle(
                            fontSize: 16,
                            color: AppTheme.darkGray,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (canCreateLocation)
                          ElevatedButton.icon(
                            onPressed: _clearForm,
                            icon: const Icon(Icons.add),
                            label: const Text('Add First Location'),
                          ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _locations.length,
                    itemBuilder: (context, index) {
                      final location = _locations[index];
                      final isSelected = _selectedLocation?.id == location.id;
                      
                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        child: ListTile(
                          selected: isSelected,
                          selectedTileColor: AppTheme.primaryOrange.withOpacity(0.1),
                          leading: Icon(
                            Icons.location_on,
                            color: isSelected ? AppTheme.primaryOrange : AppTheme.darkGray,
                          ),
                          title: Text(
                            location.name,
                            style: TextStyle(
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (location.address != null)
                                Text(location.address!),
                              if (location.phone != null)
                                Text(location.phone!),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.delete, color: AppTheme.error),
                                tooltip: 'Delete Location',
                                onPressed: () => _confirmDeleteLocation(location),
                              ),
                              const Icon(Icons.chevron_right),
                            ],
                          ),
                          onTap: () => _loadLocationData(location),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationForm() {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth <= 600;

    return Card(
      margin: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Header with back button on mobile
          if (isMobile)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: AppTheme.mediumGray),
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: _backToList,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _selectedLocation == null ? 'New Location' : 'Edit Location',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!isMobile)
                      Text(
                        _selectedLocation == null ? 'New Location' : 'Edit Location',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    if (!isMobile) const SizedBox(height: 24),
                            Text(
                              _selectedLocation == null ? 'New Location' : 'Edit Location',
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 24),
                            
                            // Shop Name
                            TextFormField(
                              controller: _nameController,
                              decoration: const InputDecoration(
                                labelText: 'Shop Name',
                                hintText: 'Enter shop name',
                                prefixIcon: Icon(Icons.store),
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Shop name is required';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            
                            // Logo Upload
                            const Text(
                              'Shop Logo',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              height: 150,
                              decoration: BoxDecoration(
                                border: Border.all(color: AppTheme.lightGray),
                                borderRadius: BorderRadius.circular(8),
                                color: AppTheme.lightGray.withOpacity(0.1),
                              ),
                              child: _selectedLogoFile != null
                                  ? Stack(
                                      alignment: Alignment.topRight,
                                      children: [
                                        Center(
                                          child: Image.file(
                                            _selectedLogoFile!,
                                            height: 140,
                                            fit: BoxFit.contain,
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.close, color: AppTheme.error),
                                          onPressed: () {
                                            setState(() {
                                              _selectedLogoFile = null;
                                            });
                                          },
                                        ),
                                      ],
                                    )
                                  : _currentLogoPath != null
                                      ? Stack(
                                          alignment: Alignment.topRight,
                                          children: [
                                            Center(
                                              child: Image.file(
                                                File(_currentLogoPath!),
                                                height: 140,
                                                fit: BoxFit.contain,
                                              ),
                                            ),
                                            IconButton(
                                              icon: const Icon(Icons.close, color: AppTheme.error),
                                              onPressed: () {
                                                setState(() {
                                                  _currentLogoPath = null;
                                                });
                                              },
                                            ),
                                          ],
                                        )
                                      : Center(
                                          child: TextButton.icon(
                                            onPressed: _pickLogo,
                                            icon: const Icon(Icons.image),
                                            label: const Text('Choose Logo'),
                                          ),
                                        ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Logo will be used on receipts. Recommended size: 512x512 pixels',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.darkGray.withOpacity(0.7),
                              ),
                            ),
                            const SizedBox(height: 16),
                            
                            // Till Number
                            TextFormField(
                              controller: _tillNumberController,
                              decoration: const InputDecoration(
                                labelText: 'Till Number (Mpesa)',
                                hintText: 'Enter till number',
                                prefixIcon: Icon(Icons.payment),
                              ),
                              keyboardType: TextInputType.number,
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            ),
                            const SizedBox(height: 16),
                            
                            // Paybill Number
                            TextFormField(
                              controller: _paybillNumberController,
                              decoration: const InputDecoration(
                                labelText: 'Paybill Number (Equity)',
                                hintText: 'Enter paybill number',
                                prefixIcon: Icon(Icons.account_balance),
                              ),
                              keyboardType: TextInputType.number,
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            ),
                            const SizedBox(height: 16),
                            
                            // Address
                            TextFormField(
                              controller: _addressController,
                              decoration: const InputDecoration(
                                labelText: 'Location/Address',
                                hintText: 'Enter address',
                                prefixIcon: Icon(Icons.location_on),
                              ),
                              maxLines: 2,
                            ),
                            const SizedBox(height: 16),
                            
                            // Phone
                            TextFormField(
                              controller: _phoneController,
                              decoration: const InputDecoration(
                                labelText: 'Phone Number',
                                hintText: 'Enter phone number',
                                prefixIcon: Icon(Icons.phone),
                              ),
                              keyboardType: TextInputType.phone,
                            ),
                            const SizedBox(height: 16),
                            
                            // Email
                            TextFormField(
                              controller: _emailController,
                              decoration: const InputDecoration(
                                labelText: 'Email',
                                hintText: 'Enter email',
                                prefixIcon: Icon(Icons.email),
                              ),
                              keyboardType: TextInputType.emailAddress,
                            ),
                            const SizedBox(height: 24),
                            
                            // Pump Setup Section
                            const Text(
                              'Pump Setup (Filling Station)',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 16),
                            
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _agoPumpsController,
                                    decoration: const InputDecoration(
                                      labelText: 'AGO Pumps',
                                      hintText: '0',
                                      prefixIcon: Icon(Icons.local_gas_station),
                                    ),
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                    validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return 'Required';
                                      }
                                      final num = int.tryParse(value);
                                      if (num == null || num < 0) {
                                        return 'Invalid number';
                                      }
                                      return null;
                                    },
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: TextFormField(
                                    controller: _pmsPumpsController,
                                    decoration: const InputDecoration(
                                      labelText: 'PMS Pumps',
                                      hintText: '0',
                                      prefixIcon: Icon(Icons.local_gas_station),
                                    ),
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                    validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return 'Required';
                                      }
                                      final num = int.tryParse(value);
                                      if (num == null || num < 0) {
                                        return 'Invalid number';
                                      }
                                      return null;
                                    },
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 32),
                            
                    // Save Button
                    const SizedBox(height: 24),
                    SizedBox(
                      height: 56,
                      child: ElevatedButton.icon(
                        onPressed: _isSaving ? null : _saveLocation,
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
                        label: Text(_selectedLocation == null ? 'Create Location' : 'Update Location'),
                      ),
                    ),
                    SizedBox(
                      height: isMobile
                          ? 96 + MediaQuery.of(context).padding.bottom
                          : 24,
                    ),
                    if (isMobile && _selectedLocation != null) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 56,
                        child: OutlinedButton.icon(
                          onPressed: _backToList,
                          icon: const Icon(Icons.close),
                          label: const Text('Cancel'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

