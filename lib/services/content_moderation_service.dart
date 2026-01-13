import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'api_key_service.dart';

class ContentModerationService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Add new fields for tracking off-topic discussions
  static const int OFF_TOPIC_THRESHOLD =
      3; // Number of off-topic messages before warning
  static const int OFF_TOPIC_WINDOW_MINUTES =
      5; // Time window to track off-topic messages
  Map<String, List<DateTime>> _roomOffTopicMessages = {};
  Map<String, bool> _userRestrictions =
      {}; // Track active restrictions by user ID

  Future<bool> isMessageAllowed(String message, String roomId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return true;

      // Check if user is currently restricted
      if (_userRestrictions[user.uid] == true) {
        // Analyze if the message is on-topic
        final isOnTopic = await _isMessageOnTopic(message);
        if (!isOnTopic) {
          // User is restricted and trying to send off-topic message
          await _sendRestrictionMessage(roomId, user.uid);
          return false;
        } else {
          // Message is on-topic, lift the restriction
          _userRestrictions[user.uid] = false;
          await _clearUserRestriction(user.uid);
          return true;
        }
      }

      // Analyze message content using AI
      final apiKey = await ApiKeyService.getApiKeyToUse();
      if (apiKey.isEmpty) {
        // If no API key, allow message (fail open for better UX)
        return true;
      }

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
                  """You are a friendly content moderator for a professional chat room. 
              The chat room is primarily for discussing careers, technology, and work, but casual conversation is allowed.
              
              ALLOW:
              - Professional topics (skills, career, tech, work)
              - Casual greetings and small talk
              - Brief personal updates and life discussions
              - Questions about work-life balance
              - General conversation about interests
              
              RESTRICT:
              - Excessive off-topic discussions
              - Personal attacks or harassment
              - Spam or inappropriate content
              - Sensitive personal information
              - Illegal activities
              
              Analyze the message and respond with a JSON object:
              {
                "isAllowed": boolean,
                "reason": "string explaining why",
                "violationType": "none" | "off_topic" | "inappropriate" | "personal_info" | "spam",
                "severity": "low" | "medium" | "high",
                "isOffTopic": boolean
              }
              
              Use "low" severity for casual off-topic messages that are still appropriate.
              Use "medium" severity for messages that are too off-topic but not harmful.
              Use "high" severity for inappropriate or harmful content.""",
            },
            {"role": "user", "content": message},
          ],
        }),
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to analyze message');
      }

      final data = jsonDecode(response.body);
      final analysis = jsonDecode(data["choices"][0]["message"]["content"]);

      // Track off-topic messages
      if (analysis["isOffTopic"] == true) {
        _trackOffTopicMessage(roomId);
      }

      // Check if room is going off-topic
      if (_shouldWarnAboutOffTopic(roomId)) {
        await _sendOffTopicWarning(roomId);
      }

      if (!analysis["isAllowed"]) {
        if (analysis["violationType"] == "off_topic") {
          // Restrict user from sending off-topic messages
          _userRestrictions[user.uid] = true;
          await _recordOffTopicRestriction(user.uid, roomId, message, analysis);
        }
      }

      return analysis["isAllowed"];
    } catch (e) {
      print('Error in content moderation: $e');
      return true;
    }
  }

  Future<bool> _isMessageOnTopic(String message) async {
    try {
      final apiKey = await ApiKeyService.getApiKeyToUse();
      if (apiKey.isEmpty) {
        // If no API key, assume message is on-topic (fail open)
        return true;
      }

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
                  """You are a content moderator checking if a message is on-topic.
              The message should be about professional topics like:
              - Skills and career development
              - Technology and technical topics
              - Work and workplace discussions
              - Industry and market trends
              - Professional development
              
              Respond with a JSON object:
              {
                "isOnTopic": boolean,
                "reason": "string explaining why"
              }""",
            },
            {"role": "user", "content": message},
          ],
        }),
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to analyze message');
      }

      final data = jsonDecode(response.body);
      final analysis = jsonDecode(data["choices"][0]["message"]["content"]);
      return analysis["isOnTopic"];
    } catch (e) {
      print('Error checking if message is on-topic: $e');
      return true; // Allow message in case of error
    }
  }

  Future<void> _recordOffTopicRestriction(
    String userId,
    String roomId,
    String message,
    Map<String, dynamic> analysis,
  ) async {
    try {
      final userRef = _firestore.collection('users').doc(userId);

      // Update user document
      await userRef.update({
        'isRestrictedFromOffTopic': true,
        'lastOffTopicViolation': {
          'timestamp': FieldValue.serverTimestamp(),
          'message': message,
          'roomId': roomId,
          'reason': analysis["reason"],
        },
      });

      // Send system message about the restriction
      await _firestore
          .collection('chat_rooms')
          .doc(roomId)
          .collection('messages')
          .add({
            'content':
                '⚠️ A user has been restricted from sending off-topic messages. They can continue chatting about professional topics.',
            'senderId': 'system',
            'timestamp': FieldValue.serverTimestamp(),
            'type': 'restriction_notice',
            'metadata': {
              'type': 'off_topic_restriction',
              'reason': analysis["reason"],
            },
          });
    } catch (e) {
      print('Error recording off-topic restriction: $e');
    }
  }

  Future<void> _clearUserRestriction(String userId) async {
    try {
      await _firestore.collection('users').doc(userId).update({
        'isRestrictedFromOffTopic': false,
        'lastOffTopicViolation': FieldValue.delete(),
      });
    } catch (e) {
      print('Error clearing user restriction: $e');
    }
  }

  Future<void> _sendRestrictionMessage(String roomId, String userId) async {
    try {
      await _firestore
          .collection('chat_rooms')
          .doc(roomId)
          .collection('messages')
          .add({
            'content':
                '⚠️ You are currently restricted from sending off-topic messages. Please keep your messages focused on professional topics.',
            'senderId': 'system',
            'timestamp': FieldValue.serverTimestamp(),
            'type': 'restriction_notice',
            'metadata': {'type': 'active_restriction', 'userId': userId},
          });
    } catch (e) {
      print('Error sending restriction message: $e');
    }
  }

  void _trackOffTopicMessage(String roomId) {
    final now = DateTime.now();
    if (!_roomOffTopicMessages.containsKey(roomId)) {
      _roomOffTopicMessages[roomId] = [];
    }

    // Add new message timestamp
    _roomOffTopicMessages[roomId]!.add(now);

    // Remove old messages outside the window
    _roomOffTopicMessages[roomId]!.removeWhere(
      (timestamp) =>
          now.difference(timestamp).inMinutes > OFF_TOPIC_WINDOW_MINUTES,
    );
  }

  bool _shouldWarnAboutOffTopic(String roomId) {
    final messages = _roomOffTopicMessages[roomId] ?? [];
    return messages.length >= OFF_TOPIC_THRESHOLD;
  }

  Future<void> _sendOffTopicWarning(String roomId) async {
    try {
      // Clear the off-topic message count after warning
      _roomOffTopicMessages[roomId]?.clear();

      await _firestore
          .collection('chat_rooms')
          .doc(roomId)
          .collection('messages')
          .add({
            'content':
                '⚠️ The conversation is going off-topic. Please try to keep discussions focused on professional topics, skills, and career development.',
            'senderId': 'system',
            'timestamp': FieldValue.serverTimestamp(),
            'type': 'off_topic_warning',
            'metadata': {'type': 'warning', 'severity': 'low'},
          });
    } catch (e) {
      print('Error sending off-topic warning: $e');
    }
  }
}
