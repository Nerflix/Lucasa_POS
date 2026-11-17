import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../services/sync_service.dart';
import '../services/connectivity_service.dart';
import '../services/time_service.dart';

/// Widget to display sync status and trigger manual sync
class SyncStatusWidget extends StatelessWidget {
  final bool showDetails;
  
  const SyncStatusWidget({
    super.key,
    this.showDetails = true,
  });

  @override
  Widget build(BuildContext context) {
    final syncService = Provider.of<SyncService>(context);
    final connectivityService = Provider.of<ConnectivityService>(context);
    final timeService = Provider.of<TimeService>(context);
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  connectivityService.hasConnection 
                      ? Icons.cloud_done 
                      : Icons.cloud_off,
                  color: connectivityService.hasConnection 
                      ? Colors.green 
                      : Colors.grey,
                ),
                const SizedBox(width: 8),
                Text(
                  connectivityService.hasConnection 
                      ? 'Online' 
                      : 'Offline',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                if (syncService.isSyncing)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.sync),
                    onPressed: connectivityService.hasConnection
                        ? () => _syncNow(context, syncService)
                        : null,
                    tooltip: 'Sync now',
                  ),
              ],
            ),
            
            if (showDetails) ...[
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 8),
              
              // Last sync time
              if (syncService.lastSyncTime != null)
                _InfoRow(
                  icon: Icons.history,
                  label: 'Last Sync',
                  value: _formatDateTime(syncService.lastSyncTime!),
                )
              else
                const _InfoRow(
                  icon: Icons.warning_amber,
                  label: 'Last Sync',
                  value: 'Never synced',
                  valueColor: Colors.orange,
                ),
              
              const SizedBox(height: 8),
              
              // Next scheduled sync
              if (connectivityService.hasConnection)
                FutureBuilder<Duration?>(
                  future: _getTimeUntilNextSync(syncService, timeService),
                  builder: (context, snapshot) {
                    if (snapshot.hasData && snapshot.data != null) {
                      final duration = snapshot.data!;
                      return _InfoRow(
                        icon: Icons.schedule,
                        label: 'Next Scheduled Sync',
                        value: _formatDuration(duration),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
              
              const SizedBox(height: 8),
              
              // Timezone
              _InfoRow(
                icon: Icons.public,
                label: 'Timezone',
                value: timeService.getDeviceTimezone(),
              ),
              
              const SizedBox(height: 12),
              
              // Sync info
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue.shade700, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Auto-sync: When online, at 7:00 AM & 9:00 PM',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blue.shade700,
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
    );
  }
  
  Future<void> _syncNow(BuildContext context, SyncService syncService) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    
    final result = await syncService.syncNow(reason: 'Manual sync');
    
    scaffoldMessenger.showSnackBar(
      SnackBar(
        content: Text(result.message),
        backgroundColor: result.success ? Colors.green : Colors.red,
      ),
    );
  }
  
  Future<Duration?> _getTimeUntilNextSync(
    SyncService syncService,
    TimeService timeService,
  ) async {
    try {
      final currentTime = timeService.getCurrentTime();
      final nextSync = timeService.getNextScheduledSyncTime(currentTime);
      return nextSync.difference(currentTime);
    } catch (e) {
      return null;
    }
  }
  
  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    
    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return DateFormat('MMM d, h:mm a').format(dateTime);
    }
  }
  
  String _formatDuration(Duration duration) {
    if (duration.inMinutes < 60) {
      return 'in ${duration.inMinutes}m';
    } else if (duration.inHours < 24) {
      return 'in ${duration.inHours}h ${duration.inMinutes.remainder(60)}m';
    } else {
      final days = duration.inDays;
      final hours = duration.inHours.remainder(24);
      return 'in ${days}d ${hours}h';
    }
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: const TextStyle(
            fontSize: 13,
            color: Colors.grey,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}
