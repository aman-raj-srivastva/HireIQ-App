import 'package:flutter/material.dart';
import '../data.dart';
import 'role_detail_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'home_screen.dart';

class FavoritesScreen extends StatefulWidget {
  final Set<String> favoriteRoles;
  final Function(String) onFavoriteRemoved;

  const FavoritesScreen({
    super.key,
    required this.favoriteRoles,
    required this.onFavoriteRemoved,
  });

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  bool _isLoading = true;
  late List<Map<String, dynamic>> _favoriteRoleList;

  @override
  void initState() {
    super.initState();
    _updateFavoriteList();
    // Add a small delay to show loading state
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    });
  }

  void _updateFavoriteList() {
    setState(() {
      _favoriteRoleList =
          AppData.roles
              .where((role) => widget.favoriteRoles.contains(role["title"]))
              .toList();
    });
  }

  void _handleFavoriteRemoved(String roleTitle) {
    setState(() {
      widget.onFavoriteRemoved(roleTitle);
      _favoriteRoleList.removeWhere((role) => role["title"] == roleTitle);
    });
  }

  @override
  Widget build(BuildContext context) {
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
          title: const Text('Favorites'),
          centerTitle: true,
          elevation: 0,
        ),
        body:
            _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_favoriteRoleList.isEmpty) {
      return _buildEmptyState();
    }
    return _buildFavoritesList(context, _favoriteRoleList);
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.favorite_border,
            size: 60,
            color: Colors.grey.shade300.withOpacity(0.5),
          ),
          const SizedBox(height: 24),
          Text(
            'No favorites yet',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Sign in to save your favorite roles and access them across devices',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
            ),
          ),
          const SizedBox(height: 24),
          if (FirebaseAuth.instance.currentUser == null)
            ElevatedButton.icon(
              onPressed: () {
                // Navigate to profile screen to sign in
                Navigator.pushNamed(context, '/profile');
              },
              icon: const Icon(Icons.login),
              label: const Text('Sign In'),
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
    );
  }

  Widget _buildFavoritesList(
    BuildContext context,
    List<Map<String, dynamic>> favorites,
  ) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: favorites.length,
      itemBuilder: (context, index) {
        final role = favorites[index];
        return Dismissible(
          key: Key(role["title"]!),
          direction: DismissDirection.endToStart,
          background: Container(
            color: Colors.red,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            child: const Icon(Icons.delete, color: Colors.white),
          ),
          onDismissed: (direction) {
            _handleFavoriteRemoved(role["title"]!);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text("${role["title"]} removed from favorites"),
                action: SnackBarAction(
                  label: 'Undo',
                  onPressed: () {
                    widget.onFavoriteRemoved(role["title"]!); // Toggle back
                    _updateFavoriteList(); // Refresh the list
                  },
                ),
              ),
            );
          },
          child: _buildFavoriteItem(context, role),
        );
      },
    );
  }

  Widget _buildFavoriteItem(BuildContext context, Map<String, dynamic> role) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: const Color.fromARGB(71, 125, 125, 125), width: 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
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
                    isFavorite: true,
                    hasApplyOption: role["applyLink"] != null,
                    applyLink: role["applyLink"],
                    onFavoriteToggle: () {
                      // Just update the parent's favorite list without popping
                      widget.onFavoriteRemoved(role["title"]!);
                    },
                  ),
            ),
          ).then((_) {
            // Update the list when returning from detail screen
            _updateFavoriteList();
          });
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  role["image"]!,
                  width: 120,
                  height: 80,
                  fit: BoxFit.cover,
                  errorBuilder:
                      (context, error, stackTrace) => Container(
                        width: 80,
                        height: 80,
                        color: Colors.grey.shade200,
                        child: const Icon(Icons.broken_image),
                      ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      role["title"]!,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.attach_money,
                          size: 16,
                          color: Colors.green.shade600,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          role["salary"]!,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.star,
                          size: 16,
                          color: Colors.amber.shade600,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          role["rating"]!,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.favorite, color: Colors.red),
                onPressed: () {
                  _handleFavoriteRemoved(role["title"]!);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
