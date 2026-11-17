import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:drift/drift.dart' as drift;
import '../data/database/app_database.dart';
import 'connectivity_service.dart';

class LogoService {
  final SupabaseClient _supabase;
  final ConnectivityService _connectivityService;
  final ImagePicker _picker = ImagePicker();
  
  static const String bucketName = 'config-files';
  
  LogoService(this._supabase, this._connectivityService);
  
  /// Pick logo from gallery
  Future<XFile?> pickLogo() async {
    try {
      debugPrint('📸 Opening image picker...');
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      
      if (image != null) {
        debugPrint('✅ Image selected: ${image.path}');
      } else {
        debugPrint('⚠️ No image selected');
      }
      
      return image;
    } catch (e) {
      debugPrint('❌ Error picking logo: $e');
      return null;
    }
  }
  
  /// Save logo locally and upload to Supabase if online
  Future<Map<String, String?>> saveLogoForLocation({
    required String locationId,
    required XFile imageFile,
    required AppDatabase db,
  }) async {
    try {
      // Save to local app directory
      final appDir = await getApplicationDocumentsDirectory();
      final logosDir = Directory(p.join(appDir.path, 'logos'));
      if (!await logosDir.exists()) {
        await logosDir.create(recursive: true);
      }
      
      // Generate unique filename
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final extension = p.extension(imageFile.path);
      final fileName = 'logo_${locationId}_$timestamp$extension';
      final localPath = p.join(logosDir.path, fileName);
      
      // Copy file to local storage
      await File(imageFile.path).copy(localPath);
      debugPrint('✅ Logo saved locally: $localPath');
      
      String? supabaseUrl;
      
      // Try to upload to Supabase if online
      if (_connectivityService.hasConnection) {
        supabaseUrl = await _uploadToSupabase(localPath, fileName);
      }
      
      return {
        'localPath': localPath,
        'supabaseUrl': supabaseUrl,
      };
    } catch (e) {
      debugPrint('❌ Error saving logo: $e');
      rethrow;
    }
  }
  
  /// Upload logo to Supabase storage
  Future<String?> _uploadToSupabase(String localPath, String fileName) async {
    try {
      final file = File(localPath);
      final bytes = await file.readAsBytes();
      
      // Upload to config-files bucket
      await _supabase.storage.from(bucketName).uploadBinary(
        fileName,
        bytes,
        fileOptions: const FileOptions(
          cacheControl: '3600',
          upsert: true,
        ),
      );
      
      // Get public URL
      final url = _supabase.storage.from(bucketName).getPublicUrl(fileName);
      debugPrint('✅ Logo uploaded to Supabase: $url');
      
      return url;
    } catch (e) {
      debugPrint('❌ Error uploading to Supabase: $e');
      return null;
    }
  }
  
  /// Sync pending logos to Supabase
  Future<void> syncPendingLogos(AppDatabase db) async {
    if (!_connectivityService.hasConnection) {
      debugPrint('⚠️ No connection, skipping logo sync');
      return;
    }
    
    try {
      // Get all locations with local logo but no Supabase URL
      final locations = await db.getAllLocations();
      
      for (final location in locations) {
        if (location.logoLocalPath != null && 
            location.logoLocalPath!.isNotEmpty &&
            (location.logoUrl == null || location.logoUrl!.isEmpty)) {
          
          final file = File(location.logoLocalPath!);
          if (await file.exists()) {
            final fileName = p.basename(location.logoLocalPath!);
            final supabaseUrl = await _uploadToSupabase(location.logoLocalPath!, fileName);
            
            if (supabaseUrl != null) {
              // Update location with Supabase URL
              await db.updateLocation(
                location.id,
                LocationsCompanion(
                  logoUrl: drift.Value(supabaseUrl),
                ),
              );
              debugPrint('✅ Synced logo for location: ${location.name}');
            }
          }
        }
      }
    } catch (e) {
      debugPrint('❌ Error syncing logos: $e');
    }
  }
  
  /// Get logo file (local or from URL)
  Future<File?> getLogoFile(Location location) async {
    // Try local path first
    if (location.logoLocalPath != null && location.logoLocalPath!.isNotEmpty) {
      final file = File(location.logoLocalPath!);
      if (await file.exists()) {
        return file;
      }
    }
    
    // If online and has Supabase URL, download it
    if (_connectivityService.hasConnection && 
        location.logoUrl != null && 
        location.logoUrl!.isNotEmpty) {
      try {
        final appDir = await getApplicationDocumentsDirectory();
        final logosDir = Directory(p.join(appDir.path, 'logos'));
        if (!await logosDir.exists()) {
          await logosDir.create(recursive: true);
        }
        
        final fileName = p.basename(location.logoUrl!);
        final localPath = p.join(logosDir.path, fileName);
        final file = File(localPath);
        
        // Download from Supabase if not already cached
        if (!await file.exists()) {
          final bytes = await _supabase.storage.from(bucketName).download(fileName);
          await file.writeAsBytes(bytes);
        }
        
        return file;
      } catch (e) {
        debugPrint('❌ Error downloading logo: $e');
      }
    }
    
    return null;
  }
}
