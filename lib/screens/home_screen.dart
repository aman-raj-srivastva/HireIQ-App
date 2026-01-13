import '../screens/favorites_screen.dart';
import 'package:flutter/material.dart';
import '../data.dart';
import 'category_roles_screen.dart';
import 'role_detail_screen.dart';
import 'interview_screen.dart';

import 'learn_screen.dart';
import 'profile_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import 'resume_review_screen.dart';
import 'dart:async';
import 'settings_screen.dart' as app_settings;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';
import '../utils/version_provider.dart';
import 'chat_rooms_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  final Set<String> favoriteRoles = {};
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _customRoleController = TextEditingController();
  final TextEditingController _customCompanyController =
      TextEditingController();
  final TextEditingController _customDifficultyController =
      TextEditingController();
  final TextEditingController _customDescriptionController =
      TextEditingController();
  List<Map<String, dynamic>> _filteredRoles = List.from(AppData.roles);
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  String _userName = 'Loading...';
  String _userEmail = 'Loading...';
  String _userPhotoUrl = '';
  StreamSubscription? _favoritesSubscription;
  final FocusNode _searchFocusNode = FocusNode();
  static const String _profileImageUrlKey = 'profile_image_url';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_filterRoles);
    _loadUserData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _customRoleController.dispose();
    _customCompanyController.dispose();
    _customDifficultyController.dispose();
    _customDescriptionController.dispose();
    _searchFocusNode.dispose();
    _favoritesSubscription?.cancel();
    super.dispose();
  }

  void _filterRoles() {
    final query = _searchController.text.toLowerCase();
    if (!mounted) return;
    setState(() {
      _filteredRoles =
          AppData.roles.where((role) {
            final title = role['title']?.toString().toLowerCase() ?? '';
            final category = role['category']?.toString().toLowerCase() ?? '';
            return title.contains(query) || category.contains(query);
          }).toList();
    });
  }

  Future<void> _saveProfileImageUrl(String url) async {
    if (url.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_profileImageUrlKey, url);
  }

  Future<String> _loadProfileImageUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_profileImageUrlKey) ?? '';
  }

  Future<void> _loadUserData() async {
    try {
      final User? user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        // Load cached profile image URL first
        final cachedImageUrl = await _loadProfileImageUrl();
        if (cachedImageUrl.isNotEmpty && mounted) {
          setState(() {
            _userPhotoUrl = cachedImageUrl;
          });
        }

        // Listen to user document changes in Firestore
        FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .snapshots()
            .listen((DocumentSnapshot doc) {
              if (mounted) {
                setState(() {
                  if (doc.exists && doc.data() != null) {
                    final data = doc.data() as Map<String, dynamic>;
                    _userName = data['displayName'] ?? _userName;
                  }
                });
              }
            });

        // Listen to Auth state changes for profile updates
        FirebaseAuth.instance.authStateChanges().listen((
          User? updatedUser,
        ) async {
          if (updatedUser != null && mounted) {
            final photoUrl = updatedUser.photoURL ?? '';
            if (photoUrl.isNotEmpty) {
              await _saveProfileImageUrl(photoUrl);
            }
            setState(() {
              _userName = updatedUser.displayName ?? 'User';
              _userEmail = updatedUser.email ?? 'No email provided';
              _userPhotoUrl = photoUrl;
            });
            // Load favorites when user signs in
            _loadFavorites();
          } else if (mounted) {
            setState(() {
              _userName = 'Not signed in';
              _userEmail = 'Please sign in';
              _userPhotoUrl = '';

              favoriteRoles.clear();
            });
          }
        });

        // Set initial values
        final photoUrl = user.photoURL ?? '';
        if (photoUrl.isNotEmpty) {
          await _saveProfileImageUrl(photoUrl);
        }
        setState(() {
          _userName = user.displayName ?? 'User';
          _userEmail = user.email ?? 'No email provided';
          _userPhotoUrl = photoUrl;
        });

        // Load favorites immediately for current user
        await _loadFavorites();
      } else {
        setState(() {
          _userName = 'Not signed in';
          _userEmail = 'Please sign in';
          _userPhotoUrl = '';

          favoriteRoles.clear();
        });
      }
    } catch (e) {
      debugPrint('Error loading user data: $e');
      if (mounted) {
        setState(() {
          _userName = 'Error loading profile';
          _userEmail = 'Please try again';
          _userPhotoUrl = '';
        });
      }
    }
  }

  Future<void> _loadFavorites() async {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => favoriteRoles.clear());
      return;
    }

    try {
      // Cancel existing subscription if any
      await _favoritesSubscription?.cancel();

      // Get initial favorites
      final favoritesSnapshot =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .collection('favorites')
              .get();

      if (mounted) {
        setState(() {
          favoriteRoles.clear();
          for (var doc in favoritesSnapshot.docs) {
            favoriteRoles.add(doc.id);
          }
        });
      }

      // Set up real-time listener
      _favoritesSubscription = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('favorites')
          .snapshots()
          .listen((snapshot) {
            if (mounted) {
              setState(() {
                favoriteRoles.clear();
                for (var doc in snapshot.docs) {
                  favoriteRoles.add(doc.id);
                }
              });
            }
          });
    } catch (e) {
      debugPrint('Error loading favorites: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to load favorites')),
        );
      }
    }
  }

  Future<void> _toggleFavorite(String role) async {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to save favorites')),
      );
      return;
    }

    try {
      final docRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('favorites')
          .doc(role);

      if (favoriteRoles.contains(role)) {
        await docRef.delete();
      } else {
        await docRef.set({
          'addedAt': FieldValue.serverTimestamp(),
          'roleTitle': role,
        });
      }
    } catch (e) {
      debugPrint('Error toggling favorite: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to update favorite')),
      );
    }
  }

  Future<String> _getDeviceInfo() async {
    final deviceInfo = DeviceInfoPlugin();
    String deviceInfoString = '';
    if (Theme.of(context).platform == TargetPlatform.android) {
      final androidInfo = await deviceInfo.androidInfo;
      deviceInfoString = '''
Device: ${androidInfo.manufacturer} ${androidInfo.model}
Android Version: ${androidInfo.version.release}, SDK: ${androidInfo.version.sdkInt}
''';
    } else if (Theme.of(context).platform == TargetPlatform.iOS) {
      final iosInfo = await deviceInfo.iosInfo;
      deviceInfoString = '''
Device: ${iosInfo.name} ${iosInfo.model}
iOS Version: ${iosInfo.systemVersion}
''';
    }
    return deviceInfoString;
  }

  Future<void> _handleBugReport() async {
    final deviceInfo = await _getDeviceInfo();
    final appVersion = await VersionProvider.getAppVersion();

    final emailBody = '''
$deviceInfo
App Information:
Version: $appVersion
Platform: ${Theme.of(context).platform}

Please describe the bug you encountered in our app:
''';

    final Uri uri = Uri.parse(
      'mailto:srivastvaamanraj0@gmail.com?subject=HireIQ Bug Report&body=${Uri.encodeComponent(emailBody)}',
    );

    try {
      if (!await launchUrl(uri)) {
        if (mounted) {
          final emailDetails =
              'Email: srivastvaamanraj0@gmail.com\nSubject: HireIQ Bug Report\n\n$emailBody';
          await showDialog(
            context: context,
            builder:
                (context) => AlertDialog(
                  title: const Text('Could not open email app'),
                  content: const Text(
                    'Would you like to copy the email details to clipboard?',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: emailDetails));
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Email details copied to clipboard'),
                          ),
                        );
                      },
                      child: const Text('Copy'),
                    ),
                  ],
                ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to open email client')),
        );
      }
    }
  }

  Future<void> _handleRateUs() async {
    const String appId = 'com.aicon.hireiq'; // Your Play Store app ID
    final Uri uri = Uri.parse('market://details?id=$appId');
    final Uri fallbackUri = Uri.parse(
      'https://play.google.com/store/apps/details?id=$appId',
    );

    try {
      if (!await launchUrl(uri)) {
        await launchUrl(fallbackUri);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Could not open store')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    List<Widget> pages = [
      _buildHomeScreen(),
      const ChatRoomsScreen(),
      const LearnScreen(),
      const ProfileScreen(),
    ];

    return Scaffold(
      key: _scaffoldKey,
      appBar: _selectedIndex == 0 ? _buildCustomAppBar() : null,
      drawer: _buildDrawer(),
      body: pages[_selectedIndex],
      bottomNavigationBar: _buildBottomNavigationBar(),
    );
  }

  PreferredSizeWidget _buildCustomAppBar() {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return AppBar(
      elevation: 0,
      backgroundColor: colorScheme.surface,
      automaticallyImplyLeading: false,
      title: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // const SizedBox(height: 7),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: () => _scaffoldKey.currentState?.openDrawer(),
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(shape: BoxShape.circle),
                    child: _buildProfileImage(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    // height: 44,
                    child: Align(
                      alignment: Alignment.center,
                      child: TextField(
                        controller: _searchController,
                        focusNode: _searchFocusNode,
                        style: textTheme.bodyLarge?.copyWith(
                          color: colorScheme.onSurface,
                        ),
                        decoration: InputDecoration(
                          hintText: "Search jobs...",
                          hintStyle: textTheme.bodyLarge?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                          prefixIcon: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Icon(
                              Icons.search_rounded,
                              size: 20,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          prefixIconConstraints: const BoxConstraints(
                            minWidth: 40,
                            minHeight: 40,
                          ),
                          filled: true,
                          fillColor: colorScheme.surfaceVariant,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 0,
                            horizontal: 0,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(22),
                            borderSide: BorderSide(
                              color: colorScheme.outline.withOpacity(0.5),
                              width: 1.5,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(22),
                            borderSide: BorderSide(
                              color: colorScheme.outline.withOpacity(0.5),
                              width: 1.5,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(22),
                            borderSide: BorderSide(
                              color: colorScheme.primary,
                              width: 2,
                            ),
                          ),
                          isDense: true,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNavigationBar() {
    return Container(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).shadowColor.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 5,
            offset: const Offset(0, -2),
          ),
        ],
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        color: Theme.of(context).scaffoldBackgroundColor,
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: BottomNavigationBar(
          currentIndex: _selectedIndex,
          onTap: (index) async {
            _searchFocusNode.unfocus();
            if (index == 3) {
              await FirebaseAuth.instance.currentUser?.reload();
              final user = FirebaseAuth.instance.currentUser;
              if (!mounted) return;
              setState(() {
                _userName = user?.displayName ?? 'User';
                _userEmail = user?.email ?? 'No email provided';
                _userPhotoUrl = user?.photoURL ?? '';
                _selectedIndex = index;
              });
            } else {
              if (!mounted) return;
              setState(() {
                _selectedIndex = index;
              });
            }
          },
          selectedItemColor: Theme.of(context).colorScheme.primary,
          unselectedItemColor: Theme.of(
            context,
          ).colorScheme.onSurface.withOpacity(0.6),
          showSelectedLabels: true,
          showUnselectedLabels: false,
          type: BottomNavigationBarType.fixed,
          elevation: 0,
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          selectedLabelStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
          items: [
            BottomNavigationBarItem(
              icon: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color:
                      _selectedIndex == 0
                          ? Theme.of(context).colorScheme.primaryContainer
                          : Colors.transparent,
                ),
                child: Icon(
                  _selectedIndex == 0 ? Icons.home : Icons.home_outlined,
                  size: 24,
                ),
              ),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color:
                      _selectedIndex == 1
                          ? Theme.of(context).colorScheme.primaryContainer
                          : Colors.transparent,
                ),
                child: Icon(
                  _selectedIndex == 1 ? Icons.chat : Icons.chat_outlined,
                  size: 24,
                ),
              ),
              label: 'Chat',
            ),
            BottomNavigationBarItem(
              icon: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color:
                      _selectedIndex == 2
                          ? Theme.of(context).colorScheme.primaryContainer
                          : Colors.transparent,
                ),
                child: Icon(
                  _selectedIndex == 2 ? Icons.school : Icons.school_outlined,
                  size: 24,
                ),
              ),
              label: 'Learn',
            ),
            BottomNavigationBarItem(
              icon: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color:
                      _selectedIndex == 3
                          ? Theme.of(context).colorScheme.primaryContainer
                          : Colors.transparent,
                ),
                child: Icon(
                  _selectedIndex == 3 ? Icons.person : Icons.person_outline,
                  size: 24,
                ),
              ),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHomeScreen() {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        _searchFocusNode.unfocus();
      },
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Categories',
              style: textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 120,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: AppData.categories.length,
                itemBuilder:
                    (context, index) => Padding(
                      padding: const EdgeInsets.only(right: 16.0),
                      child: GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder:
                                  (context) => CategoryRolesScreen(
                                    categoryTitle:
                                        AppData.categories[index]["title"]!,
                                    favoriteRoles: favoriteRoles,
                                    onFavoriteToggle: _toggleFavorite,
                                  ),
                            ),
                          );
                        },
                        child: Container(
                          width: 108,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            color: colorScheme.surface,
                            border: Border.all(
                              color: colorScheme.outline.withOpacity(0.2),
                              width: 1,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                height: 50,
                                padding: const EdgeInsets.all(8),
                                child: Image.network(
                                  AppData.categories[index]["icon"]!,
                                  fit: BoxFit.contain,
                                  errorBuilder:
                                      (context, error, stackTrace) => Icon(
                                        Icons.error,
                                        color: colorScheme.error,
                                      ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10.0,
                                ),
                                child: Text(
                                  AppData.categories[index]["title"]!,
                                  style: textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: colorScheme.onSurface,
                                  ),
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: colorScheme.surface,
                border: Border.all(
                  color: colorScheme.outline.withOpacity(0.2),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: colorScheme.shadow.withOpacity(0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.work_rounded,
                          color: colorScheme.onPrimaryContainer,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Custom Interview',
                              style: textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Practice with your specific requirements',
                              style: textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _showCustomInterviewDialog,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color.fromARGB(255, 88, 92, 148),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 16,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.play_arrow_rounded, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Start Custom Interview',
                            style: textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Popular Job Roles',
              style: textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 16),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 0.95,
              ),
              itemCount: _filteredRoles.length,
              itemBuilder: (context, index) {
                final role = _filteredRoles[index];
                final isFavorite = favoriteRoles.contains(role["title"]);

                return GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder:
                            (context) => RoleDetailScreen(
                              title: role["title"]!,
                              image: role["image"]!,
                              salary: role["salary"]!,
                              rating: role["rating"]!,
                              description: role["description"]!,
                              isFavorite: isFavorite,
                              onFavoriteToggle:
                                  () => _toggleFavorite(role["title"]!),
                              hasApplyOption: role["hasApplyOption"] ?? false,
                              applyLink: role["applyLink"],
                            ),
                      ),
                    );
                  },
                  child: Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: colorScheme.outline.withOpacity(0.2),
                        width: 1,
                      ),
                    ),
                    color: colorScheme.surface,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Stack(
                            children: [
                              ClipRRect(
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(16),
                                ),
                                child: Image.network(
                                  role["image"]!,
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                  errorBuilder:
                                      (context, error, stackTrace) => Container(
                                        color: colorScheme.surfaceVariant,
                                        alignment: Alignment.center,
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.broken_image_rounded,
                                              color:
                                                  colorScheme.onSurfaceVariant,
                                              size: 48,
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              'Image not found',
                                              style: textTheme.bodySmall
                                                  ?.copyWith(
                                                    color:
                                                        colorScheme
                                                            .onSurfaceVariant,
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ),
                                ),
                              ),
                              Positioned(
                                top: 8,
                                right: 8,
                                child: GestureDetector(
                                  onTap: () => _toggleFavorite(role["title"]!),
                                  child: Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: colorScheme.surface.withOpacity(
                                        0.8,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: colorScheme.shadow.withOpacity(
                                            0.1,
                                          ),
                                          blurRadius: 4,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Icon(
                                      isFavorite
                                          ? Icons.favorite
                                          : Icons.favorite_border,
                                      color:
                                          isFavorite
                                              ? const Color(0xFFE53935)
                                              : colorScheme.onSurfaceVariant,
                                      size: 20,
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                bottom: 8,
                                left: 8,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colorScheme.primaryContainer
                                        .withOpacity(0.9),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    role["salary"]!,
                                    style: textTheme.labelMedium?.copyWith(
                                      color: colorScheme.onPrimaryContainer,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                role["title"]!,
                                style: textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.onSurface,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Icon(
                                    Icons.star_rounded,
                                    size: 18,
                                    color: Colors.amber.shade600,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    role["rating"]!,
                                    style: textTheme.bodyMedium?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 20),
            Center(
              child: Text(
                'More job roles to be added by the next update',
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomInterviewForm() {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Custom Interview Details',
          style: textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _customRoleController,
          decoration: InputDecoration(
            labelText: 'Job Role *',
            hintText: 'e.g., Software Engineer, Product Manager',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: colorScheme.primary),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _customCompanyController,
          decoration: InputDecoration(
            labelText: 'Company (Optional)',
            hintText: 'e.g., Google, Microsoft',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: colorScheme.primary),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
          ),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          value:
              _customDifficultyController.text.isEmpty
                  ? null
                  : _customDifficultyController.text,
          decoration: InputDecoration(
            labelText: 'Difficulty Level *',
            hintText: 'Select difficulty level',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: colorScheme.primary),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
          ),
          items:
              ['Easy', 'Medium', 'Hard'].map((String value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(value),
                );
              }).toList(),
          onChanged: (String? newValue) {
            setState(() {
              _customDifficultyController.text = newValue ?? '';
            });
          },
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _customDescriptionController,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: 'Additional Description (Optional)',
            hintText:
                'Describe the role, company culture, or specific requirements...',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: colorScheme.primary),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _startCustomInterview,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color.fromARGB(255, 88, 92, 148),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.play_arrow_rounded, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Start Custom Interview',
                  style: textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _showCustomInterviewDialog() {
    // Clear previous values
    _customRoleController.clear();
    _customCompanyController.clear();
    _customDifficultyController.clear();
    _customDescriptionController.clear();

    showDialog(
      context: context,
      builder:
          (context) => Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.8,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(20),
                        topRight: Radius.circular(20),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.work_rounded,
                          color: Theme.of(context).colorScheme.onPrimary,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Custom Interview',
                            style: Theme.of(
                              context,
                            ).textTheme.titleLarge?.copyWith(
                              color: Theme.of(context).colorScheme.onPrimary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: Icon(
                            Icons.close,
                            color: Theme.of(context).colorScheme.onPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Form Content
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: _buildCustomInterviewForm(),
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
  }

  void _startCustomInterview() {
    final role = _customRoleController.text.trim();
    final company = _customCompanyController.text.trim();
    final difficulty = _customDifficultyController.text.trim();
    final description = _customDescriptionController.text.trim();

    if (role.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a job role'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (difficulty.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a difficulty level'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Close the custom interview dialog
    Navigator.pop(context);

    // Generate a unique session ID for this interview
    final sessionId = 'custom_${DateTime.now().millisecondsSinceEpoch}';

    // Create a custom role title that includes all the details
    String customRoleTitle = role;
    if (company.isNotEmpty) {
      customRoleTitle += ' at $company';
    }
    customRoleTitle += ' ($difficulty level)';
    if (description.isNotEmpty) {
      customRoleTitle += ' - $description';
    }

    // Navigate to the interview screen
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) => InterviewScreen(
              roleTitle: customRoleTitle,
              sessionId: sessionId,
            ),
      ),
    );
  }

  Drawer _buildDrawer() {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Drawer(
      width: MediaQuery.of(context).size.width * 0.75,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          _buildDrawerHeader(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color.fromARGB(255, 83, 0, 138),
                    Color.fromARGB(255, 119, 0, 174),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const ResumeReviewScreen(),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.description_rounded,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Resume Review',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Get AI-powered feedback',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.9),
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.arrow_forward_ios_rounded,
                          color: Colors.white.withOpacity(0.9),
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          _buildDrawerItem(
            icon: Icons.favorite,
            title: 'Favorites',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder:
                      (context) => FavoritesScreen(
                        favoriteRoles: favoriteRoles,
                        onFavoriteRemoved: _toggleFavorite,
                      ),
                ),
              );
            },
          ),
          const Divider(height: 1, thickness: 1),
          _buildDrawerItem(
            icon: Icons.share,
            title: 'Share App',
            onTap: () {
              const String appLink =
                  'https://play.google.com/store/apps/details?id=com.aicon.hireiq';
              const String shareMessage =
                  '''🚀 Ace Your Next Job Interview with HireIQ – Your Personal AI Interview Coach! 🤖🎯

✨ Key Features:
💬 AI-Powered Mock Interviews
📄 Smart Resume Review
🧠 Skill Analytics & Feedback
📝 Mixed Question Types
📊 Get your report
🗨️ Speacialized Chat Rooms

Whether you're preparing for your first job or your next big role, HireIQ is here to help you succeed. Practice smart, grow confident, and walk into your next interview with clarity and courage! 💼

Download now: $appLink''';

              Share.share(shareMessage);
            },
          ),
          _buildDrawerItem(
            icon: Icons.star,
            title: 'Rate Us',
            onTap: _handleRateUs,
          ),
          _buildDrawerItem(
            icon: Icons.bug_report,
            title: 'Report Bug',
            onTap: _handleBugReport,
          ),

          const Divider(height: 1, thickness: 1),
          FutureBuilder<String>(
            future: VersionProvider.getAppVersion(),
            builder: (context, snapshot) {
              return Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'Version ${snapshot.data ?? "Loading..."}',
                  style: TextStyle(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(0.6),
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDrawerHeader() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      children: [
        UserAccountsDrawerHeader(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors:
                  isDark
                      ? [
                        const Color.fromARGB(255, 23, 24, 24),
                        const Color.fromARGB(255, 79, 80, 80),
                      ]
                      : [
                        const Color.fromARGB(255, 98, 0, 255),
                        const Color.fromARGB(255, 154, 14, 247),
                      ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          accountName: Text(
            _userName,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          accountEmail: Text(_userEmail),
          currentAccountPicture: Container(
            decoration: BoxDecoration(shape: BoxShape.circle),
            child: _buildProfileImage(),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(top: 12, right: 12),
            child: Align(
              alignment: Alignment.topRight,
              child: IconButton(
                icon: Icon(Icons.settings, color: Colors.white),
                tooltip: 'Settings',
                onPressed: () async {
                  Navigator.pop(context); // Close drawer
                  await Future.delayed(const Duration(milliseconds: 200));
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => app_settings.SettingsScreen(),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDrawerItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: Theme.of(context).colorScheme.onSurface),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w500,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
      onTap: () {
        Navigator.pop(context);
        onTap();
      },
    );
  }

  Widget _buildProfileImage() {
    if (_userPhotoUrl.isEmpty) {
      return const CircleAvatar(backgroundImage: AssetImage('assets/icon.png'));
    }
    return CachedNetworkImage(
      imageUrl: _userPhotoUrl,
      imageBuilder:
          (context, imageProvider) =>
              CircleAvatar(backgroundImage: imageProvider),
      placeholder:
          (context, url) => const CircleAvatar(
            backgroundImage: AssetImage('assets/icon.png'),
          ),
      errorWidget:
          (context, url, error) => const CircleAvatar(
            backgroundImage: AssetImage('assets/icon.png'),
          ),
    );
  }
}
