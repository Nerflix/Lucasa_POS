import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';

class SyncIndicator extends StatelessWidget {
  final bool isOnline;
  final VoidCallback? onPressed;
  final String? tooltip;
  final Color? iconColor;

  const SyncIndicator({
    super.key,
    required this.isOnline,
    this.onPressed,
    this.tooltip,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final Color statusColor =
        iconColor ?? (isOnline ? AppTheme.success : AppTheme.error);

    return IconButton(
      icon: Icon(
        isOnline ? Icons.cloud_done : Icons.cloud_off,
        color: statusColor,
      ),
      onPressed: onPressed,
      tooltip: tooltip ?? (isOnline ? 'Online' : 'Offline - Check connection'),
    );
  }
}
