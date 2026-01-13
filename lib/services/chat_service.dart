import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/chat_room.dart';
import '../models/chat_message.dart';
import 'package:flutter/foundation.dart';

class ChatService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? get currentUserId => _auth.currentUser?.uid;

  // Helper method to generate room ID from name
  String _generateRoomId(String name) {
    return name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');
  }

  // Check if room ID exists
  Future<bool> _roomIdExists(String roomId) async {
    final query =
        await _firestore
            .collection('chat_rooms')
            .where('roomId', isEqualTo: roomId)
            .get();
    return query.docs.isNotEmpty;
  }

  // Chat Room Operations
  Future<String> createChatRoom({
    required String name,
    required String description,
    required String type,
    bool isPrivate = false,
    bool requireAdminApproval = false,
    Map<String, dynamic>? settings,
    String? roomId, // Optional custom room ID
    String? logoUrl,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    // Use provided room ID or generate one from name
    String finalRoomId = roomId ?? _generateRoomId(name);
    int counter = 1;
    String originalRoomId = finalRoomId;

    // Check if room ID exists and append number if it does
    while (await _roomIdExists(finalRoomId)) {
      if (roomId != null) {
        throw Exception('A room with this ID already exists');
      }
      finalRoomId = '${originalRoomId}_$counter';
      counter++;
    }

    final now = DateTime.now();
    final chatRoom = ChatRoom(
      id: '', // Will be set by Firestore
      roomId: finalRoomId,
      name: name,
      description: description,
      type: type,
      createdBy: user.uid,
      createdAt: now,
      isPrivate: isPrivate,
      members: [user.uid],
      settings: settings,
      lastMessageTime: now,
      admins: [user.uid], // Creator is automatically an admin
      requireAdminApproval: requireAdminApproval,
      memberRoles: {user.uid: 'admin'}, // Creator gets admin role
      logoUrl: logoUrl,
    );

    final docRef = await _firestore
        .collection('chat_rooms')
        .add(chatRoom.toMap());
    return docRef.id;
  }

  // Get chat room by room ID
  Future<ChatRoom?> getChatRoomByRoomId(String roomId) async {
    final query =
        await _firestore
            .collection('chat_rooms')
            .where('roomId', isEqualTo: roomId)
            .get();

    if (query.docs.isEmpty) return null;
    return ChatRoom.fromFirestore(query.docs.first);
  }

  // Search chat rooms by room ID or name
  Stream<List<ChatRoom>> searchChatRooms(String searchTerm) {
    if (searchTerm.isEmpty) {
      return getChatRooms();
    }

    final searchTermLower = searchTerm.toLowerCase();
    return _firestore
        .collection('chat_rooms')
        .where('isPrivate', isEqualTo: false)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => ChatRoom.fromFirestore(doc))
              .where(
                (room) =>
                    room.roomId.toLowerCase().contains(searchTermLower) ||
                    room.name.toLowerCase().contains(searchTermLower) ||
                    room.description.toLowerCase().contains(searchTermLower),
              )
              .toList();
        });
  }

  Stream<List<ChatRoom>> getChatRooms({String? type}) {
    Query query = _firestore
        .collection('chat_rooms')
        .where('isPrivate', isEqualTo: false)
        .orderBy('lastMessageTime', descending: true);

    if (type != null) {
      query = query.where('type', isEqualTo: type);
    }

    return query.snapshots().map((snapshot) {
      return snapshot.docs.map((doc) => ChatRoom.fromFirestore(doc)).toList();
    });
  }

  Future<void> joinChatRoom(String roomId) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    final roomDoc = await _firestore.collection('chat_rooms').doc(roomId).get();
    final room = ChatRoom.fromFirestore(roomDoc);

    if (room.requireAdminApproval) {
      // Add to pending members if admin approval is required
      await _firestore
          .collection('chat_rooms')
          .doc(roomId)
          .collection('pending_members')
          .doc(user.uid)
          .set({
            'userId': user.uid,
            'requestedAt': FieldValue.serverTimestamp(),
            'status': 'pending',
          });
    } else {
      // Add directly to members if no approval needed
      await _firestore.collection('chat_rooms').doc(roomId).update({
        'members': FieldValue.arrayUnion([user.uid]),
        'memberRoles': {user.uid: 'member'},
      });
    }
  }

  Future<void> approveJoinRequest(String roomId, String userId) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    final room = await _firestore.collection('chat_rooms').doc(roomId).get();
    if (!ChatRoom.fromFirestore(room).isAdmin(user.uid)) {
      throw Exception('Only admins can approve join requests');
    }

    // Add to members
    await _firestore.collection('chat_rooms').doc(roomId).update({
      'members': FieldValue.arrayUnion([userId]),
      'memberRoles': {userId: 'member'},
    });

    // Remove from pending members
    await _firestore
        .collection('chat_rooms')
        .doc(roomId)
        .collection('pending_members')
        .doc(userId)
        .delete();
  }

  Future<void> removeMember(String roomId, String userId) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    final room = await _firestore.collection('chat_rooms').doc(roomId).get();
    final chatRoom = ChatRoom.fromFirestore(room);

    // Allow removal if user is admin or if user is removing themselves
    if (!chatRoom.isAdmin(user.uid) && user.uid != userId) {
      throw Exception('Only admins can remove other members');
    }

    // Remove from members
    await _firestore.collection('chat_rooms').doc(roomId).update({
      'members': FieldValue.arrayRemove([userId]),
      'memberRoles.$userId': FieldValue.delete(),
      'admins': FieldValue.arrayRemove([userId]),
    });
  }

  Future<void> updateMemberRole(
    String roomId,
    String userId,
    String role,
  ) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    final room = await _firestore.collection('chat_rooms').doc(roomId).get();
    if (!ChatRoom.fromFirestore(room).isAdmin(user.uid)) {
      throw Exception('Only admins can update member roles');
    }

    await _firestore.collection('chat_rooms').doc(roomId).update({
      'memberRoles.$userId': role,
      if (role == 'admin') 'admins': FieldValue.arrayUnion([userId]),
      if (role != 'admin') 'admins': FieldValue.arrayRemove([userId]),
    });
  }

  Future<void> updateAdminApprovalSetting(
    String roomId,
    bool requireAdminApproval,
  ) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    final room = await _firestore.collection('chat_rooms').doc(roomId).get();
    if (!ChatRoom.fromFirestore(room).isAdmin(user.uid)) {
      throw Exception('Only admins can update room settings');
    }

    await _firestore.collection('chat_rooms').doc(roomId).update({
      'requireAdminApproval': requireAdminApproval,
    });
  }

  Future<void> sendSystemMessage({
    required String roomId,
    required String content,
    required String type,
  }) async {
    final message = ChatMessage(
      id: '', // Will be set by Firestore
      roomId: roomId,
      senderId: 'system',
      senderName: 'System',
      content: content,
      timestamp: DateTime.now(),
      metadata: {'type': type},
    );

    await _firestore.collection('chat_messages').add(message.toMap());
  }

  // Get user profile data
  Stream<DocumentSnapshot> getUserProfile(String userId) {
    return _firestore.collection('users').doc(userId).snapshots();
  }

  // Get pending join requests
  Stream<QuerySnapshot> getPendingJoinRequests(String roomId) {
    return _firestore
        .collection('chat_rooms')
        .doc(roomId)
        .collection('pending_members')
        .snapshots();
  }

  // Message Operations
  Future<String> sendMessage({
    required String roomId,
    required String content,
    String? replyToId,
    Map<String, dynamic>? metadata,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    final now = DateTime.now();
    final message = ChatMessage(
      id: '', // Will be set by Firestore
      roomId: roomId,
      senderId: metadata?['senderName'] == 'AiconAI' ? 'ai' : user.uid,
      senderName: metadata?['senderName'] ?? (user.displayName ?? 'Anonymous'),
      content: content,
      timestamp: now,
      replyToId: replyToId,
      metadata: metadata,
    );

    final docRef = await _firestore
        .collection('chat_messages')
        .add(message.toMap());

    // Update last message time in chat room
    await _firestore.collection('chat_rooms').doc(roomId).update({
      'lastMessageTime': Timestamp.fromDate(now),
    });

    return docRef.id;
  }

  Stream<List<ChatMessage>> getMessages(String roomId) {
    return _firestore
        .collection('chat_messages')
        .where('roomId', isEqualTo: roomId)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => ChatMessage.fromFirestore(doc))
              .toList();
        });
  }

  Future<void> deleteMessage(String messageId) async {
    await _firestore.collection('chat_messages').doc(messageId).update({
      'isDeleted': true,
      'content': '[Message deleted]',
    });
  }

  // Cleanup old messages (should be called by a Cloud Function)
  Future<void> cleanupOldMessages() async {
    final now = DateTime.now();
    final cutoffTime = now.subtract(const Duration(hours: 24));

    final oldMessages =
        await _firestore
            .collection('chat_messages')
            .where('timestamp', isLessThan: Timestamp.fromDate(cutoffTime))
            .get();

    final batch = _firestore.batch();
    for (var doc in oldMessages.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

  // User presence
  Future<void> updateUserPresence(String roomId, bool isOnline) async {
    final user = _auth.currentUser;
    if (user == null) return;

    await _firestore
        .collection('chat_rooms')
        .doc(roomId)
        .collection('presence')
        .doc(user.uid)
        .set({'isOnline': isOnline, 'lastSeen': FieldValue.serverTimestamp()});
  }

  Stream<QuerySnapshot> getRoomPresence(String roomId) {
    return _firestore
        .collection('chat_rooms')
        .doc(roomId)
        .collection('presence')
        .snapshots();
  }

  Future<void> deleteChatRoom(String roomId) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    final room = await _firestore.collection('chat_rooms').doc(roomId).get();
    if (!ChatRoom.fromFirestore(room).isAdmin(user.uid)) {
      throw Exception('Only admins can delete the chat room');
    }

    // Delete all messages in the room
    final messages =
        await _firestore
            .collection('chat_messages')
            .where('roomId', isEqualTo: roomId)
            .get();

    final batch = _firestore.batch();
    for (var doc in messages.docs) {
      batch.delete(doc.reference);
    }

    // Delete the room document
    batch.delete(_firestore.collection('chat_rooms').doc(roomId));

    await batch.commit();
  }

  // Store user profile data in Firestore
  Future<void> storeUserProfileData() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final userDoc = await _firestore.collection('users').doc(user.uid).get();

      // Only update if the document doesn't exist or if the profile data is missing
      if (!userDoc.exists ||
          !userDoc.data()!.containsKey('displayName') ||
          !userDoc.data()!.containsKey('photoURL')) {
        await _firestore.collection('users').doc(user.uid).set({
          'displayName': user.displayName,
          'email': user.email,
          'photoURL': user.photoURL,
          'lastUpdated': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('Error storing user profile data: $e');
    }
  }

  // Get user profile data from Firebase Auth and Firestore
  Future<Map<String, dynamic>> getUserProfileData(String userId) async {
    try {
      Map<String, dynamic> profileData = {};

      // First try to get from Firestore users collection
      try {
        final userDoc = await _firestore.collection('users').doc(userId).get();
        if (userDoc.exists) {
          profileData = userDoc.data() ?? {};
        }
      } catch (e) {
        debugPrint('Error getting Firestore user data: $e');
      }

      // If it's the current user, get their data from Firebase Auth
      final currentUser = _auth.currentUser;
      if (currentUser != null && currentUser.uid == userId) {
        // Update Firestore with latest Auth data
        await storeUserProfileData();

        // Use Auth data as fallback
        profileData = {
          ...profileData,
          'displayName':
              currentUser.displayName ??
              profileData['displayName'] ??
              'Anonymous',
          'email': currentUser.email ?? profileData['email'],
          'photoURL': currentUser.photoURL ?? profileData['photoURL'],
        };
      }

      // If we still don't have basic profile data, try to get it from Firebase Auth
      if ((profileData['displayName'] == null ||
              profileData['photoURL'] == null) &&
          userId != currentUser?.uid) {
        try {
          // Get the user's auth data from Firestore auth collection
          final authDoc =
              await _firestore.collection('auth_users').doc(userId).get();
          if (authDoc.exists) {
            final authData = authDoc.data() ?? {};
            profileData = {
              ...profileData,
              'displayName':
                  authData['displayName'] ??
                  profileData['displayName'] ??
                  'Anonymous',
              'photoURL': authData['photoURL'] ?? profileData['photoURL'],
              'email': authData['email'] ?? profileData['email'],
            };
          }
        } catch (e) {
          debugPrint('Error getting auth user data: $e');
        }
      }

      // Ensure we have at least some display name
      if (profileData['displayName'] == null ||
          profileData['displayName'].toString().isEmpty) {
        profileData['displayName'] = 'Anonymous';
      }

      return profileData;
    } catch (e) {
      debugPrint('Error in getUserProfileData: $e');
      return {'displayName': 'Anonymous', 'email': null, 'photoURL': null};
    }
  }

  // Call this method when user signs in
  Future<void> onUserSignIn() async {
    await storeUserProfileData();
  }

  Stream<List<ChatRoom>> getUserChatRooms() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value([]);

    return _firestore
        .collection('chat_rooms')
        .where('members', arrayContains: user.uid)
        .snapshots()
        .map((snapshot) {
          final rooms =
              snapshot.docs.map((doc) => ChatRoom.fromFirestore(doc)).toList();
          // Sort rooms: pinned first, then by last message time
          rooms.sort((a, b) {
            if (a.isPinned != b.isPinned) {
              return a.isPinned ? -1 : 1;
            }
            return b.lastMessageTime.compareTo(a.lastMessageTime);
          });
          return rooms;
        });
  }

  // Toggle pin status for a chat room
  Future<void> togglePinChatRoom(String roomId) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    final roomDoc = await _firestore.collection('chat_rooms').doc(roomId).get();
    if (!roomDoc.exists) throw Exception('Chat room not found');

    final room = ChatRoom.fromFirestore(roomDoc);
    if (!room.members.contains(user.uid)) {
      throw Exception('You are not a member of this chat room');
    }

    await _firestore.collection('chat_rooms').doc(roomId).update({
      'isPinned': !room.isPinned,
    });
  }
}
