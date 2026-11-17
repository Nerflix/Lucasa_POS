import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/constants/app_constants.dart';
import '../core/theme/app_theme.dart';
import '../data/database/app_database.dart';
import '../features/alerts/alerts_page.dart';
import '../services/auth_service.dart';

/// A notification bell icon that shakes when there are alerts
/// (low-stock items or overdue credits) and shows a badge count.
class AlertsBellIcon extends StatefulWidget {
  const AlertsBellIcon({super.key});

  @override
  State<AlertsBellIcon> createState() => _AlertsBellIconState();
}

class _AlertsBellIconState extends State<AlertsBellIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  int _alertCount = 0;
  bool _hasAlerts = false;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _shakeAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0, end: 0.15)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 1,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.15, end: -0.12)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 1,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: -0.12, end: 0.08)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 1,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.08, end: -0.05)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 1,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: -0.05, end: 0.0)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 1,
      ),
    ]).animate(_shakeController);

    _loadAlertCount();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadAlertCount();
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  Future<void> _loadAlertCount() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final db = Provider.of<AppDatabase>(context, listen: false);

    final locationIds = authService.allowedLocationIds;
    if (locationIds.isEmpty) return;

    final category =
        authService.currentCategory ?? AppConstants.categoryFillingStation;

    // Count low-stock items
    int lowStockCount = 0;
    for (final locId in locationIds) {
      final items =
          await db.getItemsByLocationAndCategory(locId, category);
      lowStockCount += items
          .where((item) =>
              item.reorderLevel > 0 && item.quantity <= item.reorderLevel)
          .length;
    }

    // Count overdue credits
    int overdueCount = 0;
    final now = DateTime.now();
    for (final locId in locationIds) {
      final credits =
          await db.getCreditsByLocationAndCategory(locId, category);
      final overdueCustomerIds = <String>{};
      for (final credit in credits) {
        final threshold =
            credit.category == AppConstants.categoryFillingStation
                ? const Duration(days: 3)
                : const Duration(days: 7);
        if (now.difference(credit.createdAt) > threshold) {
          overdueCustomerIds.add(credit.customerId);
        }
      }
      overdueCount += overdueCustomerIds.length;
    }

    final total = lowStockCount + overdueCount;
    if (mounted) {
      setState(() {
        _alertCount = total;
        _hasAlerts = total > 0;
      });

      if (_hasAlerts) {
        _startShaking();
      }
    }
  }

  void _startShaking() {
    _shakeController.repeat(
      reverse: false,
      period: const Duration(seconds: 3),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _shakeAnimation,
      builder: (context, child) {
        return Transform.rotate(
          angle: _hasAlerts ? _shakeAnimation.value : 0,
          child: child,
        );
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          IconButton(
            icon: Icon(
              _hasAlerts
                  ? Icons.notifications_active
                  : Icons.notifications_none,
              color: _hasAlerts ? AppTheme.warning : AppTheme.darkGray,
            ),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const AlertsPage(),
                ),
              );
              _loadAlertCount();
            },
            tooltip: 'Alerts',
          ),
          if (_hasAlerts)
            Positioned(
              right: 4,
              top: 4,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: AppTheme.error,
                  shape: BoxShape.circle,
                ),
                constraints: const BoxConstraints(
                  minWidth: 18,
                  minHeight: 18,
                ),
                child: Text(
                  _alertCount > 99 ? '99+' : '$_alertCount',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
