import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/toast_utils.dart';
import '../../data/models/meter_reading.dart';
import '../../data/repositories/location_repository.dart';
import '../../data/repositories/meter_reading_repository.dart';
import '../../data/repositories/sales_repository.dart';
import '../../services/auth_service.dart';

class MeterReadingsDialog extends StatefulWidget {
  final String readingType;

  const MeterReadingsDialog({super.key, required this.readingType});

  @override
  State<MeterReadingsDialog> createState() => _MeterReadingsDialogState();
}

class _MeterReadingsDialogState extends State<MeterReadingsDialog> {
  final List<_PumpReadingEntry> _entries = [];
  final _uuid = const Uuid();
  bool _isSaving = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadEntries();
  }

  @override
  void dispose() {
    for (final entry in _entries) {
      entry.dispose();
    }
    super.dispose();
  }

  Future<void> _loadEntries() async {
    setState(() {
      _isLoading = true;
    });

    final authService = Provider.of<AuthService>(context, listen: false);
    final locationRepo = Provider.of<LocationRepository>(
      context,
      listen: false,
    );
    final locationId = authService.currentEmployee?.locationId;
    if (locationId == null || locationId.isEmpty) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      return;
    }

    try {
      final location = await locationRepo.getLocation(locationId);
      final entries = <_PumpReadingEntry>[];

      if (location != null) {
        for (var i = 1; i <= location.agoPumps; i++) {
          entries.add(_PumpReadingEntry(AppConstants.pumpTypeAGO, i));
        }
        for (var i = 1; i <= location.pmsPumps; i++) {
          entries.add(_PumpReadingEntry(AppConstants.pumpTypePMS, i));
        }
      }

      if (mounted) {
        setState(() {
          _entries
            ..clear()
            ..addAll(entries);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading pump configuration: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _saveReadings() async {
    if (_isSaving) {
      return;
    }

    if (_entries.isEmpty) {
      ToastUtils.showError('No pumps configured for this location.');
      return;
    }

    if (_entries.any((entry) => !entry.isValid)) {
      ToastUtils.showError('Please fill all meter readings.');
      return;
    }

    final authService = Provider.of<AuthService>(context, listen: false);
    final meterReadingRepo = Provider.of<MeterReadingRepository>(
      context,
      listen: false,
    );
    final locationId = authService.currentEmployee?.locationId;
    if (locationId == null) {
      ToastUtils.showError('No location assigned.');
      return;
    }

    // For closing readings, validate against sales data
    if (widget.readingType == AppConstants.readingTypeClosing) {
      final validationError = await _validateClosingReadings(
        locationId,
        authService,
        meterReadingRepo,
      );
      if (validationError != null) {
        _showValidationErrorDialog(validationError);
        return;
      }
    }

    setState(() => _isSaving = true);
    final now = DateTime.now();

    try {
      for (final entry in _entries) {
        await meterReadingRepo.insertMeterReading(
          MeterReading(
            id: _uuid.v4(),
            locationId: locationId,
            employeeId: authService.currentEmployee!.id,
            readingType: widget.readingType,
            category:
                authService.currentCategory ??
                AppConstants.categoryFillingStation,
            pumpType: entry.pumpType,
            pumpNumber: entry.pumpNumber,
            valueA: entry.valueA,
            valueL: entry.valueL,
            valueT: entry.valueT,
            timestamp: now,
          ),
        );
      }

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      ToastUtils.showError('Unable to save meter readings. Please try again.');
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  /// Validates closing readings against today's opening readings and sales data.
  /// Returns an error message string if validation fails, null if OK.
  Future<String?> _validateClosingReadings(
    String locationId,
    AuthService authService,
    MeterReadingRepository meterReadingRepo,
  ) async {
    final category =
        authService.currentCategory ?? AppConstants.categoryFillingStation;
    final employeeId = authService.currentEmployee!.id;

    // Get today's date range
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);

    // 1. Fetch today's opening readings for this employee
    final openingReadings = await meterReadingRepo
        .getMeterReadingsByLocationAndRange(locationId, todayStart, todayEnd);
    final todayOpenings = openingReadings
        .where(
          (r) =>
              r.readingType == AppConstants.readingTypeOpening &&
              r.employeeId == employeeId,
        )
        .toList();

    if (todayOpenings.isEmpty) {
      return 'No opening readings found for today. Cannot validate closing readings.';
    }

    // 2. Calculate deltas per category (closing - opening) for each pump
    final errors = <String>[];

    for (final pumpType in [
      AppConstants.pumpTypeAGO,
      AppConstants.pumpTypePMS,
    ]) {
      // Get opening readings for this pump type
      final typeOpenings = todayOpenings
          .where((r) => r.pumpType == pumpType)
          .toList();
      // Get closing entries for this pump type
      final typeClosings = _entries
          .where((e) => e.pumpType == pumpType)
          .toList();

      if (typeClosings.isEmpty) continue;

      double totalDeltaA = 0;
      double totalDeltaL = 0;

      for (final closingEntry in typeClosings) {
        // Find matching opening reading
        final opening = typeOpenings
            .where((o) => o.pumpNumber == closingEntry.pumpNumber)
            .toList();

        if (opening.isEmpty) {
          errors.add(
            '${closingEntry.pumpType} Pump ${closingEntry.pumpNumber}: '
            'No opening reading found.',
          );
          continue;
        }

        // Closing must be >= opening
        final openReading = opening.first;
        if (closingEntry.valueA < openReading.valueA) {
          errors.add(
            '${closingEntry.pumpType} Pump ${closingEntry.pumpNumber}: '
            'Closing A (${closingEntry.valueA.toStringAsFixed(1)}) is less '
            'than Opening A (${openReading.valueA.toStringAsFixed(1)}).',
          );
        }
        if (closingEntry.valueL < openReading.valueL) {
          errors.add(
            '${closingEntry.pumpType} Pump ${closingEntry.pumpNumber}: '
            'Closing L (${closingEntry.valueL.toStringAsFixed(1)}) is less '
            'than Opening L (${openReading.valueL.toStringAsFixed(1)}).',
          );
        }

        totalDeltaA += (closingEntry.valueA - openReading.valueA);
        totalDeltaL += (closingEntry.valueL - openReading.valueL);
      }

      if (errors.isNotEmpty) continue; // Basic checks failed, skip comparison

      // 3. Fetch today's sales for this fuel type
      final salesRepo = Provider.of<SalesRepository>(context, listen: false);
      final allSales = await salesRepo.getSalesByLocationAndCategory(
        locationId,
        category,
      );
      final todaySales = allSales
          .where(
            (s) =>
                s.timestamp.isAfter(todayStart) &&
                s.timestamp.isBefore(todayEnd) &&
                !s.isSuspended,
          )
          .toList();

      if (todaySales.isEmpty && totalDeltaA > 0) {
        errors.add(
          '$pumpType: Meter shows ${totalDeltaA.toStringAsFixed(1)} in sales (A) '
          'but no $pumpType sales found today.',
        );
        continue;
      }

      // Get sale items for today's sales
      final saleIds = todaySales.map((s) => s.id).toList();
      final saleItems = await salesRepo.getSaleItemsBySaleIds(saleIds);

      // Filter items matching this fuel type
      final fuelItems = saleItems.where((i) {
        final itemName = i.itemName.toUpperCase();
        final type = pumpType.toUpperCase();
        return itemName == type || itemName.contains('$type (');
      }).toList();

      final salesTotal = fuelItems.fold(0.0, (sum, i) => sum + i.subtotal);
      final totalDiscounts = fuelItems.fold(0.0, (sum, i) => sum + i.discount);
      final litersSold = fuelItems.fold(0.0, (sum, i) => sum + i.quantity);

      // Adjusted sales = actual sales + wholesale discounts (what the pump recorded)
      final adjustedSalesTotal = salesTotal + totalDiscounts;

      // 4. Compare with ±3% tolerance
      if (totalDeltaA > 0) {
        final aDiff = (totalDeltaA - adjustedSalesTotal).abs();
        final aThreshold = totalDeltaA * 0.03;
        if (aDiff > aThreshold) {
          errors.add(
            '$pumpType Cash (A) mismatch:\n'
            '  Meter delta: ${totalDeltaA.toStringAsFixed(1)}\n'
            '  Sales total: ${salesTotal.toStringAsFixed(1)}\n'
            '  + Discounts: ${totalDiscounts.toStringAsFixed(1)}\n'
            '  = Adjusted: ${adjustedSalesTotal.toStringAsFixed(1)}\n'
            '  Difference: ${aDiff.toStringAsFixed(1)} '
            '(exceeds ±3% threshold of ${aThreshold.toStringAsFixed(1)})',
          );
        }
      }

      if (totalDeltaL > 0) {
        final lDiff = (totalDeltaL - litersSold).abs();
        final lThreshold = totalDeltaL * 0.03;
        if (lDiff > lThreshold) {
          errors.add(
            '$pumpType Liters (L) mismatch:\n'
            '  Meter delta: ${totalDeltaL.toStringAsFixed(1)}\n'
            '  Liters sold: ${litersSold.toStringAsFixed(1)}\n'
            '  Difference: ${lDiff.toStringAsFixed(1)} '
            '(exceeds ±3% threshold of ${lThreshold.toStringAsFixed(1)})',
          );
        }
      }
    }

    return errors.isEmpty ? null : errors.join('\n\n');
  }

  void _showValidationErrorDialog(String errorMessage) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppTheme.error, size: 28),
            const SizedBox(width: 8),
            const Text('Meter Reading Mismatch'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Closing meter readings do not match sales data within '
                'the ±3% tolerance. Please adjust sales or retake readings.',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.error.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.error.withOpacity(0.2)),
                ),
                child: Text(errorMessage, style: const TextStyle(fontSize: 13)),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: AppTheme.primaryOrange,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(4),
                ),
              ),
              child: Text(
                widget.readingType == AppConstants.readingTypeOpening
                    ? 'Opening Meter Readings'
                    : 'Closing Meter Readings',
                style: const TextStyle(
                  color: AppTheme.primaryWhite,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Flexible(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _isLoading
                    ? const SizedBox(
                        height: 100,
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : _entries.isEmpty
                    ? const Text(
                        'No pumps configured for this location.',
                        style: TextStyle(color: AppTheme.darkGray),
                      )
                    : SingleChildScrollView(
                        child: Column(
                          children: _entries
                              .map((entry) => _buildPumpCard(entry))
                              .toList(),
                        ),
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _isSaving ? null : _saveReadings,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              AppTheme.primaryWhite,
                            ),
                          ),
                        )
                      : const Icon(Icons.save),
                  label: const Text('Save Readings'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPumpCard(_PumpReadingEntry entry) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${entry.pumpType} Pump ${entry.pumpNumber}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: entry.valueAController,
                    decoration: const InputDecoration(labelText: 'A'),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: entry.valueLController,
                    decoration: const InputDecoration(labelText: 'L'),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: entry.valueTController,
                    decoration: const InputDecoration(labelText: 'T'),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PumpReadingEntry {
  final String pumpType;
  final int pumpNumber;
  final TextEditingController valueAController = TextEditingController();
  final TextEditingController valueLController = TextEditingController();
  final TextEditingController valueTController = TextEditingController();

  _PumpReadingEntry(this.pumpType, this.pumpNumber);

  bool get isValid =>
      valueAController.text.trim().isNotEmpty &&
      valueLController.text.trim().isNotEmpty &&
      valueTController.text.trim().isNotEmpty;

  double get valueA => double.tryParse(valueAController.text.trim()) ?? 0;
  double get valueL => double.tryParse(valueLController.text.trim()) ?? 0;
  double get valueT => double.tryParse(valueTController.text.trim()) ?? 0;

  void dispose() {
    valueAController.dispose();
    valueLController.dispose();
    valueTController.dispose();
  }
}
