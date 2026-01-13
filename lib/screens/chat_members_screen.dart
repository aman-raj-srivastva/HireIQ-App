import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/chat_room.dart';
import '../services/chat_service.dart';
import 'member_details_screen.dart';

class ChatMembersScreen extends StatefulWidget {
  final ChatRoom room;

  const ChatMembersScreen({super.key, required this.room});

  @override
  State<ChatMembersScreen> createState() => _ChatMembersScreenState();
}

class _ChatMembersScreenState extends State<ChatMembersScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ChatService _chatService = ChatService();
  final TextEditingController _searchController = TextEditingController();
  Map<String, Map<String, dynamic>> _userProfiles = {};
  bool _showPendingRequests = false;
  bool _requireAdminApproval = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadUserProfiles();
    _requireAdminApproval = widget.room.requireAdminApproval;
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text.toLowerCase();
    });
  }

  bool _matchesSearch(Map<String, dynamic> profile) {
    if (_searchQuery.isEmpty) return true;

    final displayName = (profile['displayName'] ?? '').toString().toLowerCase();
    final email = (profile['email'] ?? '').toString().toLowerCase();

    return displayName.contains(_searchQuery) || email.contains(_searchQuery);
  }

  Future<void> _loadUserProfiles() async {
    for (final memberId in widget.room.members) {
      await _loadUserProfile(memberId);
    }
  }

  Future<void> _loadUserProfile(String userId) async {
    if (_userProfiles.containsKey(userId)) return;

    try {
      final profileData = await _chatService.getUserProfileData(userId);
      if (mounted) {
        setState(() {
          _userProfiles[userId] = profileData;
        });
      }
    } catch (e) {
      debugPrint('Error loading user profile: $e');
      if (mounted) {
        setState(() {
          _userProfiles[userId] = {
            'displayName': 'Unknown User',
            'email': null,
            'photoURL': null,
          };
        });
      }
    }
  }

  Future<void> _handleMemberAction(String action, String memberId) async {
    try {
      switch (action) {
        case 'make_admin':
          await _chatService.updateMemberRole(
            widget.room.id,
            memberId,
            'admin',
          );
          break;
        case 'remove_admin':
          await _chatService.updateMemberRole(
            widget.room.id,
            memberId,
            'member',
          );
          break;
        case 'remove':
          final userProfile = _userProfiles[memberId] ?? {};
          final displayName = userProfile['displayName'] ?? 'this member';

          final confirmed = await showDialog<bool>(
            context: context,
            builder:
                (context) => AlertDialog(
                  title: const Text('Remove Member'),
                  content: Text(
                    'Are you sure you want to remove $displayName from the chat?',
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
            await _chatService.removeMember(widget.room.id, memberId);
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

  Future<void> _handleJoinRequest(String userId, bool approve) async {
    try {
      if (approve) {
        await _chatService.approveJoinRequest(widget.room.id, userId);
      } else {
        await _firestore
            .collection('chat_rooms')
            .doc(widget.room.id)
            .collection('pending_members')
            .doc(userId)
            .delete();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _updateAdminApproval(bool value) async {
    try {
      await _chatService.updateAdminApprovalSetting(widget.room.id, value);
      if (mounted) {
        setState(() {
          _requireAdminApproval = value;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error updating setting: $e')));
      }
    }
  }

  Widget _buildPendingRequests() {
    return StreamBuilder<QuerySnapshot>(
      stream: _chatService.getPendingJoinRequests(widget.room.id),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final requests = snapshot.data!.docs;
        if (requests.isEmpty) {
          return const Center(child: Text('No pending requests'));
        }

        return ListView.builder(
          itemCount: requests.length,
          itemBuilder: (context, index) {
            final request = requests[index].data() as Map<String, dynamic>;
            final userId = request['userId'] as String;

            if (!_userProfiles.containsKey(userId)) {
              _loadUserProfile(userId);
            }

            final userProfile = _userProfiles[userId] ?? {};
            final displayName = userProfile['displayName'] ?? 'Unknown User';
            final photoUrl = userProfile['photoURL'];

            return ListTile(
              leading: CircleAvatar(
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
                        )
                        : null,
              ),
              title: Text(displayName),
              subtitle: const Text('Requested to join'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.check, color: Colors.green),
                    onPressed: () => _handleJoinRequest(userId, true),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.red),
                    onPressed: () => _handleJoinRequest(userId, false),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildMemberList() {
    return StreamBuilder<DocumentSnapshot>(
      stream:
          _firestore.collection('chat_rooms').doc(widget.room.id).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final room = ChatRoom.fromFirestore(snapshot.data!);
        final isAdmin = room.isAdmin(_auth.currentUser?.uid ?? '');
        final currentUserId = _auth.currentUser?.uid;

        // Separate members into categories
        final List<String> adminMembers = [];
        final List<String> regularMembers = [];
        final List<String> currentUserList = [];

        // Categorize members
        for (final memberId in room.members) {
          if (memberId == currentUserId) {
            currentUserList.add(memberId);
          } else if (room.isAdmin(memberId)) {
            adminMembers.add(memberId);
          } else {
            regularMembers.add(memberId);
          }
        }

        // Filter members based on search query
        bool matchesSearch(String memberId) {
          if (!_userProfiles.containsKey(memberId)) return false;
          return _matchesSearch(_userProfiles[memberId]!);
        }

        // Apply search filter to each category
        final filteredCurrentUser =
            currentUserList.where(matchesSearch).toList();
        final filteredAdmins = adminMembers.where(matchesSearch).toList();
        final filteredRegularMembers =
            regularMembers.where(matchesSearch).toList();

        // Combine all filtered members
        final allFilteredMembers = [
          ...filteredCurrentUser,
          ...filteredAdmins,
          ...filteredRegularMembers,
        ];

        // Check if any members match the search
        final hasSearchResults =
            allFilteredMembers.isNotEmpty || _searchQuery.isEmpty;

        return Column(
          children: [
            // Search bar - always visible
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search members...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon:
                      _searchQuery.isNotEmpty
                          ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                            },
                          )
                          : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Theme.of(
                    context,
                  ).colorScheme.surfaceVariant.withOpacity(0.5),
                ),
              ),
            ),
            // Member list or no results message
            Expanded(
              child:
                  !hasSearchResults
                      ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.search_off,
                              size: 48,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withOpacity(0.5),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No members found',
                              style: Theme.of(
                                context,
                              ).textTheme.titleMedium?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withOpacity(0.7),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Try a different search term',
                              style: Theme.of(
                                context,
                              ).textTheme.bodyMedium?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withOpacity(0.5),
                              ),
                            ),
                          ],
                        ),
                      )
                      : ListView(
                        children: [
                          if (filteredCurrentUser.isNotEmpty) ...[
                            _buildSectionHeader('You'),
                            ...filteredCurrentUser.map(
                              (memberId) =>
                                  _buildMemberTile(memberId, room, true),
                            ),
                          ],
                          if (filteredAdmins.isNotEmpty) ...[
                            _buildSectionHeader('Admins'),
                            ...filteredAdmins.map(
                              (memberId) =>
                                  _buildMemberTile(memberId, room, true),
                            ),
                          ],
                          if (filteredRegularMembers.isNotEmpty) ...[
                            _buildSectionHeader('Members'),
                            ...filteredRegularMembers.map(
                              (memberId) =>
                                  _buildMemberTile(memberId, room, false),
                            ),
                          ],
                        ],
                      ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildMemberTile(String memberId, ChatRoom room, bool isAdmin) {
    if (!_userProfiles.containsKey(memberId)) {
      _loadUserProfile(memberId);
    }

    final userProfile = _userProfiles[memberId] ?? {};
    final displayName = userProfile['displayName'] ?? 'Unknown User';
    final photoUrl = userProfile['photoURL'];
    final email = userProfile['email'];
    final isMemberAdmin = room.isAdmin(memberId);
    final isCurrentUser = memberId == _auth.currentUser?.uid;
    final canManageMember =
        room.isAdmin(_auth.currentUser?.uid ?? '') && !isCurrentUser;

    return ListTile(
      leading: CircleAvatar(
        backgroundImage:
            photoUrl != null && photoUrl.isNotEmpty
                ? NetworkImage(photoUrl)
                : null,
        child:
            photoUrl == null || photoUrl.isEmpty
                ? Text(
                  displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                )
                : null,
      ),
      title: Row(
        children: [
          Expanded(child: Text(displayName)),
          if (isCurrentUser)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'You',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
            ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(isMemberAdmin ? 'Admin' : 'Member'),
          if (email != null)
            Text(
              email,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
        ],
      ),
      trailing:
          canManageMember
              ? IconButton(
                icon: const Icon(Icons.more_vert),
                onPressed: () {
                  showModalBottomSheet(
                    context: context,
                    builder:
                        (context) => Padding(
                          padding: EdgeInsets.only(
                            bottom: MediaQuery.of(context).padding.bottom + 16,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(height: 8),
                              if (!isMemberAdmin)
                                ListTile(
                                  leading: const Icon(
                                    Icons.admin_panel_settings,
                                  ),
                                  title: const Text('Make Admin'),
                                  onTap: () {
                                    Navigator.pop(context);
                                    _chatService.updateMemberRole(
                                      widget.room.id,
                                      memberId,
                                      'admin',
                                    );
                                  },
                                ),
                              if (isMemberAdmin)
                                ListTile(
                                  leading: const Icon(Icons.person_outline),
                                  title: const Text('Remove Admin'),
                                  onTap: () {
                                    Navigator.pop(context);
                                    _chatService.updateMemberRole(
                                      widget.room.id,
                                      memberId,
                                      'member',
                                    );
                                  },
                                ),
                              ListTile(
                                leading: const Icon(
                                  Icons.person_remove,
                                  color: Colors.red,
                                ),
                                title: const Text(
                                  'Remove Member',
                                  style: TextStyle(color: Colors.red),
                                ),
                                onTap: () async {
                                  Navigator.pop(context);
                                  final confirmed = await showDialog<bool>(
                                    context: context,
                                    builder:
                                        (context) => AlertDialog(
                                          title: const Text('Remove Member'),
                                          content: Text(
                                            'Are you sure you want to remove $displayName from the chat?',
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed:
                                                  () => Navigator.pop(
                                                    context,
                                                    false,
                                                  ),
                                              child: const Text('Cancel'),
                                            ),
                                            TextButton(
                                              onPressed:
                                                  () => Navigator.pop(
                                                    context,
                                                    true,
                                                  ),
                                              style: TextButton.styleFrom(
                                                foregroundColor:
                                                    Theme.of(
                                                      context,
                                                    ).colorScheme.error,
                                              ),
                                              child: const Text('Remove'),
                                            ),
                                          ],
                                        ),
                                  );

                                  if (confirmed == true && mounted) {
                                    await _chatService.removeMember(
                                      widget.room.id,
                                      memberId,
                                    );
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                  );
                },
              )
              : null,
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder:
                (context) =>
                    MemberDetailsScreen(memberId: memberId, room: widget.room),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isAdmin = widget.room.isAdmin(_auth.currentUser?.uid ?? '');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Members'),
        actions: [
          if (isAdmin)
            IconButton(
              icon: Icon(
                _showPendingRequests ? Icons.people : Icons.person_add,
              ),
              onPressed: () {
                setState(() {
                  _showPendingRequests = !_showPendingRequests;
                });
              },
            ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: theme.colorScheme.surface,
            child: Row(
              children: [
                Icon(Icons.group, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  '${widget.room.members.length} Members',
                  style: theme.textTheme.titleMedium,
                ),
                if (isAdmin) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Admin',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (isAdmin) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border(
                  bottom: BorderSide(
                    color: theme.colorScheme.outline.withOpacity(0.2),
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Room Settings', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    title: const Text('Require Admin Approval'),
                    subtitle: const Text(
                      'New members need admin approval to join',
                    ),
                    value: _requireAdminApproval,
                    onChanged: _updateAdminApproval,
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
          ],
          Expanded(
            child:
                _showPendingRequests
                    ? _buildPendingRequests()
                    : _buildMemberList(),
          ),
        ],
      ),
    );
  }
}
