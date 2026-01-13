import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/network_provider.dart';

class ConnectionStatusBar extends StatefulWidget {
  const ConnectionStatusBar({super.key});

  @override
  State<ConnectionStatusBar> createState() => _ConnectionStatusBarState();
}

class _ConnectionStatusBarState extends State<ConnectionStatusBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _showGreenBar = false;
  static const double _barHeight = 56.0; // Standard AppBar height

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    // Listen to network changes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final networkProvider = Provider.of<NetworkProvider>(
        context,
        listen: false,
      );
      networkProvider.addConnectionRestoredCallback(_handleConnectionRestored);
    });
  }

  void _handleConnectionRestored() {
    if (!mounted) return;

    setState(() {
      _showGreenBar = true;
    });
    _controller.forward();

    // Hide the green bar after 2 seconds
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        _controller.reverse().then((_) {
          if (mounted) {
            setState(() {
              _showGreenBar = false;
            });
          }
        });
      }
    });
  }

  @override
  void dispose() {
    Provider.of<NetworkProvider>(
      context,
      listen: false,
    ).removeConnectionRestoredCallback(_handleConnectionRestored);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final totalHeight = _barHeight + topPadding;

    return Consumer<NetworkProvider>(
      builder: (context, networkProvider, _) {
        if (networkProvider.status == NetworkStatus.connected &&
            !_showGreenBar) {
          return const SizedBox(height: 0);
        }

        return AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, -1),
                  end: Offset.zero,
                ).animate(
                  CurvedAnimation(
                    parent: _controller,
                    curve: Curves.easeOut,
                    reverseCurve: Curves.easeIn,
                  ),
                ),
                child: Material(
                  elevation: 4,
                  color:
                      networkProvider.status == NetworkStatus.disconnected
                          ? Colors.red.shade700
                          : Colors.green.shade700,
                  child: Container(
                    height: totalHeight,
                    width: double.infinity,
                    padding: EdgeInsets.only(
                      top: topPadding,
                      bottom: 0,
                      left: 16,
                      right: 16,
                    ),
                    child: Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            networkProvider.status == NetworkStatus.disconnected
                                ? Icons.wifi_off_rounded
                                : Icons.wifi_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              networkProvider.status ==
                                      NetworkStatus.disconnected
                                  ? 'No Internet Connection'
                                  : 'Internet Connection Restored',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
