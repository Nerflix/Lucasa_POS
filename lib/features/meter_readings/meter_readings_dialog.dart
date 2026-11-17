import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' as drift;
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/toast_utils.dart';
import '../../data/database/app_database.dart';
import '../../services/auth_service.dart';

class MeterReadingsDialog extends StatefulWidget {
  final String readingType;

  const MeterReadingsDialog({
    super.key,
    required this.readingType,
  });

  @override
  State<MeterReadingsDialog> createState() => _MeterReadingsDialogState();
}

class _MeterReadingsDialogState extends State<MeterReadingsDialog> {
  final List<_PumpReadingEntry> _entries = [];
  final _uuid = const Uuid();
  bool _isSaving = false;

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
    final authService = Provider.of<AuthService>(context, listen: false);
    final db = Provider.of<AppDatabase>(context, listen: false);
    final locationId = authService.currentEmployee?.locationId;
    if (locationId == null || locationId.isEmpty) {
      return;
    }

    final location = await db.getLocation(locationId);
    if (location == null) {
      return;
    }

    final entries = <_PumpReadingEntry>[];
    for (var i = 1; i <= location.agoPumps; i++) {
      entries.add(_PumpReadingEntry(AppConstants.pumpTypeAGO, i));
    }
    for (var i = 1; i <= location.pmsPumps; i++) {
      entries.add(_PumpReadingEntry(AppConstants.pumpTypePMS, i));
    }

    if (mounted) {
      setState(() {
        _entries
          ..clear()
          ..addAll(entries);
      });
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
    final db = Provider.of<AppDatabase>(context, listen: false);
    final locationId = authService.currentEmployee?.locationId;
    if (locationId == null) {
      ToastUtils.showError('No location assigned.');
      return;
    }

    setState(() => _isSaving = true);
    final now = DateTime.now();

    try {
      for (final entry in _entries) {
        await db.insertMeterReading(
          MeterReadingsCompanion(
            id: drift.Value(_uuid.v4()),
            locationId: drift.Value(locationId),
            employeeId: drift.Value(authService.currentEmployee!.id),
            readingType: drift.Value(widget.readingType),
            category: drift.Value(authService.currentCategory ?? AppConstants.categoryFillingStation),
            pumpType: drift.Value(entry.pumpType),
            pumpNumber: drift.Value(entry.pumpNumber),
            valueA: drift.Value(entry.valueA),
            valueL: drift.Value(entry.valueL),
            valueT: drift.Value(entry.valueT),
            timestamp: drift.Value(now),
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
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: _entries.isEmpty
                    ? const Text(
                        'No pumps configured for this location.',
                        style: TextStyle(color: AppTheme.darkGray),
                      )
                    : Column(
                        children: _entries
                            .map((entry) => _buildPumpCard(entry))
                            .toList(),
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
