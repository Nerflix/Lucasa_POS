import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';

/// Service to monitor internet connectivity
class ConnectivityService {
  static ConnectivityService? _instance;
  final Connectivity _connectivity = Connectivity();

  final StreamController<bool> _connectionStatusController =
      StreamController<bool>.broadcast();
  Stream<bool> get connectionStatus => _connectionStatusController.stream;

  bool _hasConnection = false;
  bool get hasConnection => _hasConnection;

  ConnectivityService._() {
    _initConnectivity();
    // Your version of the library provides a single ConnectivityResult here.
    _connectivity.onConnectivityChanged.listen((ConnectivityResult result) {
      _updateConnectionStatus(result);
    });
  }

  static ConnectivityService get instance {
    _instance ??= ConnectivityService._();
    return _instance!;
  }

  Future<void> _initConnectivity() async {
    try {
      // Your version of the library provides a single ConnectivityResult here.
      final result = await _connectivity.checkConnectivity();
      await _updateConnectionStatus(result);
    } catch (e) {
      print('Error initializing connectivity: $e');
      _setConnection(false); // Assume no connection on error
    }
  }

  Future<void> _updateConnectionStatus(ConnectivityResult result) async {
    // First, check if the device is connected to a network.
    final hasNetwork = result != ConnectivityResult.none;

    // If there is no network connection at all, we know there is no internet.
    if (!hasNetwork) {
      if (_hasConnection) {
        _setConnection(false);
        print('❌ No network connection');
      }
      return;
    }

    // If a network connection exists, perform a real internet check.
    final hasInternet = await checkActualConnection();

    // Only update and notify if the status has changed.
    if (_hasConnection != hasInternet) {
      _setConnection(hasInternet);
      if (hasInternet) {
        print('✅ Internet connection detected');
      } else {
        print('❌ Network connection found, but no internet access');
      }
    }
  }

  // Helper method to update the connection state and notify all listeners.
  void _setConnection(bool hasConnection) {
    _hasConnection = hasConnection;
    if (!_connectionStatusController.isClosed) {
      _connectionStatusController.add(_hasConnection);
    }
  }

  /// Performs a real internet check by looking up a reliable host.
  Future<bool> checkActualConnection() async {
    try {
      // Use a reliable host like google.com to check for actual internet access.
      final result = await InternetAddress.lookup('google.com');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } on SocketException catch (_) {
      // This exception is caught when the lookup fails, meaning no internet.
      return false;
    }
  }

  /// A public method to allow manual connection checks when needed.
  Future<bool> checkConnection() async {
    final connectivityResult = await _connectivity.checkConnectivity();
    final hasNetwork = connectivityResult != ConnectivityResult.none;

    if (!hasNetwork) {
      return false;
    }

    // If a network exists, perform the real internet check.
    return await checkActualConnection();
  }

  /// Throws an exception if there is no connection.
  Future<void> requireConnection() async {
    if (!await checkConnection()) {
      throw Exception('Internet connection required for this action');
    }
  }

  void dispose() {
    _connectionStatusController.close();
  }
}
