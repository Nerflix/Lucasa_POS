import 'dart:async';
import 'package:flutter/material.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter_pos_printer_plus/flutter_pos_printer_plus.dart';
import '../core/constants/app_constants.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/toast_utils.dart';
import '../data/database/app_database.dart';

class ReceiptPrintData {
  final Location location;
  final String receiptId;
  final DateTime timestamp;
  final String employeeName;
  final List<ReceiptPrintItem> items;
  final String paymentMethod;
  final double totalAmount;
  final double? amountPaid;
  final double? changeGiven;
  final double? outstandingBalance;

  const ReceiptPrintData({
    required this.location,
    required this.receiptId,
    required this.timestamp,
    required this.employeeName,
    required this.items,
    required this.paymentMethod,
    required this.totalAmount,
    this.amountPaid,
    this.changeGiven,
    this.outstandingBalance,
  });
}

class ReceiptPrintItem {
  final String name;
  final double quantity;
  final double price;

  const ReceiptPrintItem({
    required this.name,
    required this.quantity,
    required this.price,
  });
}

class ReceiptPrintService {
  Future<void> showPrintOptions(BuildContext context, ReceiptPrintData data) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Print Receipt',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _showBluetoothPrinters(context, data);
                  },
                  icon: const Icon(Icons.bluetooth),
                  label: const Text('Bluetooth Printer'),
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _showWifiPrinterDialog(context, data);
                  },
                  icon: const Icon(Icons.wifi),
                  label: const Text('Wi-Fi Printer'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showBluetoothPrinters(BuildContext context, ReceiptPrintData data) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _BluetoothPrinterSheet(data: data),
    );
  }

  Future<void> _showWifiPrinterDialog(BuildContext context, ReceiptPrintData data) async {
    final ipController = TextEditingController();
    final portController = TextEditingController(text: '9100');

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Wi-Fi Printer'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ipController,
              decoration: const InputDecoration(
                labelText: 'Printer IP address',
                hintText: '192.168.0.100',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: portController,
              decoration: const InputDecoration(
                labelText: 'Port',
              ),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final ip = ipController.text.trim();
              final port = int.tryParse(portController.text.trim()) ?? 9100;
              if (ip.isEmpty) {
                ToastUtils.showError('Enter printer IP address.');
                return;
              }
              Navigator.pop(context);
              await printToWifi(ip, port, data);
            },
            child: const Text('Print'),
          ),
        ],
      ),
    );
  }

  Future<void> printToWifi(String ip, int port, ReceiptPrintData data) async {
    final manager = PrinterManager.instance;
    final profile = await CapabilityProfile.load();
    final bytes = await _buildReceiptBytes(data, profile);
    final connected = await manager.connect(
      type: PrinterType.network,
      model: TcpPrinterInput(ipAddress: ip, port: port),
    );

    if (!connected) {
      ToastUtils.showError('Wi-Fi printer connection failed.');
      return;
    }

    final sent = await manager.send(type: PrinterType.network, bytes: bytes);
    await manager.disconnect(type: PrinterType.network);

    if (!sent) {
      ToastUtils.showError('Wi-Fi printer print failed.');
      return;
    }

    ToastUtils.showSuccess('Receipt sent to Wi-Fi printer.');
  }

  Future<void> printToBluetooth(
    PrinterDevice printer,
    ReceiptPrintData data,
  ) async {
    final address = printer.address;
    if (address == null || address.isEmpty) {
      ToastUtils.showError('Bluetooth printer address not available.');
      return;
    }

    final profile = await CapabilityProfile.load();
    final manager = PrinterManager.instance;
    final bytes = await _buildReceiptBytes(data, profile);
    final connected = await manager.connect(
      type: PrinterType.bluetooth,
      model: BluetoothPrinterInput(
        name: printer.name,
        address: address,
        isBle: false,
        autoConnect: true,
      ),
    );

    if (!connected) {
      ToastUtils.showError('Bluetooth printer connection failed.');
      return;
    }

    final sent = await manager.send(type: PrinterType.bluetooth, bytes: bytes);
    await manager.disconnect(type: PrinterType.bluetooth);

    if (!sent) {
      ToastUtils.showError('Bluetooth print failed.');
      return;
    }

    ToastUtils.showSuccess('Receipt sent to Bluetooth printer.');
  }

  Future<List<int>> _buildReceiptBytes(
    ReceiptPrintData data,
    CapabilityProfile profile,
  ) async {
    final generator = Generator(PaperSize.mm80, profile);
    final bytes = <int>[];

    bytes.addAll(generator.text(
      data.location.name,
      styles: const PosStyles(
        align: PosAlign.center,
        bold: true,
        height: PosTextSize.size2,
        width: PosTextSize.size2,
      ),
    ));

    if (data.location.address != null && data.location.address!.isNotEmpty) {
      bytes.addAll(generator.text(
        data.location.address!,
        styles: const PosStyles(align: PosAlign.center),
      ));
    }

    if (data.location.phone != null && data.location.phone!.isNotEmpty) {
      bytes.addAll(generator.text(
        'Tel: ${data.location.phone}',
        styles: const PosStyles(align: PosAlign.center),
      ));
    }

    bytes.addAll(generator.hr());
    bytes.addAll(generator.text('Receipt: ${data.receiptId}'));
    bytes.addAll(generator.text('Cashier: ${data.employeeName}'));
    bytes.addAll(generator.text('Payment: ${data.paymentMethod}'));
    if (data.paymentMethod == AppConstants.paymentCredit) {
      bytes.addAll(generator.text('CREDIT SALE'));
    }
    bytes.addAll(generator.hr());

    for (final item in data.items) {
      final lineTotal = item.price * item.quantity;
      bytes.addAll(
        generator.row([
          PosColumn(
            text: item.name,
            width: 6,
          ),
          PosColumn(
            text: '${item.quantity.toStringAsFixed(0)}x',
            width: 2,
            styles: const PosStyles(align: PosAlign.right),
          ),
          PosColumn(
            text: lineTotal.toStringAsFixed(0),
            width: 4,
            styles: const PosStyles(align: PosAlign.right),
          ),
        ]),
      );
    }

    bytes.addAll(generator.hr());
    bytes.addAll(
      generator.text(
        'TOTAL: KES ${data.totalAmount.toStringAsFixed(0)}',
        styles: const PosStyles(bold: true),
      ),
    );
    if (data.amountPaid != null) {
      bytes.addAll(generator.text(
        'PAID: KES ${data.amountPaid!.toStringAsFixed(0)}',
      ));
    }
    if (data.outstandingBalance != null) {
      bytes.addAll(generator.text(
        'OUTSTANDING: KES ${data.outstandingBalance!.toStringAsFixed(0)}',
      ));
    }
    if (data.changeGiven != null) {
      bytes.addAll(generator.text(
        'CHANGE: KES ${data.changeGiven!.toStringAsFixed(0)}',
      ));
    }
    bytes.addAll(generator.feed(2));
    bytes.addAll(generator.text(
      'Thank you!',
      styles: const PosStyles(align: PosAlign.center, bold: true),
    ));
    bytes.addAll(generator.feed(2));
    bytes.addAll(generator.cut());

    return bytes;
  }
}

class _BluetoothPrinterSheet extends StatefulWidget {
  final ReceiptPrintData data;

  const _BluetoothPrinterSheet({required this.data});

  @override
  State<_BluetoothPrinterSheet> createState() => _BluetoothPrinterSheetState();
}

class _BluetoothPrinterSheetState extends State<_BluetoothPrinterSheet> {
  final ReceiptPrintService _service = ReceiptPrintService();
  final PrinterManager _manager = PrinterManager.instance;
  StreamSubscription<PrinterDevice>? _scanSubscription;
  final List<PrinterDevice> _printers = [];
  bool _isScanning = false;

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    super.dispose();
  }

  void _startScan() {
    setState(() => _isScanning = true);
    _printers.clear();
    _scanSubscription?.cancel();
    _scanSubscription = _manager
        .discovery(type: PrinterType.bluetooth, isBle: false)
        .listen((device) {
      if (!mounted) {
        return;
      }
      final exists = _printers.any(
        (printer) => printer.address == device.address,
      );
      if (!exists) {
        setState(() => _printers.add(device));
      }
    });
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() => _isScanning = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Bluetooth Printers',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                if (_isScanning)
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _startScan,
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_printers.isEmpty)
              const Text(
                'No printers found. Make sure your printer is paired.',
                style: TextStyle(color: AppTheme.darkGray),
              )
            else
              ..._printers.map((printer) {
                final name = printer.name.isNotEmpty
                    ? printer.name
                    : 'Unknown Printer';
                return Card(
                  child: ListTile(
                    title: Text(name),
                    subtitle: Text(printer.address ?? ''),
                    trailing: const Icon(Icons.print),
                    onTap: () async {
                      Navigator.pop(context);
                      await _service.printToBluetooth(printer, widget.data);
                    },
                  ),
                );
              }),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }
}
