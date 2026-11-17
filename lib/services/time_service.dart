import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Service to get real time from internet (not device clock)
/// Prevents issues with wrong device time settings
class TimeService {
  static const String _lastSyncTimeKey = 'last_real_time_sync';
  static const String _timeOffsetKey = 'device_time_offset';
  
  Duration? _deviceTimeOffset; // Difference between real time and device time

  // List of reliable time APIs, with HTTPS for security
  final List<String> _timeApis = [
    'https://worldtimeapi.org/api/ip',
    'https://timeapi.io/api/Time/current/zone?timeZone=Etc/UTC', // Fallback
  ];
  
  /// Get real current time from internet
  Future<DateTime> getRealTime() async {
    for (var apiUrl in _timeApis) {
      try {
        final response = await http.get(Uri.parse(apiUrl)).timeout(const Duration(seconds: 5));
        
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          DateTime? realTime;

          // Adapt to different API response structures
          if (data.containsKey('datetime')) { // worldtimeapi.org
            realTime = DateTime.parse(data['datetime']);
          } else if (data.containsKey('dateTime')) { // timeapi.io
            realTime = DateTime.parse(data['dateTime']);
          }

          if (realTime != null) {
            _deviceTimeOffset = realTime.difference(DateTime.now());
            await _cacheTimeOffset(_deviceTimeOffset!);

            print('✅ Real time fetched from $apiUrl: $realTime');
            return realTime;
          }
        }
      } catch (e) {
        print('⚠️ Failed to fetch real time from $apiUrl: $e');
        // Try the next API in the list
      }
    }
    
    // If all APIs fail, use fallback methods
    print('⚠️ All time APIs failed. Using fallback.');
    return _getFallbackTime();
  }

  /// Fallback method to get time if all APIs fail
  Future<DateTime> _getFallbackTime() async {
    // Try to load a cached offset
    final cachedOffset = await _loadCachedTimeOffset();
    if (cachedOffset != null) {
      _deviceTimeOffset = cachedOffset;
      print('⏰ Using cached time offset: ${_deviceTimeOffset!.inMinutes} minutes');
      return DateTime.now().add(cachedOffset);
    }
    
    // Last resort: use device time with a clear warning
    print('🚨 CRITICAL: Using device time - may be inaccurate!');
    return DateTime.now();
  }
  
  /// Get current time (uses cached offset if available)
  DateTime getCurrentTime() {
    if (_deviceTimeOffset != null) {
      return DateTime.now().add(_deviceTimeOffset!);
    }
    return DateTime.now(); // Fallback to device time
  }
  
  /// Get timezone from device
  String getDeviceTimezone() {
    return DateTime.now().timeZoneName;
  }
  
  /// Check if we need to sync time (every 6 hours)
  Future<bool> shouldSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    final lastSyncStr = prefs.getString(_lastSyncTimeKey);
    
    if (lastSyncStr == null) return true; // Never synced
    
    final lastSync = DateTime.parse(lastSyncStr);
    final hoursSinceSync = DateTime.now().difference(lastSync).inHours;
    
    return hoursSinceSync >= 6;
  }
  
  /// Update time offset from internet
  Future<void> syncTimeOffset() async {
    try {
      await getRealTime(); // This will fetch and cache the new offset
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastSyncTimeKey, DateTime.now().toIso8601String());
      print('✅ Time offset synced successfully');
    } catch (e) {
      print('⚠️ Failed to sync time offset: $e');
    }
  }
  
  /// Cache time offset to local storage
  Future<void> _cacheTimeOffset(Duration offset) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_timeOffsetKey, offset.inSeconds);
  }
  
  /// Load cached time offset from local storage
  Future<Duration?> _loadCachedTimeOffset() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final offsetSeconds = prefs.getInt(_timeOffsetKey);
      
      if (offsetSeconds != null) {
        return Duration(seconds: offsetSeconds);
      }
    } catch (e) {
      print('⚠️ Failed to load cached time offset: $e');
    }
    return null;
  }
  
  /// Check if current time is within a scheduled sync window
  bool isScheduledSyncTime(DateTime time) {
    final hour = time.hour;
    return (hour == 7 || hour == 21); // Simplified to check the hour
  }
  
  /// Get next scheduled sync time
  DateTime getNextScheduledSyncTime(DateTime currentTime) {
    final now = currentTime;
    final today7AM = DateTime(now.year, now.month, now.day, 7, 0);
    final today9PM = DateTime(now.year, now.month, now.day, 21, 0);
    
    if (now.isBefore(today7AM)) return today7AM;
    if (now.isBefore(today9PM)) return today9PM;
    
    return DateTime(now.year, now.month, now.day + 1, 7, 0); // Tomorrow at 7 AM
  }
}
