import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hireiq/auth/login_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

import 'package:hireiq/screens/home_screen.dart';
import '../services/chat_service.dart';
import 'settings_screen.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:http/http.dart' as http;

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String _userName = 'Loading...';
  String _userEmail = 'Loading...';
  String _userPhotoUrl = '';

  bool _isLoading = true;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _showSubscriptionDetails = false;
  bool _isUpdatingProfile = false;
  final ChatService _chatService = ChatService();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  String? _storedApiKey;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadStoredApiKey();
  }

  Future<void> _loadUserData() async {
    if (!mounted) return;

    try {
      setState(() => _isLoading = true);

      final User? user = _auth.currentUser;
      if (user == null) {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _userName = 'Not signed in';
          _userEmail = 'Please sign in';
        });
        return;
      }

      DocumentSnapshot userDoc = await _firestore
          .collection('users')
          .doc(user.uid)
          .get()
          .timeout(const Duration(seconds: 10));

      if (!mounted) return;

      if (userDoc.exists) {
        final data = userDoc.data() as Map<String, dynamic>;

        setState(() {
          _userName = user.displayName ?? 'User';
          _userEmail = user.email ?? 'No email provided';
          _userPhotoUrl = user.photoURL ?? '';
          _isLoading = false;
        });
      } else {
        // Create user document if it doesn't exist
        await _firestore.collection('users').doc(user.uid).set({
          'createdAt': FieldValue.serverTimestamp(),
        });

        if (!mounted) return;
        setState(() {
          _userName = user.displayName ?? 'User';
          _userEmail = user.email ?? 'No email provided';
          _userPhotoUrl = user.photoURL ?? '';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      debugPrint('Error loading user data: $e');
      setState(() {
        _isLoading = false;
        _userName = 'Error loading profile';
        _userEmail = 'Please try again';
      });
    }
  }

  Future<void> _editProfile() async {
    final TextEditingController nameController = TextEditingController(
      text: _userName,
    );
    final TextEditingController imageController = TextEditingController(
      text: _userPhotoUrl,
    );
    String tempName = _userName;
    String tempImage = _userPhotoUrl;
    ValueNotifier<String> imageUrlNotifier = ValueNotifier<String>(
      _userPhotoUrl,
    );
    ValueNotifier<bool> imageLoading = ValueNotifier<bool>(false);
    ValueNotifier<bool> canSave = ValueNotifier<bool>(false);

    void updateCanSave() {
      canSave.value =
          nameController.text.trim() != _userName ||
          imageController.text.trim() != _userPhotoUrl;
    }

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder:
              (context, setState) => AlertDialog(
                title: const Text('Edit Profile'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ValueListenableBuilder<String>(
                      valueListenable: imageUrlNotifier,
                      builder: (context, url, _) {
                        return ValueListenableBuilder<bool>(
                          valueListenable: imageLoading,
                          builder: (context, loading, __) {
                            return SizedBox(
                              width: 80,
                              height: 80,
                              child: ClipOval(
                                child:
                                    url.isEmpty
                                        ? const Icon(Icons.person, size: 60)
                                        : Stack(
                                          alignment: Alignment.center,
                                          children: [
                                            Image.network(
                                              url,
                                              fit: BoxFit.cover,
                                              width: 80,
                                              height: 80,
                                              loadingBuilder: (
                                                context,
                                                child,
                                                progress,
                                              ) {
                                                if (progress == null) {
                                                  if (imageLoading.value)
                                                    imageLoading.value = false;
                                                  return child;
                                                } else {
                                                  if (!imageLoading.value)
                                                    imageLoading.value = true;
                                                  return const SizedBox();
                                                }
                                              },
                                              errorBuilder: (
                                                context,
                                                error,
                                                stackTrace,
                                              ) {
                                                if (imageLoading.value)
                                                  imageLoading.value = false;
                                                return const Icon(
                                                  Icons.person,
                                                  size: 60,
                                                );
                                              },
                                            ),
                                            if (loading)
                                              const Positioned.fill(
                                                child: Center(
                                                  child:
                                                      CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                      ),
                                                ),
                                              ),
                                          ],
                                        ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Name',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (val) {
                        tempName = val;
                        updateCanSave();
                      },
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: imageController,
                      decoration: const InputDecoration(
                        labelText: 'Profile Image Link',
                        hintText: 'https://.../your-image.png',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (val) {
                        tempImage = val;
                        imageUrlNotifier.value = val;
                        updateCanSave();
                      },
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  ValueListenableBuilder<bool>(
                    valueListenable: canSave,
                    builder: (context, enabled, _) {
                      return TextButton(
                        onPressed:
                            enabled
                                ? () async {
                                  final newName = nameController.text.trim();
                                  final newImage = imageController.text.trim();
                                  if (newName.isEmpty) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Name cannot be empty'),
                                      ),
                                    );
                                    return;
                                  }
                                  // Show loading dialog
                                  showDialog(
                                    context: context,
                                    barrierDismissible: false,
                                    builder:
                                        (context) => const Center(
                                          child: CircularProgressIndicator(),
                                        ),
                                  );
                                  try {
                                    final User? user = _auth.currentUser;
                                    if (user == null) {
                                      throw Exception('User not signed in');
                                    }
                                    // Update user profile in Firebase Auth
                                    await user.updateDisplayName(newName);
                                    if (newImage.isNotEmpty) {
                                      await user.updatePhotoURL(newImage);
                                    }
                                    // Update user document in Firestore
                                    await _firestore
                                        .collection('users')
                                        .doc(user.uid)
                                        .update({
                                          'displayName': newName,
                                          'photoURL': newImage,
                                          'lastUpdated':
                                              FieldValue.serverTimestamp(),
                                        });
                                    if (!mounted) return;
                                    setState(() {
                                      _userName = newName;
                                      _userPhotoUrl = newImage;
                                      _isUpdatingProfile = false;
                                    });
                                  } catch (e) {
                                    if (!mounted) return;
                                    setState(() => _isUpdatingProfile = false);
                                  } finally {
                                    Navigator.of(
                                      context,
                                      rootNavigator: true,
                                    ).pop(); // Close loading dialog
                                    Navigator.pop(context); // Close edit dialog
                                    // Force reload user data and update UI
                                    await _loadUserData();
                                    if (mounted) setState(() {});
                                  }
                                }
                                : null,
                        child: const Text('Save'),
                      );
                    },
                  ),
                ],
              ),
        );
      },
    );
  }

  Future<void> _logout() async {
    bool confirm =
        await showDialog(
          context: context,
          builder:
              (context) => AlertDialog(
                title: const Text('Logout'),
                content: const Text('Are you sure you want to logout?'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Logout'),
                  ),
                ],
              ),
        ) ??
        false;

    if (confirm) {
      try {
        await _auth.signOut();
        await _googleSignIn.signOut();

        // Navigate to login screen and remove all previous routes
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => LoginScreen()),
          (route) => false, // This removes all previous routes
        );

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Logged out successfully')),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Logout failed: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _launchTelegram() async {
    final url = Uri.parse('https://t.me/HireIQ_app');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not launch Telegram')),
        );
      }
    }
  }

  Future<void> _loadStoredApiKey() async {
    try {
      final apiKey = await _secureStorage.read(key: 'groq_api_key');
      if (mounted) {
        setState(() {
          _storedApiKey = apiKey;
        });
      }
    } catch (e) {
      debugPrint('Error loading API key: $e');
    }
  }

  Future<void> _showApiKeyDialog({VoidCallback? onApiKeySet}) async {
    final TextEditingController apiKeyController = TextEditingController(
      text: _storedApiKey ?? '',
    );
    bool storeInCloud = false;
    final user = FirebaseAuth.instance.currentUser;
    String? cloudApiKey;
    bool checkedCloud = false;
    bool showCloudPrompt = false;
    bool noCloudKey = false;

    // If no local API key, check for cloud key first
    if (_storedApiKey == null && user != null) {
      try {
        final userDoc =
            await FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .get();
        if (userDoc.exists &&
            userDoc.data() != null &&
            userDoc.data()!.containsKey('groq_api_key_encrypted')) {
          cloudApiKey = userDoc['groq_api_key_encrypted'] as String?;
          if (cloudApiKey != null && cloudApiKey!.isNotEmpty) {
            showCloudPrompt = true;
          } else {
            noCloudKey = true;
          }
        } else {
          noCloudKey = true;
        }
        checkedCloud = true;
      } catch (e) {
        debugPrint('Error checking cloud API key: $e');
        noCloudKey = true;
        checkedCloud = true;
      }
    }

    // If user has a cloud key and no local key, prompt to use it or set new
    if (showCloudPrompt) {
      await showDialog(
        context: context,
        builder:
            (context) => AlertDialog(
              title: const Text('API Key Found in Cloud'),
              content: const Text(
                'A Groq API key is already stored in the cloud. Would you like to use this key on this device, or set a new one?',
              ),
              actions: [
                TextButton(
                  onPressed: () async {
                    // Use cloud key locally
                    await _secureStorage.write(
                      key: 'groq_api_key',
                      value: cloudApiKey,
                    );
                    if (mounted) {
                      setState(() {
                        _storedApiKey = cloudApiKey;
                      });
                      Navigator.pop(context);
                    }
                  },
                  child: const Text('Use Cloud Key'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    // Proceed to set new key below
                  },
                  child: const Text('Set New Key'),
                ),
              ],
            ),
      );
      // If user chose to set new key, fall through to dialog below
      if (_storedApiKey != null) return;
    } else if (noCloudKey && _storedApiKey == null) {
      // Show info if no cloud key found
      await showDialog(
        context: context,
        builder:
            (context) => AlertDialog(
              title: const Text('No API Key Found'),
              content: const Text(
                'No Groq API key was found in the cloud. Please set a new API key.',
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

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder:
              (context, setState) => AlertDialog(
                title: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Groq API Key'),
                    if (_storedApiKey == null)
                      IconButton(
                        icon: const Icon(Icons.help_outline),
                        tooltip: 'How to get your api key',
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder:
                                (context) => AlertDialog(
                                  title: const Text(
                                    'How to get your Groq API key',
                                  ),
                                  content: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text('1. Visit '),
                                      GestureDetector(
                                        onTap: () async {
                                          final url = Uri.parse(
                                            'https://console.groq.com',
                                          );
                                          if (await canLaunchUrl(url)) {
                                            await launchUrl(
                                              url,
                                              mode:
                                                  LaunchMode
                                                      .externalApplication,
                                            );
                                          }
                                        },
                                        child: const Text(
                                          'https://console.groq.com',
                                          style: TextStyle(
                                            color: Colors.blue,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      const Text(
                                        '2. Sign up or log in to your account',
                                      ),
                                      const Text(
                                        '3. Navigate to API Keys section',
                                      ),
                                      const Text('4. Create a new API key'),
                                      const Text('5. Copy and paste it below'),
                                    ],
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: const Text('OK'),
                                    ),
                                  ],
                                ),
                          );
                        },
                      ),
                  ],
                ),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '🔒 Your API key is stored securely on your device and is never shared with us or any third party by default.',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 12),
                      if (_storedApiKey == null) ...[
                        Row(
                          children: [
                            Checkbox(
                              value: storeInCloud,
                              onChanged: (val) {
                                setState(() => storeInCloud = val ?? false);
                              },
                            ),
                            const Expanded(
                              child: Text(
                                'Store API key in the cloud (access from any device)',
                                style: TextStyle(fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                        if (storeInCloud) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              '⚠️ It is recommended to store your API key locally and copy-paste it when needed. Storing in the cloud carries some risk. Only proceed if you understand and accept this.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.orange,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                      ],
                      const SizedBox(height: 16),
                      TextField(
                        controller: apiKeyController,
                        decoration: const InputDecoration(
                          labelText: 'API Key',
                          hintText: 'gsk_...',
                          border: OutlineInputBorder(),
                        ),
                        obscureText: true,
                        readOnly: _storedApiKey != null,
                        enableInteractiveSelection: _storedApiKey == null,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '⚠️ Keep your API key secure and never share it with anyone.',
                        style: TextStyle(fontSize: 11, color: Colors.orange),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  if (_storedApiKey != null)
                    TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                        backgroundColor: Colors.red.withOpacity(0.08),
                      ),
                      onPressed: () async {
                        await _secureStorage.delete(key: 'groq_api_key');
                        if (mounted) {
                          setState(() {
                            _storedApiKey = null;
                          });
                          await _loadStoredApiKey();
                          if (onApiKeySet != null) onApiKeySet();
                          Navigator.pop(context);
                        }
                      },
                      child: const Text('Remove'),
                    ),
                  if (_storedApiKey == null)
                    ElevatedButton(
                      onPressed: () async {
                        final apiKey = apiKeyController.text.trim();
                        final shouldStoreInCloud = storeInCloud;
                        Navigator.pop(
                          context,
                        ); // Immediately close the Groq API key dialog
                        await Future.delayed(
                          const Duration(milliseconds: 100),
                        ); // Ensure dialog closes before opening next
                        List<bool?> stepResults = [null, null, null];
                        bool finished = false;
                        bool isValid = false;
                        final result = await showDialog(
                          context: context,
                          barrierDismissible: false,
                          builder: (context) {
                            return StatefulBuilder(
                              builder: (context, setState) {
                                // Start the validation process only once
                                Future<void>.delayed(Duration.zero, () async {
                                  if (stepResults[0] == null) {
                                    // Step 1: Format
                                    await Future.delayed(
                                      const Duration(milliseconds: 400),
                                    );
                                    if (!RegExp(
                                      r'^gsk_[A-Za-z0-9]{20,}$',
                                    ).hasMatch(apiKey)) {
                                      setState(() {
                                        stepResults[0] = false;
                                        stepResults[1] = false;
                                        stepResults[2] = false;
                                        finished = true;
                                        isValid = false;
                                      });
                                      return;
                                    } else {
                                      setState(() {
                                        stepResults[0] = true;
                                      });
                                    }
                                    // Step 2: Connect
                                    await Future.delayed(
                                      const Duration(milliseconds: 400),
                                    );
                                    try {
                                      final response = await http.get(
                                        Uri.parse(
                                          'https://api.groq.com/openai/v1/models',
                                        ),
                                        headers: {
                                          'Authorization': 'Bearer $apiKey',
                                        },
                                      );
                                      if (response.statusCode == 200) {
                                        setState(() {
                                          stepResults[1] = true;
                                        });
                                        // Step 3: Validate
                                        await Future.delayed(
                                          const Duration(milliseconds: 400),
                                        );
                                        setState(() {
                                          stepResults[2] = true;
                                          finished = true;
                                          isValid = true;
                                        });
                                        // Automatically close the dialog after a short delay
                                        await Future.delayed(
                                          const Duration(milliseconds: 700),
                                        );
                                        if (Navigator.of(context).canPop()) {
                                          Navigator.of(context).pop(true);
                                        }
                                      } else {
                                        setState(() {
                                          stepResults[1] = false;
                                          stepResults[2] = false;
                                          finished = true;
                                          isValid = false;
                                        });
                                      }
                                    } catch (e) {
                                      setState(() {
                                        stepResults[1] = false;
                                        stepResults[2] = false;
                                        finished = true;
                                        isValid = false;
                                      });
                                    }
                                  }
                                });
                                return AlertDialog(
                                  title: const Text('Validating API Key'),
                                  content: SizedBox(
                                    width: 300,
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        _ValidationStep(
                                          label: 'Checking format',
                                          done: stepResults[0] == true,
                                          failed: stepResults[0] == false,
                                          inProgress:
                                              stepResults[0] == null &&
                                              !finished,
                                        ),
                                        _ValidationStep(
                                          label: 'Connecting to Groq API',
                                          done: stepResults[1] == true,
                                          failed: stepResults[1] == false,
                                          inProgress:
                                              stepResults[0] == true &&
                                              stepResults[1] == null &&
                                              !finished,
                                        ),
                                        _ValidationStep(
                                          label: 'Validating key',
                                          done: stepResults[2] == true,
                                          failed: stepResults[2] == false,
                                          inProgress:
                                              stepResults[1] == true &&
                                              stepResults[2] == null &&
                                              !finished,
                                        ),
                                        if (finished && !isValid)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 16,
                                            ),
                                            child: Text(
                                              'API key is not valid or could not connect to Groq API.',
                                              style: const TextStyle(
                                                color: Colors.red,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        if (finished && isValid)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 16,
                                            ),
                                            child: Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: const [
                                                Icon(
                                                  Icons.check_circle,
                                                  color: Colors.green,
                                                ),
                                                SizedBox(width: 8),
                                                Text(
                                                  'API key is valid!',
                                                  style: TextStyle(
                                                    color: Colors.green,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  actions: [
                                    if (finished && !isValid)
                                      TextButton(
                                        onPressed: () async {
                                          Navigator.pop(context);
                                          await Future.delayed(
                                            const Duration(milliseconds: 100),
                                          );
                                          _showApiKeyDialog();
                                        },
                                        child: const Text('Reset API Key'),
                                      ),
                                  ],
                                );
                              },
                            );
                          },
                        ).then((result) async {
                          if (result != true) return;
                          if (shouldStoreInCloud) {
                            try {
                              final user = FirebaseAuth.instance.currentUser;
                              if (user != null) {
                                await FirebaseFirestore.instance
                                    .collection('users')
                                    .doc(user.uid)
                                    .set({
                                      'groq_api_key_encrypted': apiKey,
                                    }, SetOptions(merge: true));
                              }
                              await _secureStorage.write(
                                key: 'groq_api_key',
                                value: apiKey,
                              );
                            } catch (e) {}
                          } else {
                            try {
                              await _secureStorage.write(
                                key: 'groq_api_key',
                                value: apiKey,
                              );
                            } catch (e) {}
                          }
                          await _loadStoredApiKey();
                          if (onApiKeySet != null) onApiKeySet();
                        });
                      },
                      child: const Text('Save'),
                    ),
                ],
              ),
        );
      },
    );
    // After validation dialog closes, always reload the key and update state
    await _loadStoredApiKey();
  }

  Future<void> _updateProfile() async {
    if (!mounted) return;

    setState(() => _isUpdatingProfile = true);

    try {
      final User? user = _auth.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      // Update profile in Firebase Auth
      await user.updateDisplayName(_userName);

      // Store updated profile data in Firestore
      await _chatService.storeUserProfileData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update profile: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUpdatingProfile = false);
      }
    }
  }

  Future<bool> _validateGroqApiKey(
    String apiKey,
    void Function(int, bool) onStep,
  ) async {
    // Step 1: Check format
    await Future.delayed(const Duration(milliseconds: 400));
    if (!RegExp(r'^gsk_[A-Za-z0-9]{20,}$').hasMatch(apiKey)) {
      onStep(0, false);
      return false;
    }
    onStep(0, true);

    // Step 2: Try connecting to Groq API
    await Future.delayed(const Duration(milliseconds: 400));
    try {
      final response = await http.get(
        Uri.parse('https://api.groq.com/openai/v1/models'),
        headers: {'Authorization': 'Bearer $apiKey'},
      );
      if (response.statusCode == 200) {
        onStep(1, true);
        // Step 3: Validate key (response OK)
        await Future.delayed(const Duration(milliseconds: 400));
        onStep(2, true);
        return true;
      } else {
        onStep(1, false);
        onStep(2, false);
        return false;
      }
    } catch (e) {
      onStep(1, false);
      onStep(2, false);
      return false;
    }
  }

  Widget _buildProfileOption(
    IconData icon,
    String title,
    VoidCallback onTap, {
    bool showTrailingIcon = true,
    Widget? trailing,
    Color? iconColor,
  }) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Theme.of(
            context,
          ).colorScheme.primaryContainer.withOpacity(0.2),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          icon,
          color: iconColor ?? Theme.of(context).colorScheme.primary,
        ),
      ),
      title: Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w500),
      ),
      trailing:
          trailing ??
          (showTrailingIcon ? const Icon(Icons.chevron_right) : null),
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _isUpdatingProfile) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              if (_isUpdatingProfile) ...[
                const SizedBox(height: 16),
                const Text('Updating profile...'),
              ],
            ],
          ),
        ),
      );
    }

    return WillPopScope(
      onWillPop: () async {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => HomeScreen()),
          (route) => false,
        );
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Profile'),
          centerTitle: true,
          actions: [
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => SettingsScreen()),
                );
              },
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Column(
                children: [
                  Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Theme.of(context).colorScheme.primary,
                            width: 3,
                          ),
                        ),
                        child: ClipOval(
                          child:
                              _userPhotoUrl.isNotEmpty
                                  ? Image.network(
                                    _userPhotoUrl,
                                    fit: BoxFit.cover,
                                    loadingBuilder: (
                                      BuildContext context,
                                      Widget child,
                                      ImageChunkEvent? loadingProgress,
                                    ) {
                                      if (loadingProgress == null) return child;
                                      return Center(
                                        child: CircularProgressIndicator(
                                          value:
                                              loadingProgress
                                                          .expectedTotalBytes !=
                                                      null
                                                  ? loadingProgress
                                                          .cumulativeBytesLoaded /
                                                      loadingProgress
                                                          .expectedTotalBytes!
                                                  : null,
                                        ),
                                      );
                                    },
                                    errorBuilder:
                                        (context, error, stackTrace) =>
                                            const Icon(Icons.person, size: 60),
                                  )
                                  : const Icon(Icons.person, size: 60),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _userName,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _userEmail,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              Container(
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.surfaceVariant.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Theme.of(context).dividerColor.withOpacity(0.1),
                    width: 1,
                  ),
                ),
                child: Column(
                  children: [
                    _buildProfileOption(
                      Icons.edit,
                      'Edit Profile',
                      _editProfile,
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    _buildProfileOption(
                      Icons.key,
                      'API Key Management',
                      () => _showApiKeyDialog(
                        onApiKeySet: () async {
                          await _loadStoredApiKey();
                          if (mounted) setState(() {});
                        },
                      ),
                      trailing:
                          _storedApiKey != null
                              ? Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.green.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Text(
                                  'Set',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.green,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              )
                              : Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Text(
                                  'Not Set',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.orange,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    _buildProfileOption(
                      Icons.language,
                      'Try our web version',
                      () async {
                        final url = Uri.parse('https://hireiq-web.vercel.app/');
                        if (await canLaunchUrl(url)) {
                          await launchUrl(
                            url,
                            mode: LaunchMode.externalApplication,
                          );
                        }
                      },
                      iconColor: Colors.blue,
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    _buildProfileOption(Icons.feedback, 'Send Feedback', () async {
                        final url = Uri.parse('https://aicon-studioz.vercel.app/#contact');
                        if (await canLaunchUrl(url)) {
                          await launchUrl(
                            url,
                            mode: LaunchMode.externalApplication,
                          );
                        }
                      },),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    _buildProfileOption(Icons.privacy_tip, 'Privacy Policy', () async {
                        final url = Uri.parse('https://aiconstudiozapps.blogspot.com/2025/05/hireiq-privacy-policy-hireiq-privacy.html');
                        if (await canLaunchUrl(url)) {
                          await launchUrl(
                            url,
                            mode: LaunchMode.externalApplication,
                          );
                        }
                      },),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    _buildProfileOption(
                      Icons.telegram,
                      'Join Telegram Community',
                      _launchTelegram,
                      iconColor: const Color(0xFF0088cc),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      icon: Icon(
                        Icons.logout,
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                      label: const Text('Logout'),
                      style: FilledButton.styleFrom(
                        backgroundColor:
                            Theme.of(context).colorScheme.errorContainer,
                        foregroundColor:
                            Theme.of(context).colorScheme.onErrorContainer,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: _logout,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ValidationStep extends StatelessWidget {
  final String label;
  final bool done;
  final bool failed;
  final bool inProgress;
  const _ValidationStep({
    required this.label,
    required this.done,
    required this.failed,
    this.inProgress = false,
  });
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child:
                done
                    ? Icon(
                      Icons.check_circle,
                      color: Colors.green,
                      key: ValueKey('done'),
                    )
                    : failed
                    ? Icon(
                      Icons.cancel,
                      color: Colors.red,
                      key: ValueKey('fail'),
                    )
                    : inProgress
                    ? SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                      key: ValueKey('progress'),
                    )
                    : Icon(
                      Icons.radio_button_unchecked,
                      color: Colors.grey,
                      key: ValueKey('idle'),
                    ),
          ),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              fontWeight: done ? FontWeight.bold : null,
              color: failed ? Colors.red : null,
            ),
          ),
        ],
      ),
    );
  }
}
