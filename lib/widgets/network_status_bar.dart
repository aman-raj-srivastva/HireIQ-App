import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/network_provider.dart';

class NetworkStatusBar extends StatelessWidget {
  const NetworkStatusBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<NetworkProvider>(
      builder: (context, networkProvider, child) {
        if (networkProvider.status == NetworkStatus.connected) {
          return const SizedBox.shrink();
        }

        return Material(
          color:
              networkProvider.status == NetworkStatus.disconnected
                  ? Colors.red
                  : Colors.orange,
          child: SafeArea(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    networkProvider.status == NetworkStatus.disconnected
                        ? Icons.wifi_off
                        : Icons.signal_wifi_statusbar_connected_no_internet_4,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    networkProvider.status == NetworkStatus.disconnected
                        ? 'No Internet Connection'
                        : 'Slow Internet Connection',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
