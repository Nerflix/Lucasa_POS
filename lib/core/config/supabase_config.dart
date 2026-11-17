/// Supabase Configuration
/// Contains connection details and credentials for Supabase cloud backend
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Supabase Configuration
/// Loads connection details and credentials from environment variables
class SupabaseConfig {
  static String get supabaseUrl => dotenv.env['SUPABASE_URL'] ?? '';
  static String get supabasePublishableKey => dotenv.env['SUPABASE_PUBLISHABLE_KEY'] ?? '';
  static String get supabaseSecretKey => dotenv.env['SUPABASE_SECRET_KEY'] ?? '';
  static String get configBucketName => dotenv.env['CONFIG_BUCKET_NAME'] ?? '';
  static String get receiptsBucketName => dotenv.env['RECEIPTS_BUCKET_NAME'] ?? '';
}
