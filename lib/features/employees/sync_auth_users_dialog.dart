import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../core/theme/app_theme.dart';

/// Dialog to sync existing employees to Supabase Auth
/// This creates auth users for employees that don't have them yet
class SyncAuthUsersDialog extends StatefulWidget {
  const SyncAuthUsersDialog({super.key});

  @override
  State<SyncAuthUsersDialog> createState() => _SyncAuthUsersDialogState();
}

class _SyncAuthUsersDialogState extends State<SyncAuthUsersDialog> {
  bool _isSyncing = false;
  String? _resultMessage;
  bool? _success;

  Future<void> _syncAuthUsers() async {
    setState(() {
      _isSyncing = true;
      _resultMessage = null;
      _success = null;
    });

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final result = await authService.syncEmployeesToAuth();

      setState(() {
        _isSyncing = false;
        _resultMessage = result.message;
        _success = result.success;
      });
    } catch (e) {
      print('Sync auth users error: $e'); // Log for debugging
      setState(() {
        _isSyncing = false;
        _resultMessage = 'Unable to sync employees. Please try again.';
        _success = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Sync Employees to Supabase Auth'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This will create Supabase Auth accounts for all existing employees.',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.orange.shade700, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Important:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.orange.shade700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Default password will be: Change@123',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.orange.shade900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Employees should change their password after first login.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.orange.shade900,
                    ),
                  ),
                ],
              ),
            ),
            
            if (_isSyncing) ...[
              const SizedBox(height: 24),
              const Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Syncing employees...'),
                  ],
                ),
              ),
            ],
            
            if (_resultMessage != null) ...[
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _success! ? Colors.green.shade50 : Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _success! ? Colors.green.shade200 : Colors.red.shade200,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _success! ? Icons.check_circle : Icons.error,
                      color: _success! ? Colors.green.shade700 : Colors.red.shade700,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _resultMessage!,
                        style: TextStyle(
                          color: _success! ? Colors.green.shade900 : Colors.red.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSyncing ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        if (_resultMessage == null)
          ElevatedButton(
            onPressed: _isSyncing ? null : _syncAuthUsers,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryOrange,
              foregroundColor: AppTheme.primaryWhite,
            ),
            child: const Text('Sync Now'),
          ),
        if (_success == true)
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('Done'),
          ),
      ],
    );
  }
}
