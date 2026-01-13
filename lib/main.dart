import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:hireiq/screens/home_screen.dart';
import 'auth/login_screen.dart';
import 'firebase_options.dart';
import 'package:provider/provider.dart';
import 'providers/theme_provider.dart';
import 'providers/network_provider.dart';
import 'widgets/no_internet_overlay.dart';
import 'widgets/connection_status_bar.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

Future<void> saveFcmToken() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;
  final token = await FirebaseMessaging.instance.getToken();
  if (token != null) {
    await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
      'fcmToken': token,
    });
  }
}

void setupFirebaseMessaging(BuildContext context) {
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    // Optionally show a local notification or update UI
    // You can use flutter_local_notifications for rich notifications
    print(
      'Received a message in foreground: \\${message.notification?.title}: \\${message.notification?.body}',
    );
  });

  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    // Navigate to the chat room using message.data['roomId']
    final roomId = message.data['roomId'];
    if (roomId != null) {
      // TODO: Implement navigation to the chat room screen
      print('Notification tapped. Navigate to room: $roomId');
    }
  });
}

void main() async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  // Keep native splash screen up until Firebase is initialized
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Remove splash screen with fade animation
  FlutterNativeSplash.remove();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => NetworkProvider()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return MaterialApp(
          title: 'HireIQ',
          theme: themeProvider.lightTheme,
          darkTheme: themeProvider.darkTheme,
          themeMode: themeProvider.themeMode,
          debugShowCheckedModeBanner: false,
          home: const NetworkAwareWrapper(),
          routes: {
            '/home': (context) => const HomeScreen(),
            '/login': (context) => LoginScreen(),
          },
          builder: (context, child) {
            return Theme(
              data: Theme.of(context).copyWith(
                pageTransitionsTheme: const PageTransitionsTheme(
                  builders: {
                    TargetPlatform.android: CupertinoPageTransitionsBuilder(),
                    TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
                  },
                ),
              ),
              child: NetworkAwareBuilder(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Main content
                    Positioned.fill(child: child!),
                    // Status bar above everything
                    const ConnectionStatusBar(),
                    // Overlay on top of everything except status bar
                    const Positioned.fill(child: NoInternetOverlay()),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class NetworkAwareBuilder extends StatefulWidget {
  final Widget child;

  const NetworkAwareBuilder({super.key, required this.child});

  @override
  State<NetworkAwareBuilder> createState() => _NetworkAwareBuilderState();
}

class _NetworkAwareBuilderState extends State<NetworkAwareBuilder> {
  @override
  void initState() {
    super.initState();
    // Add callback for connection restoration
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<NetworkProvider>(
        context,
        listen: false,
      ).addConnectionRestoredCallback(_handleConnectionRestored);
      // Set up Firebase Messaging
      setupFirebaseMessaging(context);
    });
  }

  @override
  void dispose() {
    Provider.of<NetworkProvider>(
      context,
      listen: false,
    ).removeConnectionRestoredCallback(_handleConnectionRestored);
    super.dispose();
  }

  void _handleConnectionRestored() {
    // Get the current route
    final currentRoute = ModalRoute.of(context);
    if (currentRoute != null) {
      // If we're on a screen that should refresh, trigger a rebuild
      if (currentRoute.settings.name == '/home') {
        setState(() {
          // This will trigger a rebuild of the current screen
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

class NetworkAwareWrapper extends StatelessWidget {
  const NetworkAwareWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return const AuthWrapper();
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }

        if (snapshot.connectionState == ConnectionState.active) {
          User? user = snapshot.data;
          if (user == null) {
            return LoginScreen();
          }
          // Save FCM token after user is authenticated
          saveFcmToken();
          return const HomeScreen();
        }

        return Center(child: CircularProgressIndicator());
      },
    );
  }
}
