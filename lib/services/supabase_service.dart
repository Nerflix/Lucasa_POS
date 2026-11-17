import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/config/supabase_config.dart';

/// Service for managing Supabase connection and operations
class SupabaseService {
  static SupabaseService? _instance;
  static SupabaseClient? _client;
  
  SupabaseService._();
  
  /// Get singleton instance
  static SupabaseService get instance {
    _instance ??= SupabaseService._();
    return _instance!;
  }
  
  /// Get Supabase client
  SupabaseClient get client {
    if (_client == null) {
      throw Exception('Supabase not initialized. Call initialize() first.');
    }
    return _client!;
  }
  
  /// Initialize Supabase connection
  Future<void> initialize() async {
    await Supabase.initialize(
      url: SupabaseConfig.supabaseUrl,
      anonKey: SupabaseConfig.supabasePublishableKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
    );
    
    _client = Supabase.instance.client;
    print('✅ Supabase initialized successfully');
  }
  
  /// Check if user is authenticated
  bool get isAuthenticated => _client?.auth.currentUser != null;
  
  /// Get current user
  User? get currentUser => _client?.auth.currentUser;
  
  /// Sign in with email and password
  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    return await client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }
  
  /// Sign up new user
  Future<AuthResponse> signUp({
    required String email,
    required String password,
    Map<String, dynamic>? data,
  }) async {
    return await client.auth.signUp(
      email: email,
      password: password,
      data: data,
    );
  }
  
  /// Sign out
  Future<void> signOut() async {
    await client.auth.signOut();
  }
  
  /// Update password for current user
  Future<void> updatePassword(String newPassword) async {
    await client.auth.updateUser(
      UserAttributes(password: newPassword),
    );
  }
  
  /// Upload file to storage
  Future<String> uploadFile({
    required String bucketName,
    required String path,
    required List<int> fileBytes,
    String? contentType,
  }) async {
    await client.storage.from(bucketName).uploadBinary(
      path,
      Uint8List.fromList(fileBytes),
      fileOptions: FileOptions(
        contentType: contentType,
        upsert: true,
      ),
    );
    
    // Get public URL
    final publicUrl = client.storage.from(bucketName).getPublicUrl(path);
    return publicUrl;
  }
  
  /// Create storage bucket if it doesn't exist
  Future<void> createBucketIfNotExists(String bucketName) async {
    try {
      await client.storage.createBucket(
        bucketName,
        const BucketOptions(
          public: true,
        ),
      );
      print('✅ Created bucket: $bucketName');
    } catch (e) {
      // Bucket might already exist
      if (e.toString().contains('already exists')) {
        print('ℹ️ Bucket already exists: $bucketName');
      } else {
        print('❌ Error creating bucket: $e');
        rethrow;
      }
    }
  }
  
  /// Sync data to Supabase table
  Future<void> syncToTable({
    required String tableName,
    required List<Map<String, dynamic>> data,
  }) async {
    if (data.isEmpty) return;
    
    try {
      await client.from(tableName).upsert(data);
      print('✅ Synced ${data.length} records to $tableName');
    } catch (e) {
      print('❌ Error syncing to $tableName: $e');
      rethrow;
    }
  }
  
  /// Fetch data from Supabase table
  Future<List<Map<String, dynamic>>> fetchFromTable({
    required String tableName,
    String? locationId,
    Map<String, dynamic>? filters,
  }) async {
    try {
      PostgrestFilterBuilder query = client.from(tableName).select();
      
      if (locationId != null) {
        query = query.eq('location_id', locationId);
      }
      
      if (filters != null) {
        filters.forEach((key, value) {
          query = query.eq(key, value);
        });
      }
      
      final response = await query;
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error fetching from $tableName: $e');
      rethrow;
    }
  }
}
