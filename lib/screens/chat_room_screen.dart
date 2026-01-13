import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import '../models/chat_room.dart';
import '../models/chat_message.dart';
import '../services/chat_service.dart';
import '../services/content_moderation_service.dart';
import 'chat_members_screen.dart';
import 'member_details_screen.dart';
import '../services/api_key_service.dart';
import 'package:encrypt/encrypt.dart' as encrypt;

class ChatRoomScreen extends StatefulWidget {
  final ChatRoom room;

  const ChatRoomScreen({super.key, required this.room});

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  final ChatService _chatService = ChatService();
  final ContentModerationService _moderationService =
      ContentModerationService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isOnline = true;
  Map<String, Map<String, dynamic>> _userProfiles = {};
  late ChatRoom _currentRoom;
  bool _showAIMention = false;
  String _aiPrompt = '';
  bool _isGeneratingAIResponse = false;
  bool _showMentionSuggestions = false;
  String _mentionQuery = '';
  List<Map<String, dynamic>> _mentionSuggestions = [];
  final FocusNode _messageFocusNode = FocusNode();

  String? _currentUserDisplayName;

  @override
  void initState() {
    super.initState();
    _currentRoom = widget.room;
    _joinRoom();
    _updatePresence(true);
    _loadUserProfiles();
    _listenToRoomChanges();
    _messageController.addListener(_onMessageChanged);
    _messageFocusNode.addListener(_onFocusChanged);

    _loadCurrentUserDisplayName();
  }

  @override
  void dispose() {
    _messageController.removeListener(_onMessageChanged);
    _messageFocusNode.removeListener(_onFocusChanged);
    _messageController.dispose();
    _messageFocusNode.dispose();
    _scrollController.dispose();
    _updatePresence(false);
    super.dispose();
  }

  void _onFocusChanged() {
    if (!_messageFocusNode.hasFocus) {
      setState(() {
        _showMentionSuggestions = false;
      });
    }
  }

  void _onMessageChanged() {
    final text = _messageController.text;
    final lastAtSymbol = text.lastIndexOf('@');

    if (lastAtSymbol != -1) {
      final textAfterAt = text.substring(lastAtSymbol + 1);
      final query = textAfterAt.toLowerCase();

      setState(() {
        _mentionQuery = query;
        _showMentionSuggestions = true;
      });
      _updateMentionSuggestions();
    } else {
      setState(() {
        _showMentionSuggestions = false;
      });
    }
  }

  void _updateMentionSuggestions() {
    if (!_showMentionSuggestions) return;

    final suggestions = <Map<String, dynamic>>[];
    final query = _mentionQuery.toLowerCase();

    // Add AI suggestion if query matches (for all users)
    if ('aiconai'.contains(query)) {
      suggestions.add({
        'id': 'ai',
        'name': 'AiconAI',
        'type': 'ai',
        'photoURL': null,
      });
    }

    // Add member suggestions
    for (final memberId in _currentRoom.members) {
      final profile = _userProfiles[memberId];
      if (profile != null) {
        final displayName =
            profile['displayName']?.toString().toLowerCase() ?? '';
        final email = profile['email']?.toString().toLowerCase() ?? '';

        if (displayName.contains(query) || email.contains(query)) {
          suggestions.add({
            'id': memberId,
            'name': profile['displayName'] ?? 'Anonymous',
            'type': 'member',
            'photoURL': profile['photoURL'],
            'email': profile['email'],
          });
        }
      }
    }

    // Sort suggestions: exact matches first, then partial matches
    suggestions.sort((a, b) {
      final aName = a['name'].toString().toLowerCase();
      final bName = b['name'].toString().toLowerCase();

      final aExactMatch = aName == query;
      final bExactMatch = bName == query;

      if (aExactMatch && !bExactMatch) return -1;
      if (!aExactMatch && bExactMatch) return 1;

      // For partial matches, sort by relevance (most relevant at bottom)
      final aStartsWith = aName.startsWith(query);
      final bStartsWith = bName.startsWith(query);

      if (aStartsWith && !bStartsWith) return -1;
      if (!aStartsWith && bStartsWith) return 1;

      return aName.compareTo(bName);
    });

    setState(() {
      _mentionSuggestions = suggestions;
    });
  }

  void _insertMention(Map<String, dynamic> suggestion) {
    final text = _messageController.text;
    final lastAtSymbol = text.lastIndexOf('@');
    if (lastAtSymbol == -1) return;

    final beforeAt = text.substring(0, lastAtSymbol);
    final afterQuery = text.substring(lastAtSymbol + 1 + _mentionQuery.length);
    final mentionText =
        suggestion['type'] == 'ai' ? '@AiconAI' : '@${suggestion['name']}';

    _messageController.text = '$beforeAt$mentionText $afterQuery';
    _messageController.selection = TextSelection.fromPosition(
      TextPosition(offset: _messageController.text.length),
    );

    setState(() {
      _showMentionSuggestions = false;
    });
  }

  Widget _buildMentionSuggestions() {
    if (!_showMentionSuggestions || _mentionSuggestions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.3,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Theme.of(context).colorScheme.surface,
              Theme.of(context).colorScheme.surface.withOpacity(0.95),
            ],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.primaryContainer.withOpacity(0.1),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.alternate_email,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Mention someone',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: _mentionSuggestions.length,
                itemBuilder: (context, index) {
                  final suggestion = _mentionSuggestions[index];
                  final isAI = suggestion['type'] == 'ai';

                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => _insertMention(suggestion),
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color:
                                    isAI
                                        ? Theme.of(
                                          context,
                                        ).colorScheme.secondaryContainer
                                        : Theme.of(
                                          context,
                                        ).colorScheme.surfaceVariant,
                                border: Border.all(
                                  color:
                                      isAI
                                          ? Theme.of(
                                            context,
                                          ).colorScheme.secondary
                                          : Theme.of(context)
                                              .colorScheme
                                              .outline
                                              .withOpacity(0.2),
                                  width: 1,
                                ),
                              ),
                              child: ClipOval(
                                child:
                                    isAI
                                        ? Icon(
                                          Icons.smart_toy,
                                          color:
                                              Theme.of(context)
                                                  .colorScheme
                                                  .onSecondaryContainer,
                                          size: 18,
                                        )
                                        : ClipOval(
                                          child:
                                              suggestion['photoURL'] != null &&
                                                      suggestion['photoURL']
                                                          .isNotEmpty
                                                  ? Image.network(
                                                    suggestion['photoURL'],
                                                    fit: BoxFit.cover,
                                                    errorBuilder:
                                                        (
                                                          context,
                                                          error,
                                                          stackTrace,
                                                        ) => Center(
                                                          child: Text(
                                                            suggestion['name']
                                                                    .isNotEmpty
                                                                ? suggestion['name'][0]
                                                                    .toUpperCase()
                                                                : '?',
                                                            style: TextStyle(
                                                              color:
                                                                  Theme.of(
                                                                        context,
                                                                      )
                                                                      .colorScheme
                                                                      .onSurfaceVariant,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w500,
                                                            ),
                                                          ),
                                                        ),
                                                  )
                                                  : Center(
                                                    child: Text(
                                                      suggestion['name']
                                                              .isNotEmpty
                                                          ? suggestion['name'][0]
                                                              .toUpperCase()
                                                          : '?',
                                                      style: TextStyle(
                                                        color:
                                                            Theme.of(context)
                                                                .colorScheme
                                                                .onSurfaceVariant,
                                                        fontWeight:
                                                            FontWeight.w500,
                                                      ),
                                                    ),
                                                  ),
                                        ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          suggestion['name'],
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodyMedium?.copyWith(
                                            fontWeight: FontWeight.w500,
                                            color:
                                                isAI
                                                    ? Theme.of(
                                                      context,
                                                    ).colorScheme.secondary
                                                    : Theme.of(
                                                      context,
                                                    ).colorScheme.onSurface,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (suggestion['email'] != null)
                                    Text(
                                      suggestion['email'],
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall?.copyWith(
                                        color:
                                            Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.alternate_email,
                              size: 16,
                              color: Theme.of(
                                context,
                              ).colorScheme.primary.withOpacity(0.5),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<String> _getGroqApiKey(BuildContext context) async {
    final localKey = await ApiKeyService.getGroqApiKey();
    if (localKey != null && localKey.isNotEmpty) return localKey;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return ApiKeyService.getDefaultApiKey();
    final doc =
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
    final encrypted =
        doc.data() != null && doc.data()!.containsKey('groq_api_key_encrypted')
            ? doc['groq_api_key_encrypted']
            : null;
    if (encrypted == null) return ApiKeyService.getDefaultApiKey();
    String? passphrase = await showDialog<String>(
      context: context,
      builder: (context) {
        final controller = TextEditingController();
        return AlertDialog(
          title: const Text('Enter Passphrase'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'Passphrase',
              border: OutlineInputBorder(),
            ),
            obscureText: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Decrypt'),
            ),
          ],
        );
      },
    );
    if (passphrase == null || passphrase.isEmpty)
      return ApiKeyService.getDefaultApiKey();
    try {
      final key = encrypt.Key.fromUtf8(
        passphrase.padRight(32, '0').substring(0, 32),
      );
      final iv = encrypt.IV.fromLength(16);
      final encrypter = encrypt.Encrypter(encrypt.AES(key));
      final decrypted = encrypter.decrypt64(encrypted, iv: iv);
      await ApiKeyService.setGroqApiKey(decrypted);
      return decrypted;
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to decrypt API key: ${e.toString()}')),
      );
      return ApiKeyService.getDefaultApiKey();
    }
  }

  Future<void> _generateAIResponse(String prompt) async {
    if (prompt.isEmpty) return;

    setState(() {
      _isGeneratingAIResponse = true;
    });

    try {
      // Check if the prompt is asking about ownership or creation
      final lowerPrompt = prompt.toLowerCase();
      if (lowerPrompt.contains('who owns aicon studioz') ||
          lowerPrompt.contains('who owns hireiq') ||
          lowerPrompt.contains('who created aicon studioz') ||
          lowerPrompt.contains('who created hireiq') ||
          lowerPrompt.contains('who is the owner of aicon studioz') ||
          lowerPrompt.contains('who is the owner of hireiq')) {
        // Send a direct response about ownership
        await _chatService.sendMessage(
          roomId: widget.room.id,
          content: "Aicon Studioz and HireIQ are owned by Aman Raj Srivastva.",
          metadata: {'type': 'ai_response', 'senderName': 'AiconAI'},
        );
        setState(() {
          _isGeneratingAIResponse = false;
        });
        return;
      }

      // Check if the prompt is asking about who created the AI
      if (lowerPrompt.contains('who created you') ||
          lowerPrompt.contains('who made you') ||
          lowerPrompt.contains('who developed you') ||
          lowerPrompt.contains('who are your creators')) {
        // Send a direct response about Aicon Studioz
        await _chatService.sendMessage(
          roomId: widget.room.id,
          content:
              "I am created by Aicon Studioz, a team dedicated to building innovative AI solutions.",
          metadata: {'type': 'ai_response', 'senderName': 'AiconAI'},
        );
        setState(() {
          _isGeneratingAIResponse = false;
        });
        return;
      }

      final apiKey = await _getGroqApiKey(context);
      final response = await http.post(
        Uri.parse("https://api.groq.com/openai/v1/chat/completions"),
        headers: {
          "Authorization": "Bearer $apiKey",
          "Content-Type": "application/json",
        },
        body: jsonEncode({
          "model": "llama3-70b-8192",
          "messages": [
            {
              "role": "system",
              "content":
                  "You are AiconAI, a helpful AI assistant in a chat room. Provide concise, helpful responses to user queries.",
            },
            {"role": "user", "content": prompt},
          ],
        }),
      );

      if (!mounted) return;

      final data = jsonDecode(response.body);
      final aiResponse =
          data["choices"]?[0]["message"]["content"] ??
          "Sorry, I couldn't generate a response.";

      // Send the AI response as a regular message with AI metadata
      await _chatService.sendMessage(
        roomId: widget.room.id,
        content: aiResponse,
        metadata: {'type': 'ai_response', 'senderName': 'AiconAI'},
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error generating AI response: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGeneratingAIResponse = false;
        });
      }
    }
  }

  Future<void> _joinRoom() async {
    try {
      await _chatService.joinChatRoom(widget.room.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error joining room: $e')));
      }
    }
  }

  Future<void> _updatePresence(bool isOnline) async {
    try {
      await _chatService.updateUserPresence(widget.room.id, isOnline);
    } catch (e) {
      debugPrint('Error updating presence: $e');
    }
  }

  Future<void> _sendMessage() async {
    final message = _messageController.text.trim();
    if (message.isEmpty) return;

    // Check for AI mention
    if (message.startsWith('@AiconAI')) {
      final prompt = message.substring('@AiconAI'.length).trim();
      if (prompt.isNotEmpty) {
        // First, send the user's message to AI
        await _chatService.sendMessage(
          roomId: widget.room.id,
          content: message,
          metadata: {'type': 'ai_prompt'},
        );

        _messageController.clear();

        // Then generate and send AI's response
        await _generateAIResponse(prompt);
        return;
      }
    }

    // Check if message is allowed
    final isAllowed = await _moderationService.isMessageAllowed(
      message,
      widget.room.id,
    );
    if (!isAllowed) {
      // Show a snackbar explaining the restriction
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.white),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  style: TextStyle(color: Colors.white),
                  'You are restricted from sending off-topic messages. Please keep your messages focused on professional topics.',
                ),
              ),
            ],
          ),
          backgroundColor: Theme.of(context).colorScheme.errorContainer,
          duration: const Duration(seconds: 5),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(8),
        ),
      );
      return;
    }

    try {
      await _chatService.sendMessage(roomId: widget.room.id, content: message);
      _messageController.clear();

      // Use a post-frame callback to ensure the scroll happens after the message is added
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            0, // Scroll to top since the ListView is reversed
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error sending message: $e')));
      }
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _loadUserProfiles() async {
    // Load profiles for all members
    for (final memberId in widget.room.members) {
      await _loadUserProfile(memberId);
    }
  }

  Future<void> _loadUserProfile(String userId) async {
    if (_userProfiles.containsKey(userId)) return;

    try {
      // Use ChatService to get user profile data
      final profileData = await _chatService.getUserProfileData(userId);
      if (mounted) {
        setState(() {
          _userProfiles[userId] = profileData;
        });
      }
    } catch (e) {
      debugPrint('Error loading user profile for $userId: $e');
      // Set a default profile if loading fails
      if (mounted) {
        setState(() {
          _userProfiles[userId] = {
            'displayName': 'Unknown User',
            'photoURL': null,
            'email': null,
          };
        });
      }
    }
  }

  Widget _buildOnlineUsers() {
    return StreamBuilder(
      stream: _chatService.getRoomPresence(widget.room.id),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();

        final onlineUsers =
            snapshot.data!.docs.where((doc) {
              final data = doc.data() as Map<String, dynamic>;
              return data['isOnline'] == true;
            }).length;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.circle,
                size: 8,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 4),
              Text(
                '$onlineUsers online',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildJoinScreen() {
    final theme = Theme.of(context);
    final isPending = widget.room.requireAdminApproval;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isPending ? Icons.pending_actions : Icons.group_add,
              size: 64,
              color: theme.colorScheme.primary.withOpacity(0.5),
            ),
            const SizedBox(height: 24),
            Text(
              isPending ? 'Join Request Pending' : 'Join Chat Room',
              style: theme.textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              isPending
                  ? 'Your request to join this chat room is pending admin approval.'
                  : 'Join this chat room to start chatting with other members.',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.7),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            if (!isPending)
              ElevatedButton.icon(
                onPressed: _joinRoom,
                icon: const Icon(Icons.group_add),
                label: const Text('Join Chat Room'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
              ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Go Back'),
            ),
          ],
        ),
      ),
    );
  }

  void _listenToRoomChanges() {
    _firestore.collection('chat_rooms').doc(widget.room.id).snapshots().listen((
      snapshot,
    ) {
      if (!snapshot.exists) return;

      final room = ChatRoom.fromFirestore(snapshot);
      setState(() {
        _currentRoom = room;
      });
    });
  }

  Future<void> _leaveGroup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Leave Chat Room'),
            content: const Text(
              'Are you sure you want to leave this chat room?',
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
                child: const Text('Leave'),
              ),
            ],
          ),
    );

    if (confirmed == true && mounted) {
      try {
        await _chatService.removeMember(widget.room.id, _auth.currentUser!.uid);
        if (mounted) {
          FocusScope.of(context).unfocus();
          Navigator.pop(context);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error leaving room: $e')));
        }
      }
    }
  }

  Future<void> _deleteMessage(ChatMessage message) async {
    final isAdmin = widget.room.isAdmin(_auth.currentUser?.uid ?? '');
    final isOwner = message.senderId == _auth.currentUser?.uid;

    if (!isAdmin && !isOwner) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Only admins can delete other users\' messages'),
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Delete Message'),
            content: const Text(
              'Are you sure you want to delete this message?',
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
                child: const Text('Delete'),
              ),
            ],
          ),
    );

    if (confirmed == true && mounted) {
      try {
        await _chatService.deleteMessage(message.id);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error deleting message: $e')));
        }
      }
    }
  }

  Future<void> _showChangeNameDialog() async {
    final TextEditingController nameController = TextEditingController(
      text: _currentRoom.name,
    );
    final TextEditingController descController = TextEditingController(
      text: _currentRoom.description,
    );
    final TextEditingController logoUrlController = TextEditingController(
      text: _currentRoom.logoUrl ?? '',
    );

    final initialName = _currentRoom.name;
    final initialDesc = _currentRoom.description;
    final initialLogoUrl = _currentRoom.logoUrl ?? '';

    bool hasChanged() {
      return nameController.text.trim() != initialName.trim() ||
          descController.text.trim() != initialDesc.trim() ||
          logoUrlController.text.trim() != initialLogoUrl.trim();
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder: (context, setState) {
              void onFieldChanged() => setState(() {});
              nameController.removeListener(onFieldChanged);
              descController.removeListener(onFieldChanged);
              logoUrlController.removeListener(onFieldChanged);
              nameController.addListener(onFieldChanged);
              descController.addListener(onFieldChanged);
              logoUrlController.addListener(onFieldChanged);
              return AlertDialog(
                title: const Text('Edit Room Details'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Room Name',
                        hintText: 'Enter new Room name',
                      ),
                      autofocus: true,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: descController,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                        hintText: 'Enter room description',
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: logoUrlController,
                      decoration: const InputDecoration(
                        labelText: 'Room Logo Image URL',
                        hintText: 'Paste a valid image link (https://...)',
                      ),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed:
                        hasChanged()
                            ? () {
                              if (nameController.text.trim().isNotEmpty) {
                                Navigator.pop(context, true);
                              }
                            }
                            : null,
                    child: const Text('Save'),
                  ),
                ],
              );
            },
          ),
    );

    if (confirmed == true && mounted) {
      try {
        final newName = nameController.text.trim();
        final newDesc = descController.text.trim();
        final newLogoUrl = logoUrlController.text.trim();
        await _firestore.collection('chat_rooms').doc(_currentRoom.id).update({
          'name': newName,
          'description': newDesc,
          'logoUrl': newLogoUrl,
        });

        // Determine what changed for the system message
        final nameChanged = newName != initialName.trim();
        final descChanged = newDesc != initialDesc.trim();
        final logoChanged = newLogoUrl != initialLogoUrl.trim();
        String systemMsg;
        if (nameChanged && !descChanged && !logoChanged) {
          systemMsg = 'Room name changed to "$newName"';
        } else if (!nameChanged && descChanged && !logoChanged) {
          systemMsg = 'Room description updated';
        } else if (!nameChanged && !descChanged && logoChanged) {
          systemMsg = 'Room logo updated';
        } else if (nameChanged && descChanged && !logoChanged) {
          systemMsg = 'Room name and description updated';
        } else if (nameChanged && !descChanged && logoChanged) {
          systemMsg = 'Room name and logo updated';
        } else if (!nameChanged && descChanged && logoChanged) {
          systemMsg = 'Room description and logo updated';
        } else if (nameChanged && descChanged && logoChanged) {
          systemMsg = 'Room details updated';
        } else {
          systemMsg = 'Room details updated';
        }

        // Send system message about the change
        await _chatService.sendSystemMessage(
          roomId: _currentRoom.id,
          content: systemMsg,
          type: 'group_updated',
        );

        // if (mounted) {
        //   ScaffoldMessenger.of(context).showSnackBar(
        //     const SnackBar(content: Text('Room details updated successfully')),
        //   );
        // }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error updating room details: $e')),
          );
        }
      }
    }
  }

  Future<void> _loadCurrentUserDisplayName() async {
    final User? user = _auth.currentUser;
    if (user != null) {
      try {
        final userDoc =
            await _firestore.collection('users').doc(user.uid).get();
        if (mounted) {
          setState(() {
            _currentUserDisplayName =
                userDoc.exists
                    ? (userDoc.data()?['displayName'] ??
                        user.displayName ??
                        'User')
                    : (user.displayName ?? 'User');
          });
        }
      } catch (e) {
        debugPrint('Error loading user display name: $e');
        if (mounted) {
          setState(() {
            _currentUserDisplayName = user.displayName ?? 'User';
          });
        }
      }
    }
  }

  bool _isUserMentioned(String message) {
    if (_currentUserDisplayName == null) return false;
    return message.contains('@${_currentUserDisplayName}');
  }

  Future<void> _shareRoom() async {
    final shareText =
        'Join the room "${_currentRoom.name}", id: ${_currentRoom.id}, only on HireIQ, download the app now: https://play.google.com/store/apps/details?id=com.aicon.hireiq';
    await Share.share(shareText);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isAdmin = _currentRoom.isAdmin(_auth.currentUser?.uid ?? '');
    final isMember = _currentRoom.members.contains(_auth.currentUser?.uid);

    if (!isMember) {
      return Scaffold(
        appBar: AppBar(title: Text(_currentRoom.name)),
        body: _buildJoinScreen(),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: () => _showRoomDetailsModal(context),
          child: Padding(
            padding: const EdgeInsets.only(top: 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_currentRoom.logoUrl != null &&
                    _currentRoom.logoUrl!.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(120),
                    child: Image.network(
                      _currentRoom.logoUrl!,
                      height: 38,
                      width: 38,
                      fit: BoxFit.cover,
                      errorBuilder:
                          (context, error, stackTrace) => Icon(
                            Icons.broken_image,
                            size: 28,
                            color: theme.colorScheme.primary,
                          ),
                    ),
                  )
                else
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(120),
                    ),
                    child: Icon(
                      _currentRoom.type == 'topic'
                          ? Icons.topic
                          : _currentRoom.type == 'role'
                          ? Icons.work
                          : Icons.chat,
                      color: theme.colorScheme.onPrimaryContainer,
                      size: 22,
                    ),
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_currentRoom.name),
                      Text(
                        _currentRoom.description.isNotEmpty
                            ? _currentRoom.description
                            : 'No description',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withOpacity(0.7),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          _buildOnlineUsers(),
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            position: PopupMenuPosition.under,
            icon: const Icon(Icons.more_vert),
            onSelected: (value) async {
              switch (value) {
                case 'change_name':
                  await _showChangeNameDialog();
                  break;
                case 'delete':
                  await _showDeleteConfirmation();
                  break;
                case 'members':
                  if (mounted) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder:
                            (context) => ChatMembersScreen(room: _currentRoom),
                      ),
                    );
                  }
                  break;
                case 'leave':
                  await _leaveGroup();
                  break;
                case 'share':
                  await _shareRoom();
                  break;
              }
            },
            itemBuilder:
                (context) => [
                  if (isAdmin) ...[
                    const PopupMenuItem(
                      value: 'change_name',
                      child: Row(
                        children: [
                          Icon(Icons.edit, color: Colors.blue),
                          SizedBox(width: 8),
                          Text('Edit Room Details'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline, color: Colors.red),
                          SizedBox(width: 8),
                          Text('Delete Group'),
                        ],
                      ),
                    ),
                  ],
                  const PopupMenuItem(
                    value: 'members',
                    child: Row(
                      children: [
                        Icon(Icons.people_outline),
                        SizedBox(width: 8),
                        Text('Member Details'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'share',
                    child: Row(
                      children: [
                        Icon(Icons.share, color: Colors.green),
                        SizedBox(width: 8),
                        Text('Share Room'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'leave',
                    child: Row(
                      children: [
                        Icon(Icons.exit_to_app, color: Colors.orange),
                        SizedBox(width: 8),
                        Text('Leave Group'),
                      ],
                    ),
                  ),
                ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer.withOpacity(0.1),
              border: Border(
                bottom: BorderSide(
                  color: theme.colorScheme.errorContainer.withOpacity(0.2),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.security, size: 16, color: theme.colorScheme.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Messages in this room are monitored by AI. Please keep discussions focused on professional topics like skills, career, technology, and work.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.info_outline, size: 16),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder:
                          (context) => AlertDialog(
                            title: Row(
                              children: [
                                Icon(
                                  Icons.security,
                                  color: theme.colorScheme.error,
                                ),
                                const SizedBox(width: 8),
                                const Text('Community Guidelines'),
                              ],
                            ),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Allowed Topics',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '• Skills and career development\n'
                                  '• Technical topics and technology\n'
                                  '• Companies, MNCs, and startups\n'
                                  '• Job roles and positions\n'
                                  '• Salaries and compensation\n'
                                  '• Professional development\n'
                                  '• Industry trends and news\n'
                                  '• Work-related discussions',
                                  style: theme.textTheme.bodyMedium,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Restricted Topics',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: theme.colorScheme.error,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '• Personal or private information\n'
                                  '• Politics and religion\n'
                                  '• Discrimination or harassment\n'
                                  '• Illegal activities\n'
                                  '• Spam or inappropriate content\n'
                                  '• Off-topic discussions',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.error,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Violation Consequences',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '• 1st violation: 1-hour message restriction\n'
                                  '• 2nd violation: 6-hour message restriction\n'
                                  '• 3rd violation: 24-hour message restriction\n'
                                  '• Further violations: 24-hour restrictions',
                                  style: theme.textTheme.bodyMedium,
                                ),
                              ],
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('I Understand'),
                              ),
                            ],
                          ),
                    );
                  },
                  tooltip: 'View community guidelines',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  color: theme.colorScheme.error,
                ),
              ],
            ),
          ),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () {
                FocusScope.of(context).unfocus();
                setState(() {
                  _showMentionSuggestions = false;
                });
              },
              child: StreamBuilder<List<ChatMessage>>(
                stream: _chatService.getMessages(widget.room.id),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(child: Text('Error: ${snapshot.error}'));
                  }

                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final messages = snapshot.data!;

                  // Load profiles for all message senders
                  for (final message in messages) {
                    if (!_userProfiles.containsKey(message.senderId)) {
                      _loadUserProfile(message.senderId);
                    }
                  }

                  if (messages.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.chat_bubble_outline,
                            size: 64,
                            color: theme.colorScheme.primary.withOpacity(0.5),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No messages yet',
                            style: theme.textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Be the first to start the conversation!',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurface.withOpacity(
                                0.7,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.only(top: 16, bottom: 16),
                    reverse: true,
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final message = messages[index];
                      // Ensure profile is loaded for this message
                      if (!_userProfiles.containsKey(message.senderId)) {
                        _loadUserProfile(message.senderId);
                      }
                      return _buildMessageBubble(message);
                    },
                  );
                },
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildMentionSuggestions(),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _messageController,
                          focusNode: _messageFocusNode,
                          decoration: InputDecoration(
                            hintText: 'Type a message...',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide.none,
                            ),
                            filled: true,
                            fillColor: theme.colorScheme.surfaceVariant,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                          ),
                          maxLines: null,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _sendMessage(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (_isGeneratingAIResponse)
                        const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      else
                        CircleAvatar(
                          backgroundColor: theme.colorScheme.primary,
                          child: IconButton(
                            icon: Icon(
                              Icons.send,
                              color: theme.colorScheme.onPrimary,
                            ),
                            onPressed: _sendMessage,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage message) {
    final theme = Theme.of(context);
    final isCurrentUser = message.senderId == _auth.currentUser?.uid;
    final isSystemMessage = message.senderId == 'system';
    final isAIMessage = message.metadata?['type'] == 'ai_response';
    final isAIPrompt = message.metadata?['type'] == 'ai_prompt';
    final isMentioned = _isUserMentioned(message.content);
    final isViolationNotice = message.metadata?['type'] == 'violation_notice';

    // Load profile if not already loaded
    if (!_userProfiles.containsKey(message.senderId)) {
      _loadUserProfile(message.senderId);
    }

    final userProfile = _userProfiles[message.senderId] ?? {};
    final displayName =
        isAIMessage
            ? 'AiconAI'
            : (userProfile['displayName'] ?? message.senderName);
    final photoUrl = userProfile['photoURL'];

    if (isSystemMessage) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color:
                  isViolationNotice
                      ? theme.colorScheme.errorContainer.withOpacity(0.5)
                      : theme.colorScheme.surfaceVariant.withOpacity(0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isViolationNotice)
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 16,
                    color: theme.colorScheme.error,
                  ),
                if (isViolationNotice) const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    message.content,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color:
                          isViolationNotice
                              ? theme.colorScheme.error
                              : theme.colorScheme.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    Widget _buildProfileImage() {
      if (isAIMessage) {
        return Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: theme.colorScheme.secondary.withOpacity(0.3),
              width: 1,
            ),
          ),
          child: ClipOval(
            child: Image.asset('assets/avatar.jpeg', fit: BoxFit.cover),
          ),
        );
      }

      return GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder:
                  (context) => MemberDetailsScreen(
                    memberId: message.senderId,
                    room: _currentRoom,
                  ),
            ),
          );
        },
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.transparent, width: 2),
          ),
          child: CircleAvatar(
            radius: 18,
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
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    )
                    : null,
          ),
        ),
      );
    }

    return GestureDetector(
      onLongPress: () => _deleteMessage(message),
      child: Container(
        decoration: BoxDecoration(
          color:
              isMentioned
                  ? theme.colorScheme.primaryContainer.withOpacity(0.3)
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        margin: EdgeInsets.only(left: 8, right: 8, top: 4, bottom: 4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisAlignment:
                isCurrentUser ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isCurrentUser && (isAIMessage || !isAIMessage)) ...[
                _buildProfileImage(),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Column(
                  crossAxisAlignment:
                      isCurrentUser
                          ? CrossAxisAlignment.end
                          : CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isAIMessage)
                            Icon(
                              Icons.smart_toy,
                              size: 14,
                              color: theme.colorScheme.secondary,
                            ),
                          if (isAIMessage) const SizedBox(width: 4),
                          Text(
                            displayName,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color:
                                  isAIMessage
                                      ? theme.colorScheme.secondary
                                      : theme.colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color:
                            isAIMessage
                                ? theme.colorScheme.secondaryContainer
                                    .withOpacity(0.7)
                                : (isAIPrompt
                                    ? theme.colorScheme.primaryContainer
                                        .withOpacity(0.7)
                                    : (isCurrentUser
                                        ? theme.colorScheme.primary
                                        : theme.colorScheme.surfaceVariant)),
                        borderRadius: BorderRadius.circular(16).copyWith(
                          bottomLeft:
                              isCurrentUser
                                  ? const Radius.circular(16)
                                  : const Radius.circular(4),
                          bottomRight:
                              isCurrentUser
                                  ? const Radius.circular(4)
                                  : const Radius.circular(16),
                        ),
                        border:
                            isAIMessage || isAIPrompt
                                ? Border.all(
                                  color: (isAIMessage
                                          ? theme.colorScheme.secondary
                                          : theme.colorScheme.primary)
                                      .withOpacity(0.2),
                                  width: 1,
                                )
                                : null,
                      ),
                      child: Text(
                        message.isDeleted
                            ? '[Message deleted]'
                            : message.content,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color:
                              isAIMessage
                                  ? theme.colorScheme.onSecondaryContainer
                                  : (isAIPrompt
                                      ? theme.colorScheme.onPrimaryContainer
                                      : (isCurrentUser
                                          ? theme.colorScheme.onPrimary
                                          : theme
                                              .colorScheme
                                              .onSurfaceVariant)),
                          fontStyle:
                              message.isDeleted ? FontStyle.italic : null,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isAIMessage)
                            Icon(
                              Icons.auto_awesome,
                              size: 12,
                              color: theme.colorScheme.secondary.withOpacity(
                                0.7,
                              ),
                            ),
                          if (isAIPrompt)
                            Icon(
                              Icons.chat_bubble_outline,
                              size: 12,
                              color: theme.colorScheme.primary.withOpacity(0.7),
                            ),
                          // Removed @ icon for mentions in time row
                          if (isAIMessage || isAIPrompt)
                            const SizedBox(width: 4),
                          Text(
                            _formatTimestamp(message.timestamp),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface.withOpacity(
                                0.6,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (isCurrentUser && (isAIMessage || !isAIMessage)) ...[
                const SizedBox(width: 8),
                _buildProfileImage(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }

  Future<void> _showDeleteConfirmation() async {
    final isAdmin = widget.room.isAdmin(_auth.currentUser?.uid ?? '');
    if (!isAdmin) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Delete Chat Room'),
            content: const Text(
              'Are you sure you want to delete this chat room? This action cannot be undone.',
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
                child: const Text('Delete'),
              ),
            ],
          ),
    );

    if (confirmed == true && mounted) {
      try {
        await _chatService.deleteChatRoom(widget.room.id);
        if (mounted) {
          FocusScope.of(context).unfocus();
          Navigator.pop(context);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error deleting room: $e')));
        }
      }
    }
  }

  void _showRoomDetailsModal(BuildContext context) {
    final theme = Theme.of(context);
    final isAdmin = _currentRoom.isAdmin(_auth.currentUser?.uid ?? '');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Center(
          child: FractionallySizedBox(
            widthFactor: 0.95,
            child: Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              elevation: 8,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (_currentRoom.logoUrl != null &&
                        _currentRoom.logoUrl!.isNotEmpty)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(120),
                        child: Image.network(
                          _currentRoom.logoUrl!,
                          height: 64,
                          width: 64,
                          fit: BoxFit.cover,
                          errorBuilder:
                              (context, error, stackTrace) => Icon(
                                Icons.broken_image,
                                size: 48,
                                color: theme.colorScheme.primary,
                              ),
                        ),
                      )
                    else
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(120),
                        ),
                        child: Icon(
                          _currentRoom.type == 'topic'
                              ? Icons.topic
                              : _currentRoom.type == 'role'
                              ? Icons.work
                              : Icons.chat,
                          color: theme.colorScheme.onPrimaryContainer,
                          size: 36,
                        ),
                      ),
                    const SizedBox(height: 16),
                    Text(
                      _currentRoom.name,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 120),
                      child: SingleChildScrollView(
                        child: Text(
                          _currentRoom.description.isNotEmpty
                              ? _currentRoom.description
                              : 'No description',
                          style: theme.textTheme.bodyMedium,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Divider(),
                    // Menu options
                    if (isAdmin)
                      ListTile(
                        leading: const Icon(Icons.edit, color: Colors.blue),
                        title: const Text('Edit Room Details'),
                        onTap: () {
                          Navigator.pop(context);
                          _showChangeNameDialog();
                        },
                      ),
                    if (isAdmin)
                      ListTile(
                        leading: const Icon(
                          Icons.delete_outline,
                          color: Colors.red,
                        ),
                        title: const Text('Delete Room'),
                        onTap: () {
                          Navigator.pop(context);
                          _showDeleteConfirmation();
                        },
                      ),
                    ListTile(
                      leading: const Icon(Icons.people_outline),
                      title: const Text('Member Details'),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder:
                                (context) =>
                                    ChatMembersScreen(room: _currentRoom),
                          ),
                        );
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.share, color: Colors.green),
                      title: const Text('Share Room'),
                      onTap: () {
                        Navigator.pop(context);
                        _shareRoom();
                      },
                    ),
                    ListTile(
                      leading: const Icon(
                        Icons.exit_to_app,
                        color: Colors.orange,
                      ),
                      title: const Text('Leave Group'),
                      onTap: () {
                        Navigator.pop(context);
                        _leaveGroup();
                      },
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
