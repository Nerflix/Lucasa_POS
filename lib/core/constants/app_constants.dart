/// Application-wide constants
class AppConstants {
  // User roles
  static const String roleSuperAdmin = 'super_admin';
  static const String roleAdmin = 'admin';
  static const String roleEmployee = 'employee';
  
  // Payment methods
  static const String paymentCash = 'Cash';
  static const String paymentMpesa = 'Mpesa Till';
  static const String paymentEquity = 'Equity Paybill';
  static const String paymentCredit = 'Credit';
  
  // Business categories
  static const String categoryFillingStation = 'Filling Station';
  static const String categoryCarSale = 'Car Sale';
  
  // Pump types
  static const String pumpTypeAGO = 'AGO';
  static const String pumpTypePMS = 'PMS';
  
  // Meter reading types
  static const String readingTypeOpening = 'opening';
  static const String readingTypeClosing = 'closing';
  
  // Pricing types
  static const String pricingRetail = 'retail';
  static const String pricingWholesale = 'wholesale';
  
  // Sync settings
  static const Duration syncRetryInterval = Duration(minutes: 15);
  static const Duration syncCheckMorning = Duration(hours: 7);
  static const Duration syncCheckEvening = Duration(hours: 21);
  
  // Audit log actions
  static const String auditSaleDeleted = 'sale_deleted';
  static const String auditSaleEdited = 'sale_edited';
  static const String auditItemAdded = 'item_added';
  static const String auditItemEdited = 'item_edited';
  static const String auditEmployeeAdded = 'employee_added';
  
  // Date formats
  static const String dateFormatDisplay = 'MMM dd, yyyy';
  static const String dateTimeFormatDisplay = 'MMM dd, yyyy HH:mm';
  static const String dateFormatSaleId = 'yyyyMMdd-HHmmss';
  
  // Hard-coded Super Admin credentials (not stored in database)
  static const String superAdminUsername = 'superadmin';
  static const String superAdminPassword = 'SuperAdmin@2026!';
  static const String superAdminEmail = 'superadmin@lucasa.pos';
}
