import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../models/location.dart';
import '../models/employee.dart';
import '../models/item.dart';
import '../models/sale.dart';
import '../models/customer.dart';
import '../models/meter_reading.dart';
import '../models/receiving.dart';

part 'app_database.g.dart';

// ============================================================================
// TABLE DEFINITIONS
// ============================================================================

/// Locations/Shops table
@UseRowClass(Location)
class Locations extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get address => text().nullable()();
  TextColumn get phone => text().nullable()();
  TextColumn get email => text().nullable()();
  TextColumn get tillNumber => text().nullable()();
  TextColumn get paybillNumber => text().nullable()();
  TextColumn get logoUrl => text().nullable()(); // Supabase URL after upload
  TextColumn get logoLocalPath =>
      text().nullable()(); // Local file path for offline
  IntColumn get agoPumps => integer().withDefault(const Constant(0))();
  IntColumn get pmsPumps => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Employees table
@UseRowClass(Employee)
class Employees extends Table {
  TextColumn get id => text()();
  TextColumn get locationId => text().nullable()();
  TextColumn get role => text()(); // 'super_admin', 'admin', 'employee'
  TextColumn get firstName => text()();
  TextColumn get middleName => text().nullable()();
  TextColumn get surname => text()();
  TextColumn get phone => text()();
  TextColumn get email => text()();
  TextColumn get username => text()();
  TextColumn get passwordHash => text()();
  TextColumn get permissions => text().nullable()(); // JSON string
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get syncedAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Items/Inventory table
@UseRowClass(Item)
class Items extends Table {
  TextColumn get id => text()();
  TextColumn get locationId => text()();
  TextColumn get category =>
      text().withDefault(const Constant('Filling Station'))();
  TextColumn get name => text()();
  TextColumn get barcode => text().nullable()();
  RealColumn get buyingPrice => real()();
  RealColumn get sellingPrice => real()();
  RealColumn get wholesalePrice => real()();
  RealColumn get quantity => real().withDefault(const Constant(0))();
  RealColumn get reorderLevel => real().withDefault(const Constant(0))();
  TextColumn get createdBy => text()(); // employee_id
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get syncedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Sales table
@UseRowClass(Sale)
class Sales extends Table {
  TextColumn get id => text()();
  TextColumn get saleId => text()(); // Human-readable ID
  TextColumn get locationId => text()();
  TextColumn get category =>
      text().withDefault(const Constant('Filling Station'))();
  TextColumn get employeeId => text()();
  TextColumn get paymentMethod => text()();
  RealColumn get totalAmount => real()();
  RealColumn get amountPaid => real()();
  RealColumn get changeGiven => real().withDefault(const Constant(0))();
  RealColumn get profit => real().withDefault(const Constant(0))();
  BoolColumn get isSuspended => boolean().withDefault(const Constant(false))();
  TextColumn get suspensionNotes => text().nullable()();
  TextColumn get employeeName => text().nullable()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get timestamp => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get syncedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Sale Items table (items in each sale)
@UseRowClass(SaleItem)
class SaleItems extends Table {
  TextColumn get id => text()();
  TextColumn get saleId => text()();
  TextColumn get itemId => text()();
  TextColumn get itemName => text()();
  RealColumn get quantity => real()();
  RealColumn get buyingPrice => real()();
  RealColumn get sellingPrice => real()();
  TextColumn get pricingType => text()(); // 'retail' or 'wholesale'
  RealColumn get subtotal => real()();
  DateTimeColumn get syncedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Receivings table (restocking)
@UseRowClass(Receiving)
class Receivings extends Table {
  TextColumn get id => text()();
  TextColumn get receivingId => text()(); // Human-readable ID
  TextColumn get locationId => text()();
  TextColumn get category =>
      text().withDefault(const Constant('Filling Station'))();
  TextColumn get employeeId => text()();
  RealColumn get totalAmount => real()();
  TextColumn get employeeName => text().nullable()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get timestamp => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get syncedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Receiving Items table
@UseRowClass(ReceivingItem)
class ReceivingItems extends Table {
  TextColumn get id => text()();
  TextColumn get receivingId => text()();
  TextColumn get itemId => text()();
  TextColumn get itemName => text()();
  RealColumn get quantity => real()();
  RealColumn get buyingPrice => real()();
  RealColumn get subtotal => real()();
  DateTimeColumn get syncedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Customers table
@UseRowClass(Customer)
class Customers extends Table {
  TextColumn get id => text()();
  TextColumn get locationId => text()();
  TextColumn get category =>
      text().withDefault(const Constant('Filling Station'))();
  TextColumn get firstName => text()();
  TextColumn get lastName => text()();
  TextColumn get phone => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get syncedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Credits table (customer debts)
@UseRowClass(Credit)
class Credits extends Table {
  TextColumn get id => text()();
  TextColumn get customerId => text()();
  TextColumn get saleId => text()();
  TextColumn get locationId => text()();
  TextColumn get category =>
      text().withDefault(const Constant('Filling Station'))();
  RealColumn get totalOwed => real()();
  RealColumn get amountPaid => real().withDefault(const Constant(0))();
  RealColumn get balance => real()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get lastPaymentAt => dateTime().nullable()();
  DateTimeColumn get syncedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Credit Payments table (payment history)
@UseRowClass(CreditPayment)
class CreditPayments extends Table {
  TextColumn get id => text()();
  TextColumn get creditId => text()();
  RealColumn get amount => real()();
  DateTimeColumn get paidAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get syncedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Meter Readings table (for filling stations)
@UseRowClass(MeterReading)
class MeterReadings extends Table {
  TextColumn get id => text()();
  TextColumn get locationId => text()();
  TextColumn get employeeId => text()();
  TextColumn get readingType => text()(); // 'opening' or 'closing'
  TextColumn get category =>
      text().withDefault(const Constant('Filling Station'))();
  TextColumn get pumpType => text()(); // 'AGO' or 'PMS'
  IntColumn get pumpNumber => integer()();
  RealColumn get valueA => real()();
  RealColumn get valueL => real()();
  RealColumn get valueT => real()();
  DateTimeColumn get timestamp => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get syncedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Audit Logs table (track deletions, edits, etc.)
@DataClassName('DbAuditLog')
class AuditLogs extends Table {
  TextColumn get id => text()();
  TextColumn get locationId => text()();
  TextColumn get employeeId => text()();
  TextColumn get actionType => text()(); // 'sale_deleted', 'sale_edited', etc.
  TextColumn get entityId => text()(); // ID of affected record
  TextColumn get changes => text().nullable()(); // JSON string
  DateTimeColumn get timestamp => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get syncedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Sync Status table (track what needs syncing)
@DataClassName('DbSyncQueue')
class SyncQueue extends Table {
  TextColumn get id => text()();
  TextColumn get tableNameValue => text()();
  TextColumn get recordId => text()();
  BoolColumn get isSynced => boolean().withDefault(const Constant(false))();
  DateTimeColumn get lastAttempt => dateTime().nullable()();
  TextColumn get errorMessage => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

// ============================================================================
// DATABASE CLASS
// ============================================================================

@DriftDatabase(
  tables: [
    Locations,
    Employees,
    Items,
    Sales,
    SaleItems,
    Receivings,
    ReceivingItems,
    Customers,
    Credits,
    CreditPayments,
    MeterReadings,
    AuditLogs,
    SyncQueue,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
    },
    onUpgrade: (Migrator m, int from, int to) async {
      if (from == 1) {
        // Add logoLocalPath column to locations table
        await m.addColumn(locations, locations.logoLocalPath);
      }
      if (from < 3) {
        await m.addColumn(items, items.category);
        await m.addColumn(sales, sales.category);
        await m.addColumn(receivings, receivings.category);
        await m.addColumn(customers, customers.category);
        await m.addColumn(credits, credits.category);
        await m.addColumn(meterReadings, meterReadings.category);
      }
      if (from < 4) {
        await m.addColumn(items, items.reorderLevel);
      }
    },
  );

  // ============================================================================
  // LOCATIONS
  // ============================================================================

  Future<List<Location>> getAllLocations() => select(locations).get();

  Future<Location?> getLocation(String id) =>
      (select(locations)..where((tbl) => tbl.id.equals(id))).getSingleOrNull();

  Future<int> insertLocation(LocationsCompanion location) =>
      into(locations).insert(location);

  Future<bool> updateLocation(String id, LocationsCompanion location) async {
    return await (update(
          locations,
        )..where((tbl) => tbl.id.equals(id))).write(location) >
        0;
  }

  Future<int> deleteLocation(String id) =>
      (delete(locations)..where((tbl) => tbl.id.equals(id))).go();

  // ============================================================================
  // EMPLOYEES
  // ============================================================================

  Future<List<Employee>> getAllEmployees() => select(employees).get();

  Future<Employee?> getEmployeeByUsername(String username) => (select(
    employees,
  )..where((tbl) => tbl.username.equals(username))).getSingleOrNull();

  Future<Employee?> getEmployee(String id) =>
      (select(employees)..where((tbl) => tbl.id.equals(id))).getSingleOrNull();

  Future<int> insertEmployee(EmployeesCompanion employee) =>
      into(employees).insert(employee);

  Future<bool> updateEmployee(EmployeesCompanion employee) =>
      update(employees).replace(employee);

  Future<bool> updateEmployeePartial(
    String id,
    EmployeesCompanion employee,
  ) async {
    return await (update(
          employees,
        )..where((tbl) => tbl.id.equals(id))).write(employee) >
        0;
  }

  /// Upsert (insert or update) employee - used for syncing from Supabase
  Future<void> upsertEmployee(Employee employee) async {
    await into(employees).insertOnConflictUpdate(employee);
  }

  Future<int> deleteEmployee(String id) =>
      (delete(employees)..where((tbl) => tbl.id.equals(id))).go();

  Future<bool> deactivateEmployee(String id) async {
    return await (update(employees)..where((tbl) => tbl.id.equals(id))).write(
          const EmployeesCompanion(isActive: Value(false)),
        ) >
        0;
  }

  // ============================================================================
  // ITEMS
  // ============================================================================

  Future<List<Item>> getItemsByLocation(String locationId) =>
      (select(items)..where((tbl) => tbl.locationId.equals(locationId))).get();

  Future<List<Item>> getItemsByLocationAndCategory(
    String locationId,
    String category,
  ) =>
      (select(items)..where(
            (tbl) =>
                tbl.locationId.equals(locationId) &
                tbl.category.equals(category),
          ))
          .get();

  /// Get items for multiple locations (for admins)
  Future<List<Item>> getItemsByLocations(List<String> locationIds) =>
      (select(items)..where((tbl) => tbl.locationId.isIn(locationIds))).get();

  Future<List<Item>> getItemsByLocationsAndCategory(
    List<String> locationIds,
    String category,
  ) =>
      (select(items)..where(
            (tbl) =>
                tbl.locationId.isIn(locationIds) &
                tbl.category.equals(category),
          ))
          .get();

  Future<Item?> getItem(String id) =>
      (select(items)..where((tbl) => tbl.id.equals(id))).getSingleOrNull();

  Future<List<Item>> searchItems(String locationId, String query) =>
      (select(items)..where(
            (tbl) =>
                tbl.locationId.equals(locationId) &
                (tbl.name.contains(query) | tbl.barcode.contains(query)),
          ))
          .get();

  Future<List<Item>> searchItemsByCategory(
    String locationId,
    String category,
    String query,
  ) =>
      (select(items)..where(
            (tbl) =>
                tbl.locationId.equals(locationId) &
                tbl.category.equals(category) &
                (tbl.name.contains(query) | tbl.barcode.contains(query)),
          ))
          .get();

  Future<int> insertItem(ItemsCompanion item) => into(items).insert(item);

  Future<bool> updateItem(ItemsCompanion item) => update(items).replace(item);

  Future<int> updateItemQuantity(String itemId, double newQuantity) =>
      (update(items)..where((tbl) => tbl.id.equals(itemId))).write(
        ItemsCompanion(quantity: Value(newQuantity)),
      );

  // ============================================================================
  // SALES
  // ============================================================================

  Future<List<Sale>> getSalesByLocation(String locationId) =>
      (select(sales)..where((tbl) => tbl.locationId.equals(locationId))).get();

  Future<List<Sale>> getSalesByLocationAndCategory(
    String locationId,
    String category,
  ) =>
      (select(sales)..where(
            (tbl) =>
                tbl.locationId.equals(locationId) &
                tbl.category.equals(category),
          ))
          .get();

  Future<List<Sale>> getSalesByLocations(List<String> locationIds) =>
      (select(sales)..where((tbl) => tbl.locationId.isIn(locationIds))).get();

  Future<List<Sale>> getSalesByLocationsAndCategory(
    List<String> locationIds,
    String category,
  ) =>
      (select(sales)..where(
            (tbl) =>
                tbl.locationId.isIn(locationIds) &
                tbl.category.equals(category),
          ))
          .get();

  Future<List<Sale>> getSuspendedSales(String locationId) =>
      (select(sales)..where(
            (tbl) =>
                tbl.locationId.equals(locationId) &
                tbl.isSuspended.equals(true),
          ))
          .get();

  Future<List<Sale>> getSuspendedSalesByCategory(
    String locationId,
    String category,
  ) =>
      (select(sales)..where(
            (tbl) =>
                tbl.locationId.equals(locationId) &
                tbl.category.equals(category) &
                tbl.isSuspended.equals(true),
          ))
          .get();

  Future<Sale?> getSale(String id) =>
      (select(sales)..where((tbl) => tbl.id.equals(id))).getSingleOrNull();

  Future<int> insertSale(SalesCompanion sale) => into(sales).insert(sale);

  Future<bool> updateSale(SalesCompanion sale) => update(sales).replace(sale);

  Future<int> deleteSale(String id) =>
      (delete(sales)..where((tbl) => tbl.id.equals(id))).go();

  // ============================================================================
  // SALE ITEMS
  // ============================================================================

  Future<List<SaleItem>> getSaleItems(String saleId) =>
      (select(saleItems)..where((tbl) => tbl.saleId.equals(saleId))).get();

  Future<List<SaleItem>> getSaleItemsBySaleIds(List<String> saleIds) =>
      (select(saleItems)..where((tbl) => tbl.saleId.isIn(saleIds))).get();

  Future<int> insertSaleItem(SaleItemsCompanion saleItem) =>
      into(saleItems).insert(saleItem);

  Future<int> deleteSaleItems(String saleId) =>
      (delete(saleItems)..where((tbl) => tbl.saleId.equals(saleId))).go();

  // ============================================================================
  // RECEIVINGS
  // ============================================================================

  Future<List<Receiving>> getReceivingsByLocation(String locationId) => (select(
    receivings,
  )..where((tbl) => tbl.locationId.equals(locationId))).get();

  Future<List<Receiving>> getReceivingsByLocationAndCategory(
    String locationId,
    String category,
  ) =>
      (select(receivings)..where(
            (tbl) =>
                tbl.locationId.equals(locationId) &
                tbl.category.equals(category),
          ))
          .get();

  Future<List<Receiving>> getReceivingsByLocations(List<String> locationIds) =>
      (select(
        receivings,
      )..where((tbl) => tbl.locationId.isIn(locationIds))).get();

  Future<List<Receiving>> getReceivingsByLocationsAndCategory(
    List<String> locationIds,
    String category,
  ) =>
      (select(receivings)..where(
            (tbl) =>
                tbl.locationId.isIn(locationIds) &
                tbl.category.equals(category),
          ))
          .get();

  Future<int> insertReceiving(ReceivingsCompanion receiving) =>
      into(receivings).insert(receiving);

  Future<int> insertReceivingItem(ReceivingItemsCompanion receivingItem) =>
      into(receivingItems).insert(receivingItem);

  // ============================================================================
  // CUSTOMERS
  // ============================================================================

  Future<List<Customer>> getCustomersByLocation(String locationId) => (select(
    customers,
  )..where((tbl) => tbl.locationId.equals(locationId))).get();

  Future<List<Customer>> getCustomersByLocationAndCategory(
    String locationId,
    String category,
  ) =>
      (select(customers)..where(
            (tbl) =>
                tbl.locationId.equals(locationId) &
                tbl.category.equals(category),
          ))
          .get();

  /// Get customers for multiple locations (for admins)
  Future<List<Customer>> getCustomersByLocations(List<String> locationIds) =>
      (select(
        customers,
      )..where((tbl) => tbl.locationId.isIn(locationIds))).get();

  Future<List<Customer>> getCustomersByLocationsAndCategory(
    List<String> locationIds,
    String category,
  ) =>
      (select(customers)..where(
            (tbl) =>
                tbl.locationId.isIn(locationIds) &
                tbl.category.equals(category),
          ))
          .get();

  Future<Customer?> getCustomer(String id) =>
      (select(customers)..where((tbl) => tbl.id.equals(id))).getSingleOrNull();

  Future<List<Customer>> searchCustomers(String locationId, String query) =>
      (select(customers)..where(
            (tbl) =>
                tbl.locationId.equals(locationId) &
                (tbl.firstName.contains(query) | tbl.lastName.contains(query)),
          ))
          .get();

  Future<List<Customer>> searchCustomersByCategory(
    String locationId,
    String category,
    String query,
  ) =>
      (select(customers)..where(
            (tbl) =>
                tbl.locationId.equals(locationId) &
                tbl.category.equals(category) &
                (tbl.firstName.contains(query) | tbl.lastName.contains(query)),
          ))
          .get();

  Future<int> insertCustomer(CustomersCompanion customer) =>
      into(customers).insert(customer);

  Future<bool> updateCustomer(CustomersCompanion customer) =>
      update(customers).replace(customer);

  // ============================================================================
  // CREDITS
  // ============================================================================

  Future<List<Credit>> getCreditsByLocation(String locationId) =>
      (select(credits)
            ..where(
              (tbl) =>
                  tbl.locationId.equals(locationId) &
                  tbl.balance.isBiggerThanValue(0),
            )
            ..orderBy([(tbl) => OrderingTerm.asc(tbl.createdAt)]))
          .get();
  Future<List<Credit>> getCreditsByCustomerAndCategory(
    String customerId,
    String category,
  ) =>
      (select(credits)
            ..where(
              (tbl) =>
                  tbl.customerId.equals(customerId) &
                  tbl.category.equals(category) &
                  tbl.balance.isBiggerThanValue(0),
            )
            ..orderBy([(tbl) => OrderingTerm.asc(tbl.createdAt)]))
          .get();

  Future<List<Credit>> getCreditsByLocationAndCategory(
    String locationId,
    String category,
  ) =>
      (select(credits)
            ..where(
              (tbl) =>
                  tbl.locationId.equals(locationId) &
                  tbl.category.equals(category) &
                  tbl.balance.isBiggerThanValue(0),
            )
            ..orderBy([(tbl) => OrderingTerm.asc(tbl.createdAt)]))
          .get();

  Future<List<Credit>> getCreditsByCustomer(String customerId) =>
      (select(credits)
            ..where(
              (tbl) =>
                  tbl.customerId.equals(customerId) &
                  tbl.balance.isBiggerThanValue(0),
            )
            ..orderBy([(tbl) => OrderingTerm.asc(tbl.createdAt)]))
          .get();

  Future<int> insertCredit(CreditsCompanion credit) =>
      into(credits).insert(credit);

  Future<int> insertCreditPayment(CreditPaymentsCompanion payment) =>
      into(creditPayments).insert(payment);

  Future<bool> updateCredit(CreditsCompanion credit) =>
      update(credits).replace(credit);

  /// Get ALL credits for a customer in a category (including settled ones)
  Future<List<Credit>> getAllCreditsByCustomerAndCategory(
    String customerId,
    String category,
  ) =>
      (select(credits)
            ..where(
              (tbl) =>
                  tbl.customerId.equals(customerId) &
                  tbl.category.equals(category),
            )
            ..orderBy([(tbl) => OrderingTerm.desc(tbl.createdAt)]))
          .get();

  /// Get ALL credits for a location + category (including settled ones)
  Future<List<Credit>> getAllCreditsByLocationAndCategory(
    String locationId,
    String category,
  ) =>
      (select(credits)
            ..where(
              (tbl) =>
                  tbl.locationId.equals(locationId) &
                  tbl.category.equals(category),
            )
            ..orderBy([(tbl) => OrderingTerm.asc(tbl.createdAt)]))
          .get();

  /// Get all payment records for a specific credit
  Future<List<CreditPayment>> getCreditPaymentsByCreditId(String creditId) =>
      (select(creditPayments)
            ..where((tbl) => tbl.creditId.equals(creditId))
            ..orderBy([(tbl) => OrderingTerm.desc(tbl.paidAt)]))
          .get();

  /// Get all payment records for a list of credit IDs
  Future<List<CreditPayment>> getCreditPaymentsByCreditIds(
    List<String> creditIds,
  ) =>
      (select(creditPayments)
            ..where((tbl) => tbl.creditId.isIn(creditIds))
            ..orderBy([(tbl) => OrderingTerm.desc(tbl.paidAt)]))
          .get();

  /// Get all outstanding credits (balance > 0) across all locations
  Future<List<Credit>> getAllOutstandingCredits() =>
      (select(credits)
            ..where((tbl) => tbl.balance.isBiggerThanValue(0))
            ..orderBy([(tbl) => OrderingTerm.asc(tbl.createdAt)]))
          .get();

  // ============================================================================
  // METER READINGS
  // ============================================================================

  Future<int> insertMeterReading(MeterReadingsCompanion reading) =>
      into(meterReadings).insert(reading);

  Future<String?> getLatestMeterReadingType(
    String locationId,
    String employeeId,
    String category,
  ) async {
    final reading =
        await (select(meterReadings)
              ..where(
                (tbl) =>
                    tbl.locationId.equals(locationId) &
                    tbl.employeeId.equals(employeeId) &
                    tbl.category.equals(category),
              )
              ..orderBy([(tbl) => OrderingTerm.desc(tbl.timestamp)])
              ..limit(1))
            .getSingleOrNull();
    return reading?.readingType;
  }

  // ============================================================================
  // AUDIT LOGS
  // ============================================================================

  Future<int> insertAuditLog(AuditLogsCompanion log) =>
      into(auditLogs).insert(log);

  // ============================================================================
  // SYNC STATUS
  // ============================================================================

  Future<List<DbSyncQueue>> getUnsyncedRecords() =>
      (select(syncQueue)..where((tbl) => tbl.isSynced.equals(false))).get();

  Future<int> markAsSynced(String id) =>
      (update(syncQueue)..where((tbl) => tbl.id.equals(id))).write(
        SyncQueueCompanion(isSynced: Value(true)),
      );
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'lucasa_pos.db'));
    return NativeDatabase.createInBackground(file);
  });
}
