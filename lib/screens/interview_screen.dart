import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../services/api_key_service.dart';
import 'package:encrypt/encrypt.dart' as encrypt;

/// Helper function to format multiple-choice questions if they appear in one line.
/// This ensures each MCQ option appears on its own line for better readability.
String formatMCQs(String text) {
  // Handle different MCQ patterns:
  // 1. "a) option1 b) option2 c) option3 d) option4"
  // 2. "a. option1 b. option2 c. option3 d. option4"
  // 3. "a)option1 b)option2 c)option3 d)option4"
  // 4. "a.option1 b.option2 c.option3 d.option4"
  // 5. "a) option1, b) option2, c) option3, d) option4"
  // 6. "a. option1, b. option2, c. option3, d. option4"

  // First, split the text into lines to process each line separately
  final lines = text.split('\n');
  final formattedLines =
      lines.map((line) {
        // Look for MCQ patterns in the line
        final mcqPatterns = [
          // Pattern 1 & 2: With spaces after option markers
          RegExp(r'([a-d][.)]\s*[^a-d]+)(?:\s+[a-d][.)]\s*[^a-d]+){1,3}'),
          // Pattern 3 & 4: Without spaces after option markers
          RegExp(r'([a-d][.)][^a-d]+)(?:[a-d][.)][^a-d]+){1,3}'),
          // Pattern 5 & 6: With commas
          RegExp(r'([a-d][.)]\s*[^a-d]+)(?:,\s*[a-d][.)]\s*[^a-d]+){1,3}'),
        ];

        String processedLine = line;
        for (final pattern in mcqPatterns) {
          processedLine = processedLine.replaceAllMapped(pattern, (match) {
            final mcqText = match.group(0)!;
            // Split by option markers (a., b., c., d. or a), b), c), d))
            final options = mcqText.split(RegExp(r'(?:,\s*)?(?=[a-d][.)])'));
            // Clean up each option and join with newlines
            return options
                .map((opt) => opt.trim())
                .where((opt) => opt.isNotEmpty)
                .join('\n');
          });
        }
        return processedLine;
      }).toList();

  return formattedLines.join('\n');
}

/// Helper function to check if a message contains MCQs
bool containsMCQs(String text) {
  final mcqPatterns = [
    // Pattern 1 & 2: With spaces after option markers
    RegExp(r'([a-d][.)]\s*[^a-d]+)(?:\s+[a-d][.)]\s*[^a-d]+){1,3}'),
    // Pattern 3 & 4: Without spaces after option markers
    RegExp(r'([a-d][.)][^a-d]+)(?:[a-d][.)][^a-d]+){1,3}'),
    // Pattern 5 & 6: With commas
    RegExp(r'([a-d][.)]\s*[^a-d]+)(?:,\s*[a-d][.)]\s*[^a-d]+){1,3}'),
  ];

  return mcqPatterns.any((pattern) => pattern.hasMatch(text));
}

/// Helper function to extract MCQ options from text
List<String> extractMCQOptions(String text) {
  final formattedText = formatMCQs(text);
  final options = formattedText.split('\n');
  return options
      .where((option) {
        final trimmed = option.trim();
        return RegExp(r'^[a-d][.)]').hasMatch(trimmed) && trimmed.length > 2;
      })
      .map((option) => option.trim())
      .toList();
}

class InterviewScreen extends StatefulWidget {
  final String roleTitle;
  final String sessionId;

  const InterviewScreen({
    Key? key,
    required this.roleTitle,
    required this.sessionId,
  }) : super(key: key);

  @override
  State<InterviewScreen> createState() => _InterviewScreenState();
}

class _InterviewScreenState extends State<InterviewScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<Map<String, dynamic>> _messages = [];
  final List<Map<String, dynamic>> _responses = [];

  bool _isSending = false;
  bool _interviewStarted = false;
  bool _hasText = false;
  late AnimationController _animationController;
  bool _isReportVisible = false;
  bool _isEvaluating = false;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String? _selectedMCQOption;
  bool _isMCQQuestion = false;

  @override
  void initState() {
    super.initState();
    _messageController.addListener(_onTextChanged);
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _loadUserData();
  }

  void _onTextChanged() {
    setState(() {
      _hasText = _messageController.text.trim().isNotEmpty;
    });
  }

  Future<void> _loadUserData() async {
    try {
      final User? user = _auth.currentUser;
      if (user != null) {
        _startInterview();
      }
    } catch (e) {
      debugPrint('Error loading user data: $e');
    }
  }

  void _startInterview() async {
    setState(() => _isSending = true);
    await _sendBotMessage(
      "Start the interview with a relevant question for the role of ${widget.roleTitle}. Be concise and professional.",
    );
  }

  Future<String> _getGroqApiKey(BuildContext context) async {
    // Try local first
    final localKey = await ApiKeyService.getGroqApiKey();
    if (localKey != null && localKey.isNotEmpty) return localKey;

    // Try cloud (prompt for passphrase)
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
      // Optionally store locally for future use
      await ApiKeyService.setGroqApiKey(decrypted);
      return decrypted;
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to decrypt API key: ${e.toString()}')),
      );
      return ApiKeyService.getDefaultApiKey();
    }
  }

  Future<void> _sendBotMessage(String userPrompt, {bool isSkip = false}) async {
    try {
      setState(() {
        _isSending = true;
        _selectedMCQOption = null;
        _isMCQQuestion = false;
      });

      // Check if the prompt is asking about ownership or creation
      final lowerPrompt = userPrompt.toLowerCase();
      if (lowerPrompt.contains('who owns aicon studioz') ||
          lowerPrompt.contains('who owns hireiq') ||
          lowerPrompt.contains('who created aicon studioz') ||
          lowerPrompt.contains('who created hireiq') ||
          lowerPrompt.contains('who is the owner of aicon studioz') ||
          lowerPrompt.contains('who is the owner of hireiq')) {
        // Add a small delay to simulate thinking time
        await Future.delayed(const Duration(milliseconds: 800));
        setState(() {
          _messages.add({
            'sender': 'bot',
            'text': "Aicon Studioz and HireIQ are owned by Aman Raj Srivastva.",
            'timestamp': DateTime.now(),
          });
          _isSending = false;
          _interviewStarted = true;
        });
        _scrollToBottom();
        return;
      }

      // Check if the prompt is asking about who created the AI
      if (lowerPrompt.contains('who created you') ||
          lowerPrompt.contains('who made you') ||
          lowerPrompt.contains('who developed you') ||
          lowerPrompt.contains('who are your creators')) {
        // Add a small delay to simulate thinking time
        await Future.delayed(const Duration(milliseconds: 800));
        setState(() {
          _messages.add({
            'sender': 'bot',
            'text':
                "I am created by Aicon Studioz, a team dedicated to building innovative AI solutions.",
            'timestamp': DateTime.now(),
          });
          _isSending = false;
          _interviewStarted = true;
        });
        _scrollToBottom();
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
                  "You are an AI interviewer for the role of ${widget.roleTitle}. "
                  "Ask a mix of technical and behavioral questions, including occasional MCQs. "
                  "Keep questions concise and professional.",
            },
            ..._messages.map(
              (msg) => {
                "role": msg['sender'] == 'user' ? 'user' : 'assistant',
                "content": msg['text'],
              },
            ),
            {"role": "user", "content": userPrompt},
          ],
        }),
      );

      if (!mounted) return;

      final data = jsonDecode(response.body);
      final botReply =
          data["choices"]?[0]["message"]["content"] ?? "No reply received";

      // Add a small delay to simulate thinking time
      await Future.delayed(const Duration(milliseconds: 500));

      setState(() {
        _messages.add({
          'sender': 'bot',
          'text': botReply,
          'timestamp': DateTime.now(),
        });
        _isSending = false;
        _interviewStarted = true;
        _isMCQQuestion = containsMCQs(botReply);
      });

      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.add({
          'sender': 'bot',
          'text': "Error: ${e.toString()}",
          'timestamp': DateTime.now(),
        });
        _isSending = false;
      });
    }
  }

  void _handleMCQSelection(String option) {
    setState(() {
      _selectedMCQOption = option;
    });
    _sendMessage(option);
  }

  Future<void> _sendMessage([String? selectedOption]) async {
    final userMessage = selectedOption ?? _messageController.text.trim();
    if (userMessage.isEmpty || _isSending) return;

    final lastBot = _getLastBotMessage();

    setState(() {
      _messages.add({
        'sender': 'user',
        'text': userMessage,
        'timestamp': DateTime.now(),
      });
      _responses.add({
        'question': lastBot,
        'answer': userMessage,
        'evaluation': null,
        'isEvaluated': false,
        'isEvaluating': false,
        'isSkipped': false,
      });
      _messageController.clear();
      _isSending = true;
      _hasText = false;
      _selectedMCQOption = null;
      _isMCQQuestion = false;
    });

    await _sendBotMessage(userMessage);
  }

  void _skipQuestion() {
    final lastBot = _getLastBotMessage();
    setState(() {
      _responses.add({
        'question': lastBot,
        'answer': 'Skipped',
        'evaluation': null,
        'isEvaluated': false,
        'isEvaluating': false,
        'isSkipped': true,
      });
      _isSending = true;
    });
    _sendBotMessage("Skip this question and ask another.", isSkip: true);
  }

  String _getLastBotMessage() {
    for (var i = _messages.length - 1; i >= 0; i--) {
      if (_messages[i]['sender'] == 'bot') {
        return _messages[i]['text'];
      }
    }
    return "";
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _formatTimestamp(DateTime timestamp) {
    final hour = timestamp.hour.toString().padLeft(2, '0');
    final minute = timestamp.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  Future<void> _evaluateResponse(
    Map<String, dynamic> response,
    StateSetter setModalState,
  ) async {
    if (response['isSkipped'] || response['isEvaluating']) return;

    setModalState(() {
      response['isEvaluating'] = true;
      _isEvaluating = true;
    });

    try {
      final apiKey = await _getGroqApiKey(context);
      final evalResponse = await http.post(
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
                  "Evaluate the answer for the question. "
                  "Provide concise feedback (1-2 sentences) and a score from 0-10.",
            },
            {
              "role": "user",
              "content":
                  "Question: ${response['question']}\nAnswer: ${response['answer']}\n"
                  "Is this correct? Provide feedback and score.",
            },
          ],
        }),
      );

      final data = jsonDecode(evalResponse.body);
      final evaluation =
          data["choices"]?[0]["message"]["content"] ??
          "No evaluation available";

      if (mounted) {
        setModalState(() {
          response['evaluation'] = evaluation;
          response['isEvaluated'] = true;
          response['isEvaluating'] = false;
          _isEvaluating = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setModalState(() {
          response['evaluation'] = "Evaluation error: ${e.toString()}";
          response['isEvaluated'] = true;
          response['isEvaluating'] = false;
          _isEvaluating = false;
        });
      }
    }
  }

  void _showResponseSheet() {
    _isReportVisible = true;
    _animationController.forward();

    bool userDismissed = false;

    final modal = showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: !_isEvaluating,
      isDismissible: false,
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        final textTheme = Theme.of(context).textTheme;
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return PopScope(
          canPop: !_isEvaluating,
          child: StatefulBuilder(
            builder: (context, setModalState) {
              return Container(
                height: MediaQuery.of(context).size.height * 0.85,
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                ),
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    if (!_isEvaluating)
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          userDismissed = true;
                          Navigator.pop(context);
                        },
                        child: Center(
                          child: Container(
                            width: 40,
                            height: 4,
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color: colorScheme.outline.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                    Text(
                      'Interview Report',
                      style: textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child:
                          _responses.isEmpty
                              ? Center(
                                child: Text(
                                  'No responses yet',
                                  style: textTheme.bodyMedium,
                                ),
                              )
                              : ListView.separated(
                                itemCount: _responses.length,
                                separatorBuilder:
                                    (context, index) =>
                                        const Divider(height: 24),
                                itemBuilder: (context, index) {
                                  final response = _responses[index];
                                  return _buildResponseCard(
                                    response,
                                    index,
                                    setModalState,
                                    colorScheme: colorScheme,
                                    textTheme: textTheme,
                                    isDark: isDark,
                                  );
                                },
                              ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );

    modal.then((_) {
      if (userDismissed && !_isEvaluating && mounted) {
        _isReportVisible = false;
        _animationController.reverse();
      }
    });
  }

  Widget _buildResponseCard(
    Map<String, dynamic> response,
    int index,
    StateSetter setModalState, {
    ColorScheme? colorScheme,
    TextTheme? textTheme,
    bool? isDark,
  }) {
    colorScheme ??= Theme.of(context).colorScheme;
    textTheme ??= Theme.of(context).textTheme;
    isDark ??= Theme.of(context).brightness == Brightness.dark;
    return Card(
      elevation: 2,
      color: colorScheme.surfaceVariant,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${index + 1}',
                    style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    response['question'],
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your Answer:',
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurface.withOpacity(0.7),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(response['answer'], style: textTheme.bodyMedium),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (response['isEvaluating']) const LinearProgressIndicator(),
            if (response['isEvaluated'] && response['evaluation'] != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _getEvaluationColor(
                    response['evaluation'],
                  ).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _getEvaluationColor(
                      response['evaluation'],
                    ).withOpacity(0.3),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      _getEvaluationIcon(response['evaluation']),
                      size: 18,
                      color: _getEvaluationColor(response['evaluation']),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        response['evaluation'],
                        style: textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (!response['isSkipped'] && !response['isEvaluated'])
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => _evaluateResponse(response, setModalState),
                  icon: Icon(
                    Icons.auto_awesome,
                    size: 18,
                    color: colorScheme.primary,
                  ),
                  label: Text(
                    'Evaluate Response',
                    style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    backgroundColor: colorScheme.primary.withOpacity(0.08),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Color _getEvaluationColor(String evaluation) {
    final lowerEval = evaluation.toLowerCase();
    if (lowerEval.contains('not correct') ||
        lowerEval.contains('incorrect') ||
        lowerEval.contains('wrong')) {
      return Colors.red;
    }
    if (lowerEval.contains('correct') ||
        lowerEval.contains('accurate') ||
        lowerEval.contains('good')) {
      return Colors.green;
    }
    return Colors.blue;
  }

  IconData _getEvaluationIcon(String evaluation) {
    final lowerEval = evaluation.toLowerCase();
    if (lowerEval.contains('not correct') || lowerEval.contains('incorrect')) {
      return Icons.close;
    }
    if (lowerEval.contains('correct') || lowerEval.contains('accurate')) {
      return Icons.check;
    }
    return Icons.info_outline;
  }

  Widget _buildMCQOptions(String question) {
    final options = extractMCQOptions(question);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children:
          options.map((option) {
            final isSelected = option == _selectedMCQOption;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: InkWell(
                onTap: () => _handleMCQSelection(option),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color:
                        isSelected
                            ? colorScheme.primary.withOpacity(0.1)
                            : colorScheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color:
                          isSelected
                              ? colorScheme.primary
                              : colorScheme.outline.withOpacity(0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color:
                                isSelected
                                    ? colorScheme.primary
                                    : colorScheme.outline.withOpacity(0.5),
                          ),
                        ),
                        child:
                            isSelected
                                ? Icon(
                                  Icons.check_circle,
                                  size: 24,
                                  color: colorScheme.primary,
                                )
                                : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          option,
                          style: textTheme.bodyMedium?.copyWith(
                            color:
                                isSelected
                                    ? colorScheme.primary
                                    : colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> message) {
    final isUser = message['sender'] == 'user';
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final timestamp = message['timestamp'] as DateTime?;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment:
                isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: [
              if (!isUser)
                Container(
                  width: 36,
                  height: 36,
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [Colors.purple[600]!, Colors.purple[800]!],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Icon(Icons.smart_toy, color: Colors.white, size: 20),
                ),
              Flexible(
                child: Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.75,
                  ),
                  child: Column(
                    crossAxisAlignment:
                        isUser
                            ? CrossAxisAlignment.end
                            : CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 14,
                          horizontal: 18,
                        ),
                        decoration: BoxDecoration(
                          color:
                              isUser
                                  ? Colors.purple[600]!
                                  : colorScheme.surfaceVariant,
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(20),
                            topRight: const Radius.circular(20),
                            bottomLeft: Radius.circular(isUser ? 20 : 8),
                            bottomRight: Radius.circular(isUser ? 8 : 20),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: (isUser
                                      ? Colors.purple[600]!
                                      : colorScheme.surfaceVariant)
                                  .withOpacity(0.2),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child:
                            isUser
                                ? Text(
                                  message['text'],
                                  style: textTheme.bodyMedium?.copyWith(
                                    color: Colors.white,
                                    fontSize: 15,
                                    height: 1.4,
                                  ),
                                )
                                : MarkdownBody(
                                  data: formatMCQs(message['text']),
                                  styleSheet: MarkdownStyleSheet(
                                    p:
                                        textTheme.bodyMedium?.copyWith(
                                          height: 1.5,
                                          color: colorScheme.onSurface,
                                        ) ??
                                        const TextStyle(),
                                    strong:
                                        textTheme.bodyMedium?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: colorScheme.onSurface,
                                        ) ??
                                        const TextStyle(),
                                    h2:
                                        textTheme.titleMedium?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: colorScheme.onSurface,
                                        ) ??
                                        const TextStyle(),
                                    listBullet:
                                        textTheme.bodyMedium?.copyWith(
                                          color: colorScheme.onSurface,
                                        ) ??
                                        const TextStyle(),
                                    blockquote:
                                        textTheme.bodyMedium?.copyWith(
                                          color: colorScheme.onSurface
                                              .withOpacity(0.7),
                                          fontStyle: FontStyle.italic,
                                        ) ??
                                        const TextStyle(),
                                    code:
                                        textTheme.bodySmall?.copyWith(
                                          fontFamily: 'monospace',
                                          color: colorScheme.primary,
                                        ) ??
                                        const TextStyle(),
                                  ),
                                ),
                      ),
                      if (timestamp != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            _formatTimestamp(timestamp),
                            style: textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurface.withOpacity(0.6),
                              fontSize: 11,
                            ),
                          ),
                        ),
                      if (!isUser &&
                          containsMCQs(message['text']) &&
                          message == _messages.last)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: _buildMCQOptions(message['text']),
                        ),
                    ],
                  ),
                ),
              ),
              if (isUser)
                Container(
                  width: 36,
                  height: 36,
                  margin: const EdgeInsets.only(left: 12),
                  child: FutureBuilder<String?>(
                    future:
                        FirebaseAuth.instance.currentUser?.photoURL != null
                            ? Future.value(
                              FirebaseAuth.instance.currentUser?.photoURL,
                            )
                            : null,
                    builder: (context, snapshot) {
                      if (snapshot.hasData && snapshot.data != null) {
                        return CircleAvatar(
                          backgroundImage: NetworkImage(snapshot.data!),
                          backgroundColor: colorScheme.surfaceVariant,
                          onBackgroundImageError: (_, __) {},
                        );
                      }
                      return Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [
                              colorScheme.secondary,
                              colorScheme.tertiary,
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: colorScheme.secondary.withOpacity(0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.person,
                          color: Colors.white,
                          size: 20,
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _messageController.removeListener(_onTextChanged);
    _animationController.dispose();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${widget.roleTitle} Interview',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.assessment_outlined,
                color: colorScheme.primary,
                size: 20,
              ),
            ),
            onPressed: _showResponseSheet,
          ),
        ],
        elevation: 0,
        backgroundColor: colorScheme.surface,
      ),
      backgroundColor: colorScheme.background,
      body: Column(
        children: [
          Expanded(
            child:
                _messages.isEmpty
                    ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: colorScheme.primaryContainer.withOpacity(
                                0.3,
                              ),
                            ),
                            child: Icon(
                              Icons.psychology,
                              size: 48,
                              color: colorScheme.primary,
                            ),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            'Preparing your interview...',
                            style: textTheme.titleMedium?.copyWith(
                              color: colorScheme.onSurface,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'We\'re crafting personalized questions for you',
                            style: textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurface.withOpacity(0.7),
                            ),
                          ),
                        ],
                      ),
                    )
                    : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.only(top: 8, bottom: 8),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        return _buildMessageBubble(_messages[index]);
                      },
                    ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              boxShadow: [
                BoxShadow(
                  color: colorScheme.shadow.withOpacity(0.1),
                  blurRadius: 12,
                  spreadRadius: 0,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              child: Row(
                children: [
                  if (_interviewStarted && !_hasText)
                    Container(
                      margin: const EdgeInsets.only(right: 12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(24),
                        onTap: _isSending ? null : _skipQuestion,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.purple[600]!,
                                Colors.purple[800]!,
                              ],
                            ),
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.skip_next,
                                size: 18,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                "Skip",
                                style: textTheme.bodyMedium?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  Expanded(
                    child: Container(
                      constraints: const BoxConstraints(maxHeight: 120),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceVariant,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: colorScheme.outline.withOpacity(0.2),
                        ),
                      ),
                      child: TextField(
                        controller: _messageController,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendMessage(),
                        maxLines: null,
                        style: textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurface,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Type your answer...',
                          hintStyle: textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurface.withOpacity(0.5),
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 16,
                          ),
                          suffixIcon:
                              _isSending
                                  ? const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  )
                                  : _hasText
                                  ? Container(
                                    margin: const EdgeInsets.all(4),
                                    child: IconButton(
                                      icon: Container(
                                        width: 32,
                                        height: 32,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          gradient: LinearGradient(
                                            colors: [
                                              Colors.purple[600]!,
                                              Colors.purple[800]!,
                                            ],
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.send,
                                          size: 18,
                                          color: Colors.white,
                                        ),
                                      ),
                                      onPressed: _sendMessage,
                                    ),
                                  )
                                  : null,
                        ),
                      ),
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
}
