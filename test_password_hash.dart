// Quick test to verify password hash computation
// Run this with: dart run test_password_hash.dart

import 'dart:convert';
import 'package:crypto/crypto.dart';

void main() {
  // Test different possible passwords
  final testCases = [
    'SuperAdmin@2026!',
    'superadmin@2026!',
    'SuperAdmin@2026',
    'SuperAdmin2026!',
    'SuperAdmin@2026! ', // with trailing space
    ' SuperAdmin@2026!', // with leading space
  ];
  
  print('='.padRight(80, '='));
  print('PASSWORD HASH VERIFICATION TEST');
  print('='.padRight(80, '='));
  print('');
  
  for (final password in testCases) {
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    final hash = digest.toString();
    
    print('Password: "${password}" (${password.length} chars)');
    print('Hash:     $hash');
    print('');
  }
  
  print('='.padRight(80, '='));
  print('EXPECTED HASH FOR CORRECT PASSWORD:');
  print('d5d9bdd777d6e8e320a6bf4973ba7dd331ff0bbb7e3fc791782ff3325db101eb');
  print('='.padRight(80, '='));
  print('');
  print('INSTRUCTIONS:');
  print('1. Run the Flutter app: flutter run');
  print('2. Try to login with username: superadmin');
  print('3. Check the console output for these two lines:');
  print('   🔑 Computed hash: [hash from password you typed]');
  print('   🔑 Stored hash:   [hash from Supabase database]');
  print('4. Compare both hashes with the expected hash above');
  print('');
  print('This will tell you:');
  print('  - If "Computed hash" != expected: You typed the wrong password');
  print('  - If "Stored hash" != expected: Database has wrong hash (run SQL fix)');
  print('='.padRight(80, '='));
}
