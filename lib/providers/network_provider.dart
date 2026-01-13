import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

enum NetworkStatus { connected, slow, disconnected }

class NetworkProvider extends ChangeNotifier {
  final Connectivity _connectivity = Connectivity();
  late StreamSubscription<ConnectivityResult> _connectivitySubscription;
  NetworkStatus _status = NetworkStatus.connected;
  NetworkStatus? _previousStatus;
  final List<Function()> _onConnectionRestoredCallbacks = [];

  NetworkStatus get status => _status;
  bool get wasDisconnected => _previousStatus == NetworkStatus.disconnected;

  void addConnectionRestoredCallback(Function() callback) {
    _onConnectionRestoredCallbacks.add(callback);
  }

  void removeConnectionRestoredCallback(Function() callback) {
    _onConnectionRestoredCallbacks.remove(callback);
  }

  NetworkProvider() {
    _initConnectivity();
    // Listen to connectivity changes
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen((
      ConnectivityResult result,
    ) {
      _updateConnectionStatus(result);
    });
  }

  Future<void> checkConnectivity() async {
    try {
      final result = await _connectivity.checkConnectivity();
      _updateConnectionStatus(result);
    } catch (e) {
      _status = NetworkStatus.disconnected;
      notifyListeners();
    }
  }

  Future<void> _initConnectivity() async {
    await checkConnectivity();
  }

  void _updateConnectionStatus(ConnectivityResult result) {
    _previousStatus = _status;

    switch (result) {
      case ConnectivityResult.wifi:
      case ConnectivityResult.mobile:
      case ConnectivityResult.ethernet:
        _status = NetworkStatus.connected;
        break;
      case ConnectivityResult.bluetooth:
      case ConnectivityResult.vpn:
        _status = NetworkStatus.slow;
        break;
      case ConnectivityResult.none:
      default:
        _status = NetworkStatus.disconnected;
        break;
    }

    // If connection was restored (from disconnected to connected)
    if (_previousStatus == NetworkStatus.disconnected &&
        _status == NetworkStatus.connected) {
      // Execute all callbacks
      for (var callback in _onConnectionRestoredCallbacks) {
        callback();
      }
    }

    notifyListeners();
  }

  @override
  void dispose() {
    _connectivitySubscription.cancel();
    _onConnectionRestoredCallbacks.clear();
    super.dispose();
  }
}
