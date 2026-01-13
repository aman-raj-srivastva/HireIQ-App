import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/chat_service.dart';
import '../models/chat_room.dart';
import 'chat_room_screen.dart';
import 'ai_chat_screen.dart';

class ChatRoomsScreen extends StatefulWidget {
  const ChatRoomsScreen({super.key});

  @override
  State<ChatRoomsScreen> createState() => _ChatRoomsScreenState();
}

class _ChatRoomsScreenState extends State<ChatRoomsScreen> {
  final ChatService _chatService = ChatService();
  final _searchController = TextEditingController();
  bool requireAdminApproval = false;
  OverlayEntry? _notificationOverlay;
  String? _joinedRoomId;

  @override
  void dispose() {
    _searchController.dispose();
    _removeNotification();
    super.dispose();
  }

  void _removeNotification() {
    _notificationOverlay?.remove();
    _notificationOverlay = null;
  }

  void _showJoinNotification(String roomId, String roomName) {
    _removeNotification(); // Remove any existing notification

    final overlay = Overlay.of(context);
    final renderBox = context.findRenderObject() as RenderBox;

    _notificationOverlay = OverlayEntry(
      builder:
          (context) => Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 16,
            right: 16,
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Successfully joined group',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Click to enter $roomName',
                            style: Theme.of(
                              context,
                            ).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(
                                context,
                              ).colorScheme.onPrimaryContainer.withOpacity(0.8),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: _removeNotification,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ],
                ),
              ),
            ),
          ),
    );

    overlay.insert(_notificationOverlay!);
    _joinedRoomId = roomId;

    // Auto-remove notification after 5 seconds
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) {
        _removeNotification();
      }
    });
  }

  void _showCreateRoomDialog() {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();
    final roomIdController = TextEditingController();
    final logoUrlController = TextEditingController();
    const String selectedType = 'general'; // Default type
    bool isRoomIdManuallyEdited = false;

    // Function to check if room ID exists
    Future<void> checkRoomIdExists(
      BuildContext context,
      String roomId,
      StateSetter setState,
      ValueNotifier<bool> isRoomIdExists,
    ) async {
      if (roomId.isEmpty) return;

      final existingRoom = await _chatService.getChatRoomByRoomId(roomId);
      if (context.mounted) {
        isRoomIdExists.value = existingRoom != null;
      }
    }

    // Function to update room ID based on name
    void updateRoomId(
      BuildContext context,
      String name,
      StateSetter setState,
      ValueNotifier<bool> isRoomIdExists,
    ) {
      if (!isRoomIdManuallyEdited) {
        final generatedId = name.toLowerCase().replaceAll(
          RegExp(r'[^a-z0-9]'),
          '_',
        );
        roomIdController.text = generatedId;
        checkRoomIdExists(context, generatedId, setState, isRoomIdExists);
      }
    }

    showDialog(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder: (context, setState) {
              final theme = Theme.of(context);
              final isRoomIdExists = ValueNotifier<bool>(false);

              // Listen to name changes
              nameController.addListener(() {
                updateRoomId(
                  context,
                  nameController.text,
                  setState,
                  isRoomIdExists,
                );
              });

              // Listen to room ID changes
              roomIdController.addListener(() {
                checkRoomIdExists(
                  context,
                  roomIdController.text,
                  setState,
                  isRoomIdExists,
                );
              });

              return AlertDialog(
                title: const Text('Create Chat Room'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'Room Name',
                          hintText: 'Enter room name',
                        ),
                      ),
                      const SizedBox(height: 16),
                      ValueListenableBuilder<bool>(
                        valueListenable: isRoomIdExists,
                        builder: (context, exists, _) {
                          return TextField(
                            controller: roomIdController,
                            decoration: InputDecoration(
                              labelText: 'Room ID',
                              hintText: 'Enter unique room ID',
                              helperText:
                                  exists
                                      ? 'This room ID is already taken'
                                      : 'This will be used to identify your room',
                              helperStyle: TextStyle(
                                color:
                                    exists
                                        ? theme.colorScheme.error
                                        : theme.colorScheme.onSurface
                                            .withOpacity(0.7),
                              ),
                              errorText:
                                  exists
                                      ? 'A room with this ID already exists'
                                      : null,
                            ),
                            onChanged: (value) {
                              setState(() {
                                isRoomIdManuallyEdited = true;
                              });
                            },
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: logoUrlController,
                        decoration: const InputDecoration(
                          labelText: 'Group Logo Image URL',
                          hintText: 'Paste a valid image link (https://...)',
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: descriptionController,
                        decoration: const InputDecoration(
                          labelText: 'Description',
                          hintText: 'Enter room description',
                        ),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 16),
                      SwitchListTile(
                        title: const Text('Require Admin Approval'),
                        subtitle: const Text(
                          'New members need admin approval to join',
                        ),
                        value: requireAdminApproval,
                        onChanged: (value) {
                          setState(() {
                            requireAdminApproval = value;
                          });
                        },
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  ValueListenableBuilder<bool>(
                    valueListenable: isRoomIdExists,
                    builder: (context, exists, _) {
                      return ElevatedButton(
                        onPressed:
                            exists
                                ? null
                                : () async {
                                  if (nameController.text.isNotEmpty &&
                                      roomIdController.text.isNotEmpty) {
                                    try {
                                      await _chatService.createChatRoom(
                                        name: nameController.text,
                                        description: descriptionController.text,
                                        type: selectedType,
                                        requireAdminApproval:
                                            requireAdminApproval,
                                        roomId: roomIdController.text,
                                        logoUrl: logoUrlController.text,
                                      );
                                      if (context.mounted)
                                        Navigator.pop(context);
                                    } catch (e) {
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              'Error creating room: $e',
                                            ),
                                          ),
                                        );
                                      }
                                    }
                                  }
                                },
                        child: const Text('Create'),
                      );
                    },
                  ),
                ],
              );
            },
          ),
    );
  }

  Future<void> _handleJoinRoom(ChatRoom room) async {
    try {
      await _chatService.joinChatRoom(room.id);
      if (mounted) {
        if (room.requireAdminApproval) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Join request sent successfully')),
          );
        } else {
          _showJoinNotification(room.id, room.name);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error joining room: $e')));
      }
    }
  }

  Future<void> _handlePinRoom(ChatRoom room) async {
    try {
      await _chatService.togglePinChatRoom(room.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              room.isPinned ? 'Room unpinned' : 'Room pinned to top',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error toggling pin: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: () {
        // If there's a notification showing and user taps the screen,
        // navigate to the joined room
        if (_notificationOverlay != null && _joinedRoomId != null) {
          _removeNotification();
          _chatService.getChatRoomByRoomId(_joinedRoomId!).then((room) {
            if (room != null && mounted) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ChatRoomScreen(room: room),
                ),
              );
            }
          });
        }
      },
      behavior: HitTestBehavior.translucent,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Chat Rooms'),
          elevation: 0,
          centerTitle: true,
        ),
        body: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusScope.of(context).unfocus(),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16.0),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  boxShadow: [
                    BoxShadow(
                      color: theme.shadowColor.withOpacity(0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // AI Chat Card
                    Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                          color: theme.colorScheme.outline.withOpacity(0.2),
                        ),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () {
                          // Navigate to AI chat screen
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const AIChatScreen(),
                            ),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primaryContainer,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  Icons.smart_toy,
                                  color: theme.colorScheme.onPrimaryContainer,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Chat with AI',
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Get instant help and answers',
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            color: theme.colorScheme.onSurface
                                                .withOpacity(0.7),
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.arrow_forward_ios,
                                size: 16,
                                color: theme.colorScheme.onSurface.withOpacity(
                                  0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // Search Bar
                    TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText:
                            _searchController.text.isEmpty
                                ? 'Search your groups...'
                                : 'Search for groups by name or ID...',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: theme.colorScheme.surfaceVariant.withOpacity(
                          0.5,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      onChanged: (value) {
                        setState(() {});
                      },
                    ),
                  ],
                ),
              ),
              Expanded(
                child: StreamBuilder<List<ChatRoom>>(
                  stream:
                      _searchController.text.isEmpty
                          ? _chatService
                              .getUserChatRooms() // New method to get only user's rooms
                          : _chatService.searchChatRooms(
                            _searchController.text,
                          ),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.error_outline,
                              size: 48,
                              color: theme.colorScheme.error,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Error: ${snapshot.error}',
                              style: theme.textTheme.titleMedium,
                            ),
                          ],
                        ),
                      );
                    }

                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final rooms = snapshot.data!;
                    // Filter out AI chat room
                    final filteredRooms =
                        rooms.where((room) => room.type != 'ai_chat').toList();
                    if (filteredRooms.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _searchController.text.isEmpty
                                  ? Icons.group_outlined
                                  : Icons.search_off,
                              size: 64,
                              color: theme.colorScheme.primary.withOpacity(0.5),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _searchController.text.isEmpty
                                  ? 'No Groups Yet'
                                  : 'No groups found',
                              style: theme.textTheme.titleLarge,
                            ),
                            const SizedBox(height: 8),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 32,
                              ),
                              child: Text(
                                _searchController.text.isEmpty
                                    ? 'You haven\'t joined any groups yet. Search for groups to join or create your own!'
                                    : 'Try a different search term or create a new group',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurface
                                      .withOpacity(0.7),
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            ElevatedButton.icon(
                              onPressed: _showCreateRoomDialog,
                              icon: const Icon(Icons.add),
                              label: const Text('Create New Group'),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.only(
                        left: 16,
                        right: 16,
                        top: 16,
                        bottom: 80,
                      ),
                      itemCount: filteredRooms.length,
                      itemBuilder: (context, index) {
                        final room = filteredRooms[index];
                        final isMember = room.members.contains(
                          _chatService.currentUserId,
                        );

                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(
                              color: theme.colorScheme.outline.withOpacity(0.2),
                            ),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap:
                                isMember
                                    ? () {
                                      FocusScope.of(context).unfocus();
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder:
                                              (context) =>
                                                  ChatRoomScreen(room: room),
                                        ),
                                      );
                                    }
                                    : null,
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      if (room.logoUrl != null &&
                                          room.logoUrl!.isNotEmpty)
                                        Container(
                                          width: 48,
                                          height: 48,
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            color:
                                                theme
                                                    .colorScheme
                                                    .primaryContainer,
                                          ),
                                          clipBehavior: Clip.antiAlias,
                                          child: Image.network(
                                            room.logoUrl!,
                                            fit: BoxFit.cover,
                                            errorBuilder:
                                                (
                                                  context,
                                                  error,
                                                  stackTrace,
                                                ) => Icon(
                                                  Icons.broken_image,
                                                  color:
                                                      theme
                                                          .colorScheme
                                                          .onPrimaryContainer,
                                                ),
                                          ),
                                        )
                                      else
                                        Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color:
                                                theme
                                                    .colorScheme
                                                    .primaryContainer,
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          child: Icon(
                                            room.type == 'topic'
                                                ? Icons.topic
                                                : room.type == 'role'
                                                ? Icons.work
                                                : Icons.chat,
                                            color:
                                                theme
                                                    .colorScheme
                                                    .onPrimaryContainer,
                                          ),
                                        ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    room.name,
                                                    style: theme
                                                        .textTheme
                                                        .titleMedium
                                                        ?.copyWith(
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                  ),
                                                ),
                                                if (isMember)
                                                  IconButton(
                                                    icon: Icon(
                                                      room.isPinned
                                                          ? Icons.push_pin
                                                          : Icons
                                                              .push_pin_outlined,
                                                      color:
                                                          room.isPinned
                                                              ? theme
                                                                  .colorScheme
                                                                  .primary
                                                              : theme
                                                                  .colorScheme
                                                                  .onSurface
                                                                  .withOpacity(
                                                                    0.7,
                                                                  ),
                                                    ),
                                                    onPressed:
                                                        () => _handlePinRoom(
                                                          room,
                                                        ),
                                                    tooltip:
                                                        room.isPinned
                                                            ? 'Unpin room'
                                                            : 'Pin room',
                                                    padding: EdgeInsets.zero,
                                                    constraints:
                                                        const BoxConstraints(),
                                                  ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                color:
                                                    theme
                                                        .colorScheme
                                                        .secondaryContainer,
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: Text(
                                                'ID: ${room.roomId}',
                                                style: theme.textTheme.bodySmall
                                                    ?.copyWith(
                                                      color:
                                                          theme
                                                              .colorScheme
                                                              .onSecondaryContainer,
                                                    ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (!isMember)
                                        ElevatedButton(
                                          onPressed:
                                              () => _handleJoinRoom(room),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor:
                                                theme.colorScheme.primary,
                                            foregroundColor:
                                                theme.colorScheme.onPrimary,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 16,
                                              vertical: 8,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                          ),
                                          child: Text(
                                            room.requireAdminApproval
                                                ? 'Request'
                                                : 'Join',
                                          ),
                                        ),
                                    ],
                                  ),
                                  if (room.description.isNotEmpty) ...[
                                    const SizedBox(height: 12),
                                    Text(
                                      room.description,
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            color: theme.colorScheme.onSurface
                                                .withOpacity(0.7),
                                          ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                  const SizedBox(height: 12),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.people,
                                            size: 16,
                                            color: theme.colorScheme.onSurface
                                                .withOpacity(0.7),
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            '${room.members.length} members',
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                                  color: theme
                                                      .colorScheme
                                                      .onSurface
                                                      .withOpacity(0.7),
                                                ),
                                          ),
                                          const SizedBox(width: 16),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color:
                                                  theme
                                                      .colorScheme
                                                      .tertiaryContainer,
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              room.type.toUpperCase(),
                                              style: theme.textTheme.bodySmall
                                                  ?.copyWith(
                                                    color:
                                                        theme
                                                            .colorScheme
                                                            .onTertiaryContainer,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (room.requireAdminApproval &&
                                          !isMember)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color:
                                                theme
                                                    .colorScheme
                                                    .primaryContainer,
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.admin_panel_settings,
                                                size: 14,
                                                color:
                                                    theme
                                                        .colorScheme
                                                        .onPrimaryContainer,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                'Admin Approval',
                                                style: theme.textTheme.bodySmall
                                                    ?.copyWith(
                                                      color:
                                                          theme
                                                              .colorScheme
                                                              .onPrimaryContainer,
                                                    ),
                                              ),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        floatingActionButton: StreamBuilder<List<ChatRoom>>(
          stream: _chatService.getUserChatRooms(),
          builder: (context, snapshot) {
            if (snapshot.hasData && snapshot.data!.isNotEmpty) {
              return FloatingActionButton.extended(
                onPressed: _showCreateRoomDialog,
                icon: const Icon(Icons.add),
                label: const Text('New Group'),
                elevation: 2,
              );
            }
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }
}
