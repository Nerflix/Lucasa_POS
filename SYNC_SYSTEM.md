# Sync System with Real Time Implementation

## Overview
The app now has a comprehensive synchronization system that:
1. **Requires internet connection for login** - Ensures fresh data on every login
2. Works offline after login - Application functions without internet
3. Auto-syncs when internet connects - Immediate sync when connection detected
4. Scheduled syncs at 7 AM & 9 PM - Uses accurate internet time (not device clock)

## Key Components

### 1. TimeService (`lib/services/time_service.dart`)
Purpose: Obtain accurate time from the internet to prevent issues with incorrect device clocks

Features:
- Fetches real time from World Time API
- Calculates device time offset (difference between real time and device time)
- Caches offset for offline use
- Detects device timezone (UTC+X format)
- Checks if current time is within scheduled sync windows (7 AM or 9 PM)
- Calculates next scheduled sync time

Key Methods:
- getRealTime() - Fetches current time from internet
- getCurrentTime() - Gets current time using cached offset (fast, no network call)
- getDeviceTimezone() - Returns device timezone as string
- isScheduledSyncTime() - Checks if current time is within 7 AM or 9 PM window
- getNextScheduledSyncTime() - Calculates when next sync should happen
- syncTimeOffset() - Updates time offset from internet (every 6 hours)

How It Works:
```dart
// On first login or when needed
await timeService.getRealTime(); // Fetches from internet
// Returns: 2026-02-05 14:30:00 (real time)
// Device shows: 2026-02-05 16:45:00 (incorrect)
// Offset calculated: -2h 15m
// Cached to local storage

// Later, quick time check (no network)
final now = timeService.getCurrentTime();
// Returns: Device time + offset = Real time
```

### 2. Enhanced SyncService (`lib/services/sync_service.dart`)
**Purpose**: Manage all data synchronization

**New Features**:
- Monitors for scheduled sync times (every minute check)
- Uses real internet time instead of device clock
- Prevents duplicate syncs in same window (10-minute buffer)
- Syncs time offset before each data sync
- Notifies listeners when sync status changes

**Sync Triggers**:
1. **Manual** - User clicks sync button
2. **Connectivity** - Internet connection restored
3. **Scheduled** - 7:00 AM or 9:00 PM (based on real time)

**Scheduled Sync Logic**:
```dart
Every minute:
  1. Check if online
  2. Fetch real time from internet
  3. Check if hour is 7 (7:00-7:05 AM) or 21 (9:00-9:05 PM)
  4. Check if already synced in this window (last 10 minutes)
  5. If all pass → Trigger sync
  6. Mark window as done (prevents duplicate syncs)
```

**Sync Flow**:
```
Login (requires internet)
    ↓
Sync time offset
    ↓
Work offline (local SQLite)
    ↓
Internet connects → Auto-sync
    OR
7 AM / 9 PM → Scheduled sync
    ↓
Sync: Employees → Locations → Items → Sales → Receivings → Customers → Credits → Meter Readings → Audit Logs
```

### 3. Enhanced AuthService (`lib/services/auth_service.dart`)
**Changes**:
- **REQUIRES internet for login** (removed offline fallback)
- Fetches employee from Supabase (cloud database)
- Verifies password against cloud
- Checks if account is active
- Updates local database with latest data
- Blocks login with message if offline

**Login Flow**:
```
User enters credentials
    ↓
Try to fetch from Supabase
    ↓
Success → Verify password → Check active → Update local DB → Login
    ↓
Network error → Show "Internet connection required" → Block login
```

### 4. SyncStatusWidget (`lib/widgets/sync_status_widget.dart`)
**Purpose**: Visual sync status display for dashboards

**Shows**:
- Online/Offline status (cloud icon)
- Last sync time ("2h ago", "Just now", etc.)
- Next scheduled sync ("in 5h 30m")
- Device timezone ("UTC+3")
- Sync button (manual trigger)
- Auto-sync info message

**Usage**:
```dart
// In any dashboard
SyncStatusWidget() // Full details
SyncStatusWidget(showDetails: false) // Compact version
```

## Configuration

### Scheduled Sync Times
Configured in `TimeService.isScheduledSyncTime()`:
- **Morning**: 7:00 AM - 7:05 AM
- **Evening**: 9:00 PM - 9:05 PM (21:00 - 21:05)

Change times by modifying the hour values:
```dart
if (hour == 7 && minute < 5) return true;  // 7 AM
if (hour == 21 && minute < 5) return true; // 9 PM
```

### Time Sync Frequency
Time offset syncs every **6 hours** (prevents constant network calls)

Change in `TimeService.shouldSyncTime()`:
```dart
return hoursSinceSync >= 6; // Change to 12 for 12 hours, etc.
```

### Sync Window Buffer
Scheduled syncs have **10-minute buffer** to prevent duplicates

Change in `SyncService._checkScheduledSync()`:
```dart
if (minutesSinceLastSync < 10) return; // Change to 5, 15, etc.
```

## Dependencies Added

### pubspec.yaml
```yaml
dependencies:
  http: ^1.0.0              # For fetching real time from World Time API
  shared_preferences: ^2.0.0 # For caching time offset locally
```

Install with:
```bash
flutter pub get
```

## Files Modified/Created

### New Files:
1. `lib/services/time_service.dart` - Real time fetching
2. `lib/widgets/sync_status_widget.dart` - UI component

### Modified Files:
1. `lib/services/sync_service.dart` - Added scheduled sync logic
2. `lib/services/auth_service.dart` - Made login require internet
3. `lib/main.dart` - Added TimeService initialization
4. `pubspec.yaml` - Added dependencies

## How It Solves the Problems

### Problem 1: Wrong Device Clock
**Solution**: Fetches real time from World Time API
```
Device shows: 2:00 PM (wrong)
Real time from internet: 4:30 PM
Offset: +2h 30m (cached)
All scheduled syncs use: Device time + offset = Real time
```

### Problem 2: Offline Deleted Employees Still Login
**Solution**: Login REQUIRES internet
- Employee deleted on Device A
- Employee tries to login on Device B
- Device B must connect to internet
- Supabase returns is_active = false
- Login blocked immediately

### Problem 3: Manual Sync Dependency
**Solution**: Three automatic sync triggers
1. Internet connects → Immediate sync
2. 7 AM (real time) → Scheduled sync
3. 9 PM (real time) → Scheduled sync

### Problem 4: Different Timezones
**Solution**: World Time API returns timezone-aware time
- API uses IP geolocation
- Returns: datetime + timezone info
- Converts to device timezone automatically
- All users in same physical location sync at same real time

## Testing

### Test Real Time Sync
```dart
final timeService = TimeService();
final realTime = await timeService.getRealTime();
print('Real time: $realTime');
print('Device time: ${DateTime.now()}');
print('Offset: ${timeService._deviceTimeOffset}');
```

### Test Scheduled Sync (Manual)
Change scheduled time to current hour for testing:
```dart
// In time_service.dart, temporarily change:
if (hour == DateTime.now().hour && minute < 5) return true;
// Wait a minute, sync should trigger
```

### Test Offline Login Block
1. Turn off internet
2. Try to login
3. Should see: "Internet connection required to login..."

## Production Checklist

- [ ] Run `flutter pub get`
- [ ] Test login with internet (should work)
- [ ] Test login without internet (should fail with message)
- [ ] Verify time offset syncs on first run
- [ ] Confirm auto-sync on connection
- [ ] Wait for 7 AM or 9 PM to test scheduled sync
- [ ] Check timezone detection matches device
- [ ] Verify sync status widget displays correctly
- [ ] Test manual sync button
- [ ] Confirm last sync time updates

## Monitoring

### Console Logs to Watch:
```
✅ Real time fetched: 2026-02-05 14:30:00 (Timezone: Africa/Nairobi)
⏰ Device offset: -135 minutes
📶 Internet connected - triggering auto-sync
⏰ Scheduled sync time reached: 7:00
✅ Time offset synced successfully
🔄 Starting sync: Scheduled sync at 7:00
✅ Sync completed successfully
```

### Warning Logs:
```
⚠️ WARNING: Using device time - may be inaccurate!
⚠️ Failed to fetch real time from World Time API: [error]
❌ Online verification required but failed: [error]
```

## Future Enhancements

1. **Multiple Time Sources**: Fallback to NTP servers if World Time API fails
2. **Sync Conflict Resolution**: Smart merge when data conflicts
3. **Bandwidth Optimization**: Only sync changed records
4. **Background Sync**: Use Flutter background services for syncing when app closed
5. **Sync Logs**: Track all sync operations for debugging

## Notes

- **First login after update**: Will take few seconds to fetch real time
- **Time offset caching**: Survives app restarts (stored in SharedPreferences)
- **Timezone changes**: Detected automatically on next time sync
- **Battery impact**: Minimal (checks every minute are very lightweight)
- **Data usage**: ~5KB per time sync, ~varies per data sync
