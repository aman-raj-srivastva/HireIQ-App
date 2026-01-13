import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/chat_room.dart';
import '../models/chat_message.dart';
import '../services/chat_service.dart';
import '../services/api_key_service.dart';

class AIChatScreen extends StatefulWidget {
  const AIChatScreen({super.key});

  @override
  State<AIChatScreen> createState() => _AIChatScreenState();
}

class _AIChatScreenState extends State<AIChatScreen> {
  final ChatService _chatService = ChatService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isGeneratingAIResponse = false;
  bool _isInitializing = true;
  late ChatRoom _aiRoom;
  String? _currentUserDisplayName;

  @override
  void initState() {
    super.initState();
    _initializeAIChat();
    _loadCurrentUserDisplayName();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initializeAIChat() async {
    try {
      // Create or get the AI chat room
      _aiRoom = await _createOrGetAIChatRoom();

      // Join the room
      await _chatService.joinChatRoom(_aiRoom.id);

      // Send initial AI message if room is empty
      await _sendInitialAIMessage();

      setState(() {
        _isInitializing = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error initializing AI chat: $e')),
        );
      }
    }
  }

  Future<ChatRoom> _createOrGetAIChatRoom() async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    // Check if AI chat room already exists for this user
    final userRoomsQuery =
        await _firestore
            .collection('chat_rooms')
            .where('members', arrayContains: user.uid)
            .where('type', isEqualTo: 'ai_chat')
            .limit(1)
            .get();

    if (userRoomsQuery.docs.isNotEmpty) {
      return ChatRoom.fromFirestore(userRoomsQuery.docs.first);
    }

    // Create new AI chat room
    final roomData = {
      'name': 'Chat with AiconAI',
      'description': 'Your personal AI assistant',
      'type': 'ai_chat',
      'roomId': 'ai_chat_${user.uid}',
      'members': [user.uid],
      'admins': [user.uid],
      'createdBy': user.uid,
      'createdAt': Timestamp.now(),
      'lastMessageTime': Timestamp.now(),
      'requireAdminApproval': false,
      'isPinned': false,
    };

    final docRef = await _firestore.collection('chat_rooms').add(roomData);
    return ChatRoom.fromFirestore(await docRef.get());
  }

  Future<void> _sendInitialAIMessage() async {
    // Check if there are any messages in the room
    final messagesQuery =
        await _firestore
            .collection('chat_messages')
            .where('roomId', isEqualTo: _aiRoom.id)
            .orderBy('timestamp', descending: true)
            .limit(1)
            .get();

    if (messagesQuery.docs.isEmpty) {
      // Send welcome message
      await _chatService.sendMessage(
        roomId: _aiRoom.id,
        content:
            "Hello! I'm AiconAI, your personal AI assistant. How can I help you today? I can assist you with:\n\n• Technical questions and programming help\n• Career advice and job-related queries\n• Learning new skills and technologies\n• General knowledge and information\n• Problem-solving and brainstorming\n\nFeel free to ask me anything!",
        metadata: {'type': 'ai_response', 'senderName': 'AiconAI'},
      );
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

  Future<void> _sendMessage() async {
    final message = _messageController.text.trim();
    if (message.isEmpty) return;

    setState(() {
      _isGeneratingAIResponse = true;
    });

    try {
      // Send user message
      await _chatService.sendMessage(roomId: _aiRoom.id, content: message);

      _messageController.clear();

      // Generate AI response
      await _generateAIResponse(message);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error sending message: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGeneratingAIResponse = false;
        });
      }
    }
  }

  Future<void> _generateAIResponse(String prompt) async {
    if (prompt.isEmpty) return;

    try {
      // Check if the prompt is asking about ownership or creation
      final lowerPrompt = prompt.toLowerCase();
      if (lowerPrompt.contains('who owns aicon studioz') ||
          lowerPrompt.contains('who owns hireiq') ||
          lowerPrompt.contains('who created aicon studioz') ||
          lowerPrompt.contains('who created hireiq') ||
          lowerPrompt.contains('who is the owner of aicon studioz') ||
          lowerPrompt.contains('who is the owner of hireiq')) {
        await _chatService.sendMessage(
          roomId: _aiRoom.id,
          content: "Aicon Studioz and HireIQ are owned by Aman Raj Srivastva.",
          metadata: {'type': 'ai_response', 'senderName': 'AiconAI'},
        );
        return;
      }

      // Check if the prompt is asking about who created the AI
      if (lowerPrompt.contains('who created you') ||
          lowerPrompt.contains('who made you') ||
          lowerPrompt.contains('who developed you') ||
          lowerPrompt.contains('who are your creators')) {
        await _chatService.sendMessage(
          roomId: _aiRoom.id,
          content:
              "I am created by Aicon Studioz, a team dedicated to building innovative AI solutions.",
          metadata: {'type': 'ai_response', 'senderName': 'AiconAI'},
        );
        return;
      }

      final apiKey = await ApiKeyService.getApiKeyToUse();
      if (apiKey.isEmpty) {
        await _chatService.sendMessage(
          roomId: _aiRoom.id,
          content: "Please set your Groq API key in the app settings to use AI features.",
          metadata: {'type': 'ai_response', 'senderName': 'AiconAI'},
        );
        return;
      }

      final response = await http.post(
        Uri.parse("https://api.groq.com/openai/v1/chat/completions"),
        headers: {
          "Authorization": "Bearer $apiKey",
          "Content-Type": "application/json",
        },
        body: jsonEncode({
          "model": "llama-3.1-8b-instant",
          "messages": [
            {
              "role": "system",
              "content":
                  "You are AiconAI, a helpful and friendly AI assistant. Provide concise, helpful, and engaging responses to user queries. Be conversational and supportive.",
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

      await _chatService.sendMessage(
        roomId: _aiRoom.id,
        content: aiResponse,
        metadata: {'type': 'ai_response', 'senderName': 'AiconAI'},
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error generating AI response: $e')),
        );
      }
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0, // Scroll to top since the ListView is reversed
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isInitializing) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Chat with AI'),
          elevation: 0,
          centerTitle: true,
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Initializing AI chat...'),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat with AI'),
        elevation: 0,
        centerTitle: true,
        actions: [
          Icon(Icons.smart_toy, color: theme.colorScheme.primary),
          const SizedBox(width: 16),
        ],
      ),
      body: Column(
        children: [
          // AI Info Banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer.withOpacity(0.3),
              border: Border(
                bottom: BorderSide(
                  color: theme.colorScheme.secondary.withOpacity(0.2),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.smart_toy,
                  size: 16,
                  color: theme.colorScheme.secondary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'AiconAI is here to help you with any questions or tasks!',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.secondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<List<ChatMessage>>(
              stream: _chatService.getMessages(_aiRoom.id),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }

                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final messages = snapshot.data!;

                if (messages.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Loading conversation...'),
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
                    return _buildMessageBubble(message);
                  },
                );
              },
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
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      decoration: InputDecoration(
                        hintText: 'Ask me anything...',
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
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage message) {
    final theme = Theme.of(context);
    final isCurrentUser = message.senderId == _auth.currentUser?.uid;
    final isAIMessage = message.metadata?['type'] == 'ai_response';

    return Container(
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      margin: const EdgeInsets.only(left: 8, right: 8, top: 4, bottom: 4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisAlignment:
              isCurrentUser ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isCurrentUser) ...[
              Container(
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
              ),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Column(
                crossAxisAlignment:
                    isCurrentUser
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                children: [
                  if (!isCurrentUser)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.smart_toy,
                            size: 14,
                            color: theme.colorScheme.secondary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'AiconAI',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.secondary,
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
                              : (isCurrentUser
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.surfaceVariant),
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
                          isAIMessage
                              ? Border.all(
                                color: theme.colorScheme.secondary.withOpacity(
                                  0.2,
                                ),
                                width: 1,
                              )
                              : null,
                    ),
                    child: Text(
                      message.content,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color:
                            isAIMessage
                                ? theme.colorScheme.onSecondaryContainer
                                : (isCurrentUser
                                    ? theme.colorScheme.onPrimary
                                    : theme.colorScheme.onSurfaceVariant),
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
                            color: theme.colorScheme.secondary.withOpacity(0.7),
                          ),
                        if (isAIMessage) const SizedBox(width: 4),
                        Text(
                          _formatTimestamp(message.timestamp),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withOpacity(0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (isCurrentUser) ...[
              const SizedBox(width: 8),
              CircleAvatar(
                radius: 18,
                backgroundImage:
                    _auth.currentUser?.photoURL != null
                        ? NetworkImage(_auth.currentUser!.photoURL!)
                        : null,
                child:
                    _auth.currentUser?.photoURL == null
                        ? Text(
                          _currentUserDisplayName?.isNotEmpty == true
                              ? _currentUserDisplayName![0].toUpperCase()
                              : 'U',
                          style: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                        )
                        : null,
              ),
            ],
          ],
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
}
