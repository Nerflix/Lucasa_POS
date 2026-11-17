import 'dart:convert';
import 'package:crypto/crypto.dart';

void main() {
  // This is the exact password from app_constants.dart
  const password = 'SuperAdmin@2026!';
  
  // This matches the _hashPassword function in auth_service.dart
  final bytes = utf8.encode(password);
  final digest = sha256.convert(bytes);
  final hash = digest.toString();
  
  print('='.padRight(80, '='));
  print('PASSWORD HASH VERIFICATION');
  print('='.padRight(80, '='));
  print('Password:  $password');
  print('SHA-256:   $hash');
  print('='.padRight(80, '='));
  print('');
  print('This is the EXACT hash that should be in your database for SuperAdmin.');
  print('');
  print('To verify, run this query in Supabase SQL Editor:');
  print('');
  print("SELECT id, username, password_hash FROM employees WHERE username = 'superadmin';");
  print('');
  print('If the hash does NOT match, run this in Supabase SQL Editor to fix it:');
  print('');
  print("UPDATE employees SET password_hash = '$hash' WHERE username = 'superadmin';");
  print('='.padRight(80, '='));
}
