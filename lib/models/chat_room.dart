import 'package:cloud_firestore/cloud_firestore.dart';

class ChatRoom {
  final String id; // Firestore document ID
  final String roomId; // Unique room identifier
  final String name;
  final String description;
  final String type; // 'topic', 'role', 'general'
  final String createdBy;
  final DateTime createdAt;
  final bool isPrivate;
  final List<String> members;
  final Map<String, dynamic>? settings;
  final DateTime lastMessageTime;
  final List<String> admins; // List of admin user IDs
  final bool requireAdminApproval; // Whether new members need admin approval
  final Map<String, dynamic> memberRoles; // Map of user IDs to their roles
  final bool isPinned; // Whether the room is pinned by the user
  final String? logoUrl; // Group logo image URL

  ChatRoom({
    required this.id,
    required this.roomId,
    required this.name,
    required this.description,
    required this.type,
    required this.createdBy,
    required this.createdAt,
    this.isPrivate = false,
    required this.members,
    this.settings,
    required this.lastMessageTime,
    required this.admins,
    this.requireAdminApproval = false,
    required this.memberRoles,
    this.isPinned = false,
    this.logoUrl,
  });

  factory ChatRoom.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ChatRoom(
      id: doc.id,
      roomId:
          data['roomId'] ??
          doc.id, // Fallback to doc.id for backward compatibility
      name: data['name'] ?? '',
      description: data['description'] ?? '',
      type: data['type'] ?? 'general',
      createdBy: data['createdBy'] ?? '',
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      isPrivate: data['isPrivate'] ?? false,
      members: List<String>.from(data['members'] ?? []),
      settings: data['settings'],
      lastMessageTime: (data['lastMessageTime'] as Timestamp).toDate(),
      admins: List<String>.from(data['admins'] ?? [data['createdBy'] ?? '']),
      requireAdminApproval: data['requireAdminApproval'] ?? false,
      memberRoles: Map<String, dynamic>.from(data['memberRoles'] ?? {}),
      isPinned: data['isPinned'] ?? false,
      logoUrl: data['logoUrl'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'roomId': roomId,
      'name': name,
      'description': description,
      'type': type,
      'createdBy': createdBy,
      'createdAt': Timestamp.fromDate(createdAt),
      'isPrivate': isPrivate,
      'members': members,
      'settings': settings,
      'lastMessageTime': Timestamp.fromDate(lastMessageTime),
      'admins': admins,
      'requireAdminApproval': requireAdminApproval,
      'memberRoles': memberRoles,
      'isPinned': isPinned,
      if (logoUrl != null && logoUrl!.isNotEmpty) 'logoUrl': logoUrl,
    };
  }

  bool isAdmin(String userId) => admins.contains(userId);
  String getMemberRole(String userId) => memberRoles[userId] ?? 'member';
}
