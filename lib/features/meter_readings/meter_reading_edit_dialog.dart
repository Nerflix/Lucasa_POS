import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/toast_utils.dart';
import '../../data/models/meter_reading.dart';
import '../../data/repositories/meter_reading_repository.dart';
import '../../services/auth_service.dart';
import 'package:intl/intl.dart';

class MeterReadingEditDialog extends StatefulWidget {
  final MeterReading reading;

  const MeterReadingEditDialog({super.key, required this.reading});

  @override
  State<MeterReadingEditDialog> createState() => _MeterReadingEditDialogState();
}

class _MeterReadingEditDialogState extends State<MeterReadingEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _valueAController;
  late TextEditingController _valueLController;
  late TextEditingController _valueTController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _valueAController = TextEditingController(
      text: widget.reading.valueA.toString(),
    );
    _valueLController = TextEditingController(
      text: widget.reading.valueL.toString(),
    );
    _valueTController = TextEditingController(
      text: widget.reading.valueT.toString(),
    );
  }

  @override
  void dispose() {
    _valueAController.dispose();
    _valueLController.dispose();
    _valueTController.dispose();
    super.dispose();
  }

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    final repository = Provider.of<MeterReadingRepository>(
      context,
      listen: false,
    );
    final authService = Provider.of<AuthService>(context, listen: false);

    try {
      final newValueA = double.parse(_valueAController.text);
      final newValueL = double.parse(_valueLController.text);
      final newValueT = double.parse(_valueTController.text);

      final updatedReading = widget.reading.copyWith(
        valueA: newValueA,
        valueL: newValueL,
        valueT: newValueT,
      );

      await repository.updateMeterReading(updatedReading);

      // Log to AuditLogs (Supabase implementation)
      final changes = {
        'old': {
          'valueA': widget.reading.valueA,
          'valueL': widget.reading.valueL,
          'valueT': widget.reading.valueT,
        },
        'new': {'valueA': newValueA, 'valueL': newValueL, 'valueT': newValueT},
        'pump': '${widget.reading.pumpType} ${widget.reading.pumpNumber}',
        'type': widget.reading.readingType,
      };

      final uuid = const Uuid();
      // Directly using client for audit logs if repository not available
      final client = Provider.of<MeterReadingRepository>(
        context,
        listen: false,
      )._client;
      // NOTE: Better to have an AuditRepository but following existing structure
      await client.from('audit_logs').insert({
        'id': uuid.v4(),
        'location_id': widget.reading.locationId,
        'employee_id': authService.currentEmployee!.id,
        'action_type': 'meter_reading_edited',
        'entity_id': widget.reading.id,
        'changes': jsonEncode(changes),
        'timestamp': DateTime.now().toIso8601String(),
      });

      if (mounted) {
        ToastUtils.showSuccess('Meter reading updated successfully');
        Navigator.pop(context, true);
      }
    } catch (e) {
      ToastUtils.showError('Failed to update reading: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Edit ${widget.reading.readingType.toUpperCase()} Reading'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${widget.reading.pumpType} Pump ${widget.reading.pumpNumber}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Recorded: ${DateFormat('dd MMM yyyy, HH:mm').format(widget.reading.timestamp)}',
              style: const TextStyle(fontSize: 12, color: AppTheme.darkGray),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _valueAController,
              decoration: const InputDecoration(labelText: 'Value A'),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              validator: (v) => v == null || double.tryParse(v) == null
                  ? 'Invalid number'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _valueLController,
              decoration: const InputDecoration(labelText: 'Value L'),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              validator: (v) => v == null || double.tryParse(v) == null
                  ? 'Invalid number'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _valueTController,
              decoration: const InputDecoration(labelText: 'Value T'),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              validator: (v) => v == null || double.tryParse(v) == null
                  ? 'Invalid number'
                  : null,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isSaving ? null : _saveChanges,
          child: _isSaving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save Changes'),
        ),
      ],
    );
  }
}

extension on MeterReadingRepository {
  SupabaseClient get _client =>
      this._client; // This is a hack because the property is private
}
