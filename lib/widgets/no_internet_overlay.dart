import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/network_provider.dart';

class NoInternetOverlay extends StatelessWidget {
  const NoInternetOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<NetworkProvider>(
      builder: (context, networkProvider, _) {
        if (networkProvider.status == NetworkStatus.connected) {
          return const SizedBox.shrink();
        }

        return Material(
          color:
              networkProvider.status == NetworkStatus.disconnected
                  ? Colors.black.withOpacity(0.8)
                  : Colors.orange.withOpacity(0.8),
          child: SafeArea(
            child: Center(
              child: Container(
                margin: const EdgeInsets.all(24),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      networkProvider.status == NetworkStatus.disconnected
                          ? Icons.wifi_off_rounded
                          : Icons
                              .signal_wifi_statusbar_connected_no_internet_4_rounded,
                      size: 64,
                      color:
                          networkProvider.status == NetworkStatus.disconnected
                              ? Colors.red
                              : Colors.orange,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      networkProvider.status == NetworkStatus.disconnected
                          ? 'No Internet Connection'
                          : 'Slow Internet Connection',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color:
                            networkProvider.status == NetworkStatus.disconnected
                                ? Colors.red
                                : Colors.orange,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      networkProvider.status == NetworkStatus.disconnected
                          ? 'Please check your internet connection and try again.'
                          : 'Your internet connection seems to be slow. Some features may not work properly.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(
                          context,
                        ).textTheme.bodyMedium?.color?.withOpacity(0.7),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: () {
                        // Trigger a recheck of the connection
                        Provider.of<NetworkProvider>(
                          context,
                          listen: false,
                        ).checkConnectivity();
                      },
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Try Again'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
