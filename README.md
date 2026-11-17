<<<<<<< HEAD
# Lucasa POS - Point of Sale System

A comprehensive Flutter-based Point of Sale system with offline-first architecture using SQLite for local operations and Supabase for cloud backup.

## 🎯 Project Overview

Lucasa POS is a hybrid mobile application designed for retail operations, with specific support for:
- **Car Sale** businesses
- **Filling Stations** (petrol stations)
- Multi-location management
- Offline-first operations
- Automatic cloud backup

## 🏗️ Architecture

### Hybrid Database System
```
┌─────────────────────────────────────┐
│      LOCAL (SQLite via Drift)       │
│   - Day-to-day operations           │
│   - 100% offline capable            │
│   - Real-time performance           │
└──────────────┬──────────────────────┘
               │
               │ Auto-sync when online
               ▼
┌─────────────────────────────────────┐
│    CLOUD (Supabase PostgreSQL)      │
│   - Backup and recovery             │
│   - Cross-location reporting        │
│   - Admin dashboards                │
└─────────────────────────────────────┘
```

## Setup Instructions

### Prerequisites
- Flutter SDK (>=3.10.8)
- Android Studio or VS Code
- Supabase account

### 1. Clone and Install Dependencies

```bash
cd d:\Lucasa_POS\lucasa_pos
flutter pub get
```

### 2. Generate Database Code

```bash
dart run build_runner build --delete-conflicting-outputs
```

### 3. Supabase Setup

#### A. Create Supabase Project
1. Go to [https://supabase.com](https://supabase.com)
2. Create a new project (already created: https://ofgjgslucmyizkbgtzaj.supabase.co)

#### B. Run SQL Schema
1. Open Supabase SQL Editor
2. Copy contents of `supabase_schema.sql`
3. Run the script to create all tables and indexes

#### C. Create Storage Buckets
1. Go to Supabase Storage
2. Create two public buckets:
   - `config-files` (for shop logos)
   - `receipts` (for receipt PDFs)
3. Set both buckets to public access

### 4. Configuration

Supabase credentials are configured in:
- `lib/core/config/supabase_config.dart`
- URL: https://ofgjgslucmyizkbgtzaj.supabase.co
- Keys: See config file

### 5. Run the Application

```bash
flutter run
```

## Features Implemented

### Core Infrastructure (Completed)

1. Supabase Integration
   - Connection service with authentication
   - File upload to storage buckets
   - Real-time sync capability

2. Local SQLite Database
   - 13 tables covering all business operations
   - Type-safe ORM using Drift
   - Automatic schema generation

3. Authentication System
   - 3-tier roles: Super Admin, Admin, Employee
   - Hard-coded Super Admin credentials
   - Password hashing with SHA256
   - Offline login support

4. Sync Service
   - Automatic sync when internet detected
   - Incremental uploads (only unsynced data)
   - Background sync monitoring
   - Manual sync trigger

5. Connectivity Monitoring
   - Real-time internet status
   - Automatic sync on connection
   - Offline mode support

### Database Tables Created

- locations - Shop/location configuration
- employees - User accounts and permissions
- items - Inventory management
- sales - Sales transactions
- sale_items - Individual items in sales
- receivings - Restocking operations
- receiving_items - Items in receivings
- customers - Customer records
- credits - Customer debts
- credit_payments - Payment history
- meter_readings - Filling station pump readings
- audit_logs - Edit/delete tracking
- sync_status - Sync queue management

### Services Created

- SupabaseService - Cloud backend operations
- ConnectivityService - Internet monitoring
- SyncService - Data synchronization
- AuthService - Authentication & permissions

## Super Admin Login

Username: `superadmin`
Password: `SuperAdmin@2026!`

The Super Admin account is hard-coded and not stored in any database for security.

## Next Steps

### To Be Implemented

1. Login Page UI
   - Username/password fields
   - Failed login handling (3 attempts)
   - Password reset request
   - Category selection (Filling Station / Car Sale)

2. Configuration Page
   - Location management
   - Logo upload
   - Pump setup for filling stations

3. Employee Management
   - Add/edit employees
   - Location assignment
   - Permission management

4. Sales Module
   - Sales page with item search
   - Retail/wholesale pricing toggle
   - Payment method selection
   - Receipt printing

5. Inventory Module
   - Add items
   - Receiving items (restocking)
   - Stock tracking

6. Reports Module
   - Sales reports (summary, graphical, detailed)
   - Profit/loss reports
   - Inventory reports
   - Receivings reports
   - Deleted/edited sales audit

7. Filling Station Specific
   - Meter reading entry (A, L, T values)
   - Opening/closing readings
   - Stop all sales functionality

8. Credits Management
   - Customer credit tracking
   - Payment recording
   - Balance management

## Project Structure

```
lib/
├── core/
│   ├── config/
│   │   └── supabase_config.dart      # Supabase credentials
│   └── constants/
│       └── app_constants.dart        # App-wide constants
├── data/
│   ├── database/
│   │   ├── app_database.dart         # Drift database schema
│   │   └── app_database.g.dart       # Generated code
│   └── models/                       # Data models (future)
├── features/
│   └── auth/                         # Authentication UI (future)
├── services/
│   ├── supabase_service.dart        # Supabase operations
│   ├── connectivity_service.dart    # Internet monitoring
│   ├── sync_service.dart            # Data sync
│   └── auth_service.dart            # Authentication
├── utils/                           # Helper utilities (future)
└── main.dart                        # App entry point
```

## Development Commands

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
dart run build_runner watch
flutter run
flutter build apk --release
flutter build appbundle --release
```

## Technology Stack

### Frontend
- Flutter - Cross-platform framework
- Dart - Programming language
- Provider - State management
- Material Design 3 - UI components

### Local Database
- SQLite - Local database
- Drift - Type-safe SQL ORM
- path_provider - Database file location

### Cloud Backend
- Supabase - Backend as a Service
  - PostgreSQL database
  - Authentication
  - Storage (file uploads)
  - Real-time subscriptions

### Utilities
- connectivity_plus - Internet monitoring
- uuid - Unique ID generation
- crypto - Password hashing
- intl - Date formatting
- fl_chart - Charts and graphs
- blue_thermal_printer - Receipt printing

## Security Features

1. Password Hashing - SHA256 encryption
2. Row Level Security - Supabase RLS policies
3. Hard-coded Super Admin - Not in database
4. Location Isolation - Users only see assigned locations
5. Audit Logging - Track all changes

## Offline Support

- All operations work offline
- Automatic sync when internet available
- Persistent sync reminders (7 AM and 9 PM)
- Manual sync button
- Background sync service
- 15-minute retry intervals

## License

Private project for Lucasa POS.

## Support

For questions or issues, contact the project administrator.

---

Status: Core infrastructure complete - Ready for UI development

=======
# Lucasa_POS
Lucasa POS is a cross-platform point-of-sale system designed for retail and small businesses. Built with Flutter, it supports Android, iOS, Windows, macOS, Linux, and web. The project integrates with Supabase for backend services, features robust location and sales management, and includes audit logging for security and compliance. 

