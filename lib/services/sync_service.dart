import 'dart:async';
import 'dart:convert';
import 'package:drift/drift.dart' as drift;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/database/app_database.dart';
import 'supabase_service.dart';
import 'connectivity_service.dart';
import 'logo_service.dart';
import 'time_service.dart';

/// Service to sync local SQLite data to Supabase
class SyncService extends ChangeNotifier {
  static SyncService? _instance;
  final AppDatabase _db;
  final SupabaseService _supabase;
  final ConnectivityService _connectivity;
  final TimeService _timeService;
  
  Timer? _periodicSyncTimer;
  Timer? _backupReminderTimer;
  Timer? _scheduledSyncCheckTimer;
  DateTime? _lastSuccessfulSync;
  bool _isSyncing = false;
  
  static const String _lastScheduledSyncKey = 'last_scheduled_sync';
  
  final StreamController<SyncProgress> _syncProgressController = StreamController<SyncProgress>.broadcast();
  Stream<SyncProgress> get syncProgress => _syncProgressController.stream;
  
  bool get isSyncing => _isSyncing;
  DateTime? get lastSyncTime => _lastSuccessfulSync;
  
  SyncService._(this._db, this._supabase, this._connectivity, this._timeService) {
    _initSync();
  }
  
  static SyncService initialize(
    AppDatabase db,
    SupabaseService supabase,
    ConnectivityService connectivity,
    TimeService timeService,
  ) {
    _instance = SyncService._(db, supabase, connectivity, timeService);
    return _instance!;
  }
  
  static SyncService get instance {
    if (_instance == null) {
      throw Exception('SyncService not initialized. Call initialize() first.');
    }
    return _instance!;
  }
  
  void _initSync() {
    // Listen to connectivity changes
    _connectivity.connectionStatus.listen((hasConnection) {
      if (hasConnection) {
        // Internet detected - trigger auto sync
        print('📶 Internet connected - triggering auto-sync');
        syncNow();
      }
    });
    
    // Start periodic auto sync (every 5 minutes)
    _startPeriodicSync();

    // Start periodic sync check (every minute) for scheduled times
    _startScheduledSyncCheck();
  }

  void _startPeriodicSync() {
    _periodicSyncTimer?.cancel();
    _periodicSyncTimer = Timer.periodic(const Duration(minutes: 5), (_) async {
      if (!_connectivity.hasConnection || _isSyncing) {
        return;
      }
      await syncNow(reason: 'Auto sync');
    });
  }
  
  /// Start checking for scheduled sync times (7 AM and 9 PM)
  void _startScheduledSyncCheck() {
    // Check every minute if we're in a scheduled sync window
    _scheduledSyncCheckTimer = Timer.periodic(const Duration(minutes: 1), (_) async {
      await _checkScheduledSync();
    });
  }
  
  /// Check if we should perform scheduled sync (7 AM or 9 PM)
  Future<void> _checkScheduledSync() async {
    if (!_connectivity.hasConnection || _isSyncing) {
      return; // Skip if offline or already syncing
    }
    
    try {
      // Get real time from internet (not device clock)
      final realTime = await _timeService.getRealTime();
      
      // Check if we're in a scheduled sync window
      if (!_timeService.isScheduledSyncTime(realTime)) {
        return; // Not time yet
      }
      
      // Check if we already synced in this window
      final prefs = await SharedPreferences.getInstance();
      final lastScheduledSyncStr = prefs.getString(_lastScheduledSyncKey);
      
      if (lastScheduledSyncStr != null) {
        final lastScheduledSync = DateTime.parse(lastScheduledSyncStr);
        final minutesSinceLastSync = realTime.difference(lastScheduledSync).inMinutes;
        
        if (minutesSinceLastSync < 10) {
          return; // Already synced in this window (within 10 minutes)
        }
      }
      
      // Perform scheduled sync
      print('⏰ Scheduled sync time reached: ${realTime.hour}:${realTime.minute.toString().padLeft(2, '0')}');
      await syncNow(reason: 'Scheduled sync at ${realTime.hour}:00');
      
      // Mark this sync window as done
      await prefs.setString(_lastScheduledSyncKey, realTime.toIso8601String());
      
    } catch (e) {
      print('⚠️ Error checking scheduled sync: $e');
    }
  }
  
  /// Sync time offset if needed
  Future<void> _syncTimeIfNeeded() async {
    if (await _timeService.shouldSyncTime()) {
      await _timeService.syncTimeOffset();
    }
  }
  
  /// Manually trigger sync with optional reason
  Future<SyncResult> syncNow({String reason = 'Manual sync'}) async {
    if (_isSyncing) {
      return SyncResult(
        success: false,
        message: 'Sync already in progress',
      );
    }
    
    if (!_connectivity.hasConnection) {
      return SyncResult(
        success: false,
        message: 'No internet connection',
      );
    }
    
    _isSyncing = true;
    _syncProgressController.add(SyncProgress(
      status: SyncStatus.syncing,
      message: 'Starting sync: $reason',
    ));
    notifyListeners();
    
    try {
      // Sync time offset first
      await _syncTimeIfNeeded();
      
      int totalSynced = 0;
      final List<String> syncDetails = [];
      
      // Sync logos first (in case locations need them)
      final logoService = LogoService(_supabase.client, _connectivity);
      await logoService.syncPendingLogos(_db);
      
      // Sync locations FIRST (other tables reference location_id)
      final locationsCount = await _syncLocations();
      totalSynced += locationsCount;
      if (locationsCount > 0) syncDetails.add('$locationsCount locations');
      
      // Sync employees (references location_id)
      final employeesCount = await _syncEmployees();
      totalSynced += employeesCount;
      if (employeesCount > 0) syncDetails.add('$employeesCount employees');
      
      // Sync items (references location_id)
      final itemsCount = await _syncItems();
      totalSynced += itemsCount;
      if (itemsCount > 0) syncDetails.add('$itemsCount items');
      
      // Sync customers
      final customersCount = await _syncCustomers();
      totalSynced += customersCount;
      if (customersCount > 0) syncDetails.add('$customersCount customers');
      
      // Sync sales (references location_id, employee_id)
      final salesCount = await _syncSales();
      totalSynced += salesCount;
      if (salesCount > 0) syncDetails.add('$salesCount sales');
      
      // Sync receivings (references location_id, employee_id)
      final receivingsCount = await _syncReceivings();
      totalSynced += receivingsCount;
      if (receivingsCount > 0) syncDetails.add('$receivingsCount receivings');
      
      // Sync credits (references customer_id)
      final creditsCount = await _syncCredits();
      totalSynced += creditsCount;
      if (creditsCount > 0) syncDetails.add('$creditsCount credits');

      // Sync credit payments
      final creditPaymentsCount = await _syncCreditPayments();
      totalSynced += creditPaymentsCount;
      if (creditPaymentsCount > 0) syncDetails.add('$creditPaymentsCount credit payments');
      
      // Sync meter readings
      final readingsCount = await _syncMeterReadings();
      totalSynced += readingsCount;
      if (readingsCount > 0) syncDetails.add('$readingsCount meter readings');
      
      // Sync audit logs
      final logsCount = await _syncAuditLogs();
      totalSynced += logsCount;
      if (logsCount > 0) syncDetails.add('$logsCount audit logs');
      
      _lastSuccessfulSync = DateTime.now();
      _isSyncing = false;
      
      final message = totalSynced > 0
          ? 'Synced: ${syncDetails.join(', ')}'
          : 'All data up to date';
      
      _syncProgressController.add(SyncProgress(
        status: SyncStatus.completed,
        message: message,
        lastSyncTime: _lastSuccessfulSync,
        recordsSynced: totalSynced,
      ));
      notifyListeners();
      
      return SyncResult(success: true, message: message);
    } catch (e) {
      print('Sync error: $e'); // Log for debugging
      _isSyncing = false;
      const errorMessage = 'Sync failed. Please check your internet connection and try again.';
      
      _syncProgressController.add(SyncProgress(
        status: SyncStatus.failed,
        message: errorMessage,
        lastSyncTime: _lastSuccessfulSync,
      ));
      notifyListeners();
      
      return SyncResult(success: false, message: errorMessage);
    }
  }
  
  Future<int> _syncEmployees() async {
    // Get unsynced employees only
    final unsynced = await (_db.select(_db.employees)
        ..where((tbl) => tbl.syncedAt.isNull()))
        .get();
    
    print('🔍 Total unsynced employees: ${unsynced.length}');
    if (unsynced.isNotEmpty) {
      for (final e in unsynced) {
        print('   - ${e.firstName} ${e.surname} (id: ${e.id}, syncedAt: ${e.syncedAt})');
      }
    }
    
    if (unsynced.isEmpty) return 0;
    
    // Filter out super_admin (managed directly in Supabase)
    final toSync = unsynced.where((e) => e.id != 'super_admin').toList();
    
    // Mark super_admin as synced if present
    final superAdminList = unsynced.where((e) => e.id == 'super_admin').toList();
    if (superAdminList.isNotEmpty) {
      await (_db.update(_db.employees)..where((tbl) => tbl.id.equals('super_admin')))
          .write(EmployeesCompanion(syncedAt: drift.Value(DateTime.now())));
      print('⏭️ Marked super_admin as synced (managed in Supabase)');
    }
    
    if (toSync.isEmpty) {
      print('📋 No employees to sync (super_admin already handled)');
      return 0;
    }
    
    print('📋 Employees to sync to Supabase: ${toSync.length}');
    for (final e in toSync) {
      print('   → ${e.firstName} ${e.surname} (id: ${e.id}, location_id: ${e.locationId})');
    }
    
    int syncedCount = 0;
    
    for (final e in toSync) {
      try {
        // Decode permissions from JSON string to a Map
        Map<String, dynamic>? permissionsMap;
        if (e.permissions != null && e.permissions!.isNotEmpty) {
          permissionsMap = json.decode(e.permissions!);
        }

        final data = {
          'id': e.id,
          'location_id': e.locationId,
          'role': e.role,
          'first_name': e.firstName,
          'middle_name': e.middleName,
          'surname': e.surname,
          'phone': e.phone,
          'email': e.email,
          'username': e.username,
          'password_hash': e.passwordHash,
          'permissions': permissionsMap, // Pass the decoded map
          'is_active': e.isActive,
          'created_at': e.createdAt.toIso8601String(),
        };
        
        print('🔄 Syncing employee: ${e.firstName} ${e.surname} (role: ${e.role}, location_id: ${e.locationId})');
        await _supabase.syncToTable(tableName: 'employees', data: [data]);
        
        await (_db.update(_db.employees)..where((tbl) => tbl.id.equals(e.id)))
            .write(EmployeesCompanion(syncedAt: drift.Value(DateTime.now())));
        syncedCount++;
        print('✅ Synced employee: ${e.firstName} ${e.surname}');
      } catch (err) {
        print('⚠️ Failed to sync employee ${e.firstName} ${e.surname} (location_id: ${e.locationId}): $err');
      }
    }
    
    return syncedCount;
  }
  
  Future<int> _syncLocations() async {
    final unsynced = await (_db.select(_db.locations)
        ..where((tbl) => tbl.id.isNotNull()))
        .get();
    
    if (unsynced.isEmpty) return 0;
    
    print('📍 Locations to sync: ${unsynced.length}');
    for (final loc in unsynced) {
      print('   - ID: ${loc.id}, Name: ${loc.name}');
    }
    
    final data = unsynced.map((loc) => {
      'id': loc.id,
      'name': loc.name,
      'address': loc.address,
      'phone': loc.phone,
      'email': loc.email,
      'till_number': loc.tillNumber,
      'paybill_number': loc.paybillNumber,
      'logo_url': loc.logoUrl,
      'ago_pumps': loc.agoPumps,
      'pms_pumps': loc.pmsPumps,
      'created_at': loc.createdAt.toIso8601String(),
    }).toList();
    
    await _supabase.syncToTable(tableName: 'locations', data: data);
    print('✅ Locations synced successfully');
    
    return unsynced.length;
  }
  
  Future<int> _syncItems() async {
    final unsynced = await (_db.select(_db.items)
        ..where((tbl) => tbl.syncedAt.isNull()))
        .get();
    
    if (unsynced.isEmpty) return 0;
    
    print('📦 Items to sync: ${unsynced.length}');
    
    int syncedCount = 0;
    
    for (final item in unsynced) {
      try {
        final data = {
          'id': item.id,
          'location_id': item.locationId,
          'category': item.category,
          'name': item.name,
          'barcode': item.barcode,
          'buying_price': item.buyingPrice,
          'selling_price': item.sellingPrice,
          'wholesale_price': item.wholesalePrice,
          'quantity': item.quantity,
          'reorder_level': item.reorderLevel,
          'created_by': item.createdBy,
          'created_at': item.createdAt.toIso8601String(),
          'updated_at': item.updatedAt.toIso8601String(),
        };
        
        await _supabase.syncToTable(tableName: 'items', data: [data]);
        
        await (_db.update(_db.items)..where((tbl) => tbl.id.equals(item.id)))
            .write(ItemsCompanion(syncedAt: drift.Value(DateTime.now())));
        syncedCount++;
        print('✅ Synced item: ${item.name}');
      } catch (err) {
        print('⚠️ Failed to sync item ${item.name} (location_id: ${item.locationId}): $err');
      }
    }
    
    return syncedCount;
  }
  
  Future<int> _syncSales() async {
    final unsynced = await (_db.select(_db.sales)
        ..where((tbl) => tbl.syncedAt.isNull()))
        .get();
    
    if (unsynced.isEmpty) return 0;
    
    // Sync sales
    final salesData = unsynced.map((sale) => {
      'id': sale.id,
      'sale_id': sale.saleId,
      'location_id': sale.locationId,
      'category': sale.category,
      'employee_id': sale.employeeId,
      'payment_method': sale.paymentMethod,
      'total_amount': sale.totalAmount,
      'amount_paid': sale.amountPaid,
      'change_given': sale.changeGiven,
      'profit': sale.profit,
      'is_suspended': sale.isSuspended,
      'suspension_notes': sale.suspensionNotes,
      'timestamp': sale.timestamp.toIso8601String(),
    }).toList();
    
    await _supabase.syncToTable(tableName: 'sales', data: salesData);
    
    // Sync sale items
    for (final sale in unsynced) {
      final items = await _db.getSaleItems(sale.id);
      if (items.isNotEmpty) {
        final itemsData = items.map((item) => {
          'id': item.id,
          'sale_id': item.saleId,
          'item_id': item.itemId,
          'item_name': item.itemName,
          'quantity': item.quantity,
          'buying_price': item.buyingPrice,
          'selling_price': item.sellingPrice,
          'pricing_type': item.pricingType,
          'subtotal': item.subtotal,
        }).toList();
        
        await _supabase.syncToTable(tableName: 'sale_items', data: itemsData);
      }
    }
    
    // Mark as synced
    final now = DateTime.now();
    for (final sale in unsynced) {
      await (_db.update(_db.sales)..where((tbl) => tbl.id.equals(sale.id)))
          .write(SalesCompanion(syncedAt: drift.Value(now)));
    }
    
    return unsynced.length;
  }
  
  Future<int> _syncReceivings() async {
    final unsynced = await (_db.select(_db.receivings)
        ..where((tbl) => tbl.syncedAt.isNull()))
        .get();
    
    if (unsynced.isEmpty) return 0;
    
    final data = unsynced.map((rec) => {
      'id': rec.id,
      'receiving_id': rec.receivingId,
      'location_id': rec.locationId,
      'category': rec.category,
      'employee_id': rec.employeeId,
      'total_amount': rec.totalAmount,
      'timestamp': rec.timestamp.toIso8601String(),
    }).toList();
    
    await _supabase.syncToTable(tableName: 'receivings', data: data);
    
    final now = DateTime.now();
    for (final rec in unsynced) {
      await (_db.update(_db.receivings)..where((tbl) => tbl.id.equals(rec.id)))
          .write(ReceivingsCompanion(syncedAt: drift.Value(now)));
    }
    
    return unsynced.length;
  }
  
  Future<int> _syncCustomers() async {
    final unsynced = await (_db.select(_db.customers)
        ..where((tbl) => tbl.syncedAt.isNull()))
        .get();
    
    if (unsynced.isEmpty) return 0;
    
    final data = unsynced.map((c) => {
      'id': c.id,
      'location_id': c.locationId,
      'category': c.category,
      'first_name': c.firstName,
      'last_name': c.lastName,
      'phone': c.phone,
      'created_at': c.createdAt.toIso8601String(),
    }).toList();
    
    await _supabase.syncToTable(tableName: 'customers', data: data);
    
    final now = DateTime.now();
    for (final c in unsynced) {
      await (_db.update(_db.customers)..where((tbl) => tbl.id.equals(c.id)))
          .write(CustomersCompanion(syncedAt: drift.Value(now)));
    }
    
    return unsynced.length;
  }
  
  Future<int> _syncCredits() async {
    final unsynced = await (_db.select(_db.credits)
        ..where((tbl) => tbl.syncedAt.isNull()))
        .get();
    
    if (unsynced.isEmpty) return 0;
    
    final data = unsynced.map((cr) => {
      'id': cr.id,
      'customer_id': cr.customerId,
      'sale_id': cr.saleId,
      'location_id': cr.locationId,
      'category': cr.category,
      'total_owed': cr.totalOwed,
      'amount_paid': cr.amountPaid,
      'balance': cr.balance,
      'created_at': cr.createdAt.toIso8601String(),
      'last_payment_at': cr.lastPaymentAt?.toIso8601String(),
    }).toList();
    
    await _supabase.syncToTable(tableName: 'credits', data: data);
    
    final now = DateTime.now();
    for (final cr in unsynced) {
      await (_db.update(_db.credits)..where((tbl) => tbl.id.equals(cr.id)))
          .write(CreditsCompanion(syncedAt: drift.Value(now)));
    }
    
    return unsynced.length;
  }

  Future<int> _syncCreditPayments() async {
    final unsynced = await (_db.select(_db.creditPayments)
        ..where((tbl) => tbl.syncedAt.isNull()))
        .get();

    if (unsynced.isEmpty) return 0;

    final data = unsynced.map((cp) => {
      'id': cp.id,
      'credit_id': cp.creditId,
      'amount': cp.amount,
      'paid_at': cp.paidAt.toIso8601String(),
    }).toList();

    await _supabase.syncToTable(tableName: 'credit_payments', data: data);

    final now = DateTime.now();
    for (final cp in unsynced) {
      await (_db.update(_db.creditPayments)..where((tbl) => tbl.id.equals(cp.id)))
          .write(CreditPaymentsCompanion(syncedAt: drift.Value(now)));
    }

    return unsynced.length;
  }
  
  Future<int> _syncMeterReadings() async {
    final unsynced = await (_db.select(_db.meterReadings)
        ..where((tbl) => tbl.syncedAt.isNull()))
        .get();
    
    if (unsynced.isEmpty) return 0;
    
    final data = unsynced.map((mr) => {
      'id': mr.id,
      'location_id': mr.locationId,
      'employee_id': mr.employeeId,
      'reading_type': mr.readingType,
      'category': mr.category,
      'pump_type': mr.pumpType,
      'pump_number': mr.pumpNumber,
      'value_a': mr.valueA,
      'value_l': mr.valueL,
      'value_t': mr.valueT,
      'timestamp': mr.timestamp.toIso8601String(),
    }).toList();
    
    await _supabase.syncToTable(tableName: 'meter_readings', data: data);
    
    final now = DateTime.now();
    for (final mr in unsynced) {
      await (_db.update(_db.meterReadings)..where((tbl) => tbl.id.equals(mr.id)))
          .write(MeterReadingsCompanion(syncedAt: drift.Value(now)));
    }
    
    return unsynced.length;
  }
  
  Future<int> _syncAuditLogs() async {
    final unsynced = await (_db.select(_db.auditLogs)
        ..where((tbl) => tbl.syncedAt.isNull()))
        .get();
    
    if (unsynced.isEmpty) return 0;
    
    final data = unsynced.map((log) => {
      'id': log.id,
      'location_id': log.locationId,
      'employee_id': log.employeeId,
      'action_type': log.actionType,
      'entity_id': log.entityId,
      'changes': log.changes,
      'timestamp': log.timestamp.toIso8601String(),
    }).toList();
    
    await _supabase.syncToTable(tableName: 'audit_logs', data: data);
    
    final now = DateTime.now();
    for (final log in unsynced) {
      await (_db.update(_db.auditLogs)..where((tbl) => tbl.id.equals(log.id)))
          .write(AuditLogsCompanion(syncedAt: drift.Value(now)));
    }
    
    return unsynced.length;
  }
  
  /// Clean up resources
  @override
  void dispose() {
    _syncProgressController.close();
    _periodicSyncTimer?.cancel();
    _backupReminderTimer?.cancel();
    _scheduledSyncCheckTimer?.cancel();
    super.dispose();
  }
}

// ============================================================================
// MODELS
// ============================================================================

enum SyncStatus {
  syncing,
  completed,
  failed,
  promptRequired,
}

class SyncProgress {
  final SyncStatus status;
  final String message;
  final DateTime? lastSyncTime;
  final int? recordsSynced;
  
  SyncProgress({
    required this.status,
    required this.message,
    this.lastSyncTime,
    this.recordsSynced,
  });
}

class SyncResult {
  final bool success;
  final String message;
  
  SyncResult({
    required this.success,
    required this.message,
  });
}
