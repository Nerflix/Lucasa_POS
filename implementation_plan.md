# Fix Build Errors Implementation Plan

## Goal Description
The goal is to fix the current build errors preventing the application from running. This includes adding the missing `fl_chart` dependency, fixing a constructor error in `Location` model usage, and implementing the missing `syncEmployeesToAuth` method in `AuthService`.

## User Review Required
> [!IMPORTANT]
> I will be using the `SupabaseConfig.supabaseSecretKey` to create a temporary admin client for syncing employees to Supabase Auth. This key should be kept secure.

## Proposed Changes

### Configuration
#### [MODIFY] [pubspec.yaml](file:///d:/Lucasa_POS/lucasa_pos/pubspec.yaml)
- Add `fl_chart: ^0.69.0` (or compatible version) to `dependencies`.

### Features
#### [MODIFY] [employee_detail_page.dart](file:///d:/Lucasa_POS/lucasa_pos/lib/features/employees/employee_detail_page.dart)
- Update `Location` constructor usage in `_getAssignedLocationNames` to include the required `isActive` parameter (defaulting to `true` or `false` as appropriate for a fallback object).

### Services
#### [MODIFY] [auth_service.dart](file:///d:/Lucasa_POS/lucasa_pos/lib/services/auth_service.dart)
- Implement `syncEmployeesToAuth` method.
- This method will:
    1.  Initialize a `SupabaseClient` with the service role key.
    2.  Fetch all employees from the database.
    3.  Iterate through employees and create a Supabase Auth user for each using `admin.createUser`.
    4.  Set the default password to `Change@123`.
    5.  Handle exceptions (e.g., user already exists) gracefully.

## Verification Plan

### Automated Tests
- Run `flutter pub get` to verify dependencies.
- Run `flutter build apk --debug` (or `assembleDebug`) to verify compilation.

### Manual Verification
- Launch the app on the device.
- Navigate to the Reports page to verify `fl_chart` works.
- Navigate to the Employee list and open the "Sync Auth Users" dialog (if accessible/visible) to verify the method logic (or trigger it manually).
- Check `EmployeeDetailPage` by opening an employee's details.
