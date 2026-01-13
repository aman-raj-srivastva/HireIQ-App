import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/chat_room.dart';
import '../services/chat_service.dart';

class MemberDetailsScreen extends StatefulWidget {
  final String memberId;
  final ChatRoom room;

  const MemberDetailsScreen({
    super.key,
    required this.memberId,
    required this.room,
  });

  @override
  State<MemberDetailsScreen> createState() => _MemberDetailsScreenState();
}

class _MemberDetailsScreenState extends State<MemberDetailsScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ChatService _chatService = ChatService();
  Map<String, dynamic>? _userProfile;
  bool _isOnline = false;
  DateTime? _lastSeen;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
    _loadPresence();
  }

  Future<void> _loadUserProfile() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final profileData = await _chatService.getUserProfileData(
        widget.memberId,
      );
      if (mounted) {
        setState(() {
          _userProfile = profileData;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading user profile: $e');
      if (mounted) {
        setState(() {
          _userProfile = {
            'displayName': 'Unknown User',
            'email': null,
            'photoURL': null,
          };
          _isLoading = false;
        });
      }
    }
  }

  void _loadPresence() {
    _firestore
        .collection('chat_rooms')
        .doc(widget.room.id)
        .collection('presence')
        .doc(widget.memberId)
        .snapshots()
        .listen((snapshot) {
          if (snapshot.exists && mounted) {
            final data = snapshot.data() as Map<String, dynamic>;
            setState(() {
              _isOnline = data['isOnline'] ?? false;
              _lastSeen = (data['lastSeen'] as Timestamp?)?.toDate();
            });
          }
        });
  }

  Future<void> _handleMemberAction(String action) async {
    try {
      switch (action) {
        case 'make_admin':
          await _chatService.updateMemberRole(
            widget.room.id,
            widget.memberId,
            'admin',
          );
          break;
        case 'remove_admin':
          await _chatService.updateMemberRole(
            widget.room.id,
            widget.memberId,
            'member',
          );
          break;
        case 'remove':
          final confirmed = await showDialog<bool>(
            context: context,
            builder:
                (context) => AlertDialog(
                  title: const Text('Remove Member'),
                  content: Text(
                    'Are you sure you want to remove ${_userProfile?['displayName'] ?? 'this member'} from the chat?',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: TextButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.error,
                      ),
                      child: const Text('Remove'),
                    ),
                  ],
                ),
          );

          if (confirmed == true && mounted) {
            await _chatService.removeMember(widget.room.id, widget.memberId);
            if (mounted) {
              Navigator.pop(context); // Return to chat room
            }
          }
          break;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  String _formatLastSeen() {
    if (_isOnline) return 'Online';
    if (_lastSeen == null) return 'Offline';

    final now = DateTime.now();
    final difference = now.difference(_lastSeen!);

    if (difference.inDays > 0) {
      return 'Last seen ${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return 'Last seen ${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return 'Last seen ${difference.inMinutes}m ago';
    } else {
      return 'Last seen just now';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isAdmin = widget.room.isAdmin(_auth.currentUser?.uid ?? '');
    final isMemberAdmin = widget.room.isAdmin(widget.memberId);
    final isCurrentUser = widget.memberId == _auth.currentUser?.uid;
    final displayName = _userProfile?['displayName'] ?? 'Unknown User';
    final photoUrl = _userProfile?['photoURL'];
    final email = _userProfile?['email'];
    final isPro = _userProfile?['isPro'] == true;

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Member Details')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Member Details'),
        actions: [
          if (isAdmin && !isCurrentUser)
            PopupMenuButton<String>(
              onSelected: _handleMemberAction,
              itemBuilder:
                  (context) => [
                    if (!isMemberAdmin)
                      const PopupMenuItem(
                        value: 'make_admin',
                        child: Text('Make Admin'),
                      ),
                    if (isMemberAdmin)
                      const PopupMenuItem(
                        value: 'remove_admin',
                        child: Text('Remove Admin'),
                      ),
                    const PopupMenuItem(
                      value: 'remove',
                      child: Text('Remove Member'),
                    ),
                  ],
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadUserProfile,
            tooltip: 'Refresh Profile',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadUserProfile,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                color: theme.colorScheme.surface,
                child: Column(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color:
                              isPro
                                  ? Colors.amber.shade800
                                  : Colors.transparent,
                          width: 3,
                        ),
                      ),
                      child: CircleAvatar(
                        radius: 60,
                        backgroundImage:
                            photoUrl != null && photoUrl.isNotEmpty
                                ? NetworkImage(photoUrl)
                                : null,
                        child:
                            photoUrl == null || photoUrl.isEmpty
                                ? Text(
                                  displayName.isNotEmpty
                                      ? displayName[0].toUpperCase()
                                      : '?',
                                  style: theme.textTheme.headlineLarge
                                      ?.copyWith(
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                      ),
                                )
                                : null,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(displayName, style: theme.textTheme.headlineSmall),
                    if (isPro) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade800.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.amber.shade800.withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.workspace_premium,
                              size: 16,
                              color: Colors.amber.shade800,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Pro Member',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: Colors.amber.shade800,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color:
                            _isOnline
                                ? Colors.green.withOpacity(0.1)
                                : theme.colorScheme.surfaceVariant,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.circle,
                            size: 8,
                            color: _isOnline ? Colors.green : Colors.grey,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _formatLastSeen(),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color:
                                  _isOnline
                                      ? Colors.green
                                      : theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Contact Information Section
              Container(
                padding: const EdgeInsets.all(16),
                color: theme.colorScheme.surface,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Contact Information',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (email != null)
                      ListTile(
                        leading: Icon(
                          Icons.email_outlined,
                          color: theme.colorScheme.primary,
                        ),
                        title: const Text('Email'),
                        subtitle: Text(
                          email,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.copy_outlined),
                          onPressed: () {
                            // TODO: Implement copy to clipboard
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Email copied to clipboard'),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Role Information Section
              Container(
                padding: const EdgeInsets.all(16),
                color: theme.colorScheme.surface,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Role Information',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ListTile(
                      leading: Icon(
                        isMemberAdmin
                            ? Icons.admin_panel_settings
                            : Icons.person,
                        color:
                            isMemberAdmin
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurface,
                      ),
                      title: Text(isMemberAdmin ? 'Admin' : 'Member'),
                      subtitle: Text(
                        isMemberAdmin
                            ? 'Can manage members and settings'
                            : 'Regular chat member',
                      ),
                    ),
                    if (isMemberAdmin) ...[
                      const Divider(),
                      ListTile(
                        leading: const Icon(Icons.shield),
                        title: const Text('Admin Permissions'),
                        subtitle: const Text(
                          'Can manage members, approve join requests, and modify settings',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Chat Room Information Section
              Container(
                padding: const EdgeInsets.all(16),
                color: theme.colorScheme.surface,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Chat Room Information',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ListTile(
                      leading: const Icon(Icons.group),
                      title: const Text('Chat Room'),
                      subtitle: Text(widget.room.name),
                    ),
                    ListTile(
                      leading: const Icon(Icons.calendar_today),
                      title: const Text('Joined'),
                      subtitle: Text(
                        'Member since ${_formatTimestamp(widget.room.createdAt)}',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inDays > 365) {
      final years = (difference.inDays / 365).floor();
      return '$years ${years == 1 ? 'year' : 'years'} ago';
    } else if (difference.inDays > 30) {
      final months = (difference.inDays / 30).floor();
      return '$months ${months == 1 ? 'month' : 'months'} ago';
    } else if (difference.inDays > 0) {
      return '${difference.inDays} ${difference.inDays == 1 ? 'day' : 'days'} ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} ${difference.inHours == 1 ? 'hour' : 'hours'} ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} ${difference.inMinutes == 1 ? 'minute' : 'minutes'} ago';
    } else {
      return 'Just now';
    }
  }
}
