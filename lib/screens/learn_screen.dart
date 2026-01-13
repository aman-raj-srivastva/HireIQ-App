import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math' as math;
import 'home_screen.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:modal_bottom_sheet/modal_bottom_sheet.dart';
import '../services/api_key_service.dart';

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

class LearnScreen extends StatefulWidget {
  const LearnScreen({super.key});

  @override
  State<LearnScreen> createState() => _LearnScreenState();
}

class _LearnScreenState extends State<LearnScreen>
    with TickerProviderStateMixin {
  final TextEditingController _topicController = TextEditingController();
  final FocusNode _topicFocusNode = FocusNode();
  bool _hasValidInput = false;
  bool _isGeneratingContent = false;
  bool _showDescriptionHint = false;
  String _generatedContent = '';
  String _initialContent = '';
  bool _showContent = false;
  bool _showFullContent = false;
  bool _isLoading = true;
  Timer? _descriptionHintTimer;
  final ScrollController _scrollController = ScrollController();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  late AnimationController _loaderController;
  late Animation<double> _loaderAnimation;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _topicController.addListener(_checkInput);
    _loadUserData();

    // Initialize loader animation
    _loaderController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    _loaderAnimation = Tween<double>(
      begin: 0,
      end: 2 * math.pi,
    ).animate(_loaderController);

    // Initialize pulse animation
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _topicController.removeListener(_checkInput);
    _topicController.dispose();
    _topicFocusNode.dispose();
    _descriptionHintTimer?.cancel();
    _scrollController.dispose();
    _loaderController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  void _checkInput() {
    final isValid = _topicController.text.trim().length > 4;
    if (_hasValidInput != isValid) {
      setState(() {
        _hasValidInput = isValid;
      });
    }

    _descriptionHintTimer?.cancel();
    if (_topicController.text.trim().length > 0 &&
        _topicController.text.trim().length < 5) {
      _descriptionHintTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() {
            _showDescriptionHint = true;
          });
        }
      });
    } else {
      setState(() {
        _showDescriptionHint = false;
      });
    }
  }

  Future<void> _loadUserData() async {
    try {
      final User? user = _auth.currentUser;
      if (user != null) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading user data: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showInteractiveLearningDialog({String? topic}) {
    showModalBottomSheet(
      context: context,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder:
          (context) => Padding(
            padding: const EdgeInsets.only(top: 48),
            child: InteractiveLearningDialog(
              initialTopic: topic ?? _topicController.text.trim(),
            ),
          ),
    );
  }

  Future<bool> _validateTopic(String topic) async {
    try {
      final apiKey = await ApiKeyService.getApiKeyToUse();
      final response = await http.post(
        Uri.parse('https://api.groq.com/openai/v1/chat/completions'),
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
                  "Determine if the following topic is a valid technical/programming topic suitable for a learning guide. Respond with only 'true' or 'false'.",
            },
            {
              "role": "user",
              "content":
                  "Is '$topic' a valid technical/programming topic for a learning guide?",
            },
          ],
          "temperature": 0.3,
          "max_tokens": 10,
        }),
      );

      final data = jsonDecode(response.body);
      final validation =
          data["choices"][0]["message"]["content"].toLowerCase().trim();
      return validation == 'true';
    } catch (e) {
      return false;
    }
  }

  Future<void> _generateLearningContent({bool moreContent = false}) async {
    final topic = _topicController.text.trim();

    if (!moreContent) {
      setState(() {
        _isGeneratingContent = true;
        _showContent = false;
        _showFullContent = false;
      });

      final isValid = await _validateTopic(topic);
      if (!isValid) {
        setState(() {
          _isGeneratingContent = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Please enter a valid technical/programming topic',
            ),
            backgroundColor: Colors.red[400],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
        return;
      }
    }

    try {
      await Future.delayed(const Duration(seconds: 1));

      final apiKey = await ApiKeyService.getApiKeyToUse();
      final response = await http.post(
        Uri.parse('https://api.groq.com/openai/v1/chat/completions'),
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
                  "You are an expert technical educator. Generate comprehensive learning material in article format. "
                  "Use Markdown formatting with ### for headers, - for lists, and ``` for code blocks. "
                  "Prevent generating code blocks in the content. "
                  "If this is the first request, provide a brief introduction (about 100 words). "
                  "If this is a follow-up request, provide more detailed content expanding on the topic.",
            },
            {
              "role": "user",
              "content":
                  "Create ${moreContent ? 'detailed expanded content' : 'a brief introduction'} about $topic",
            },
          ],
          "temperature": 0.7,
          "max_tokens": moreContent ? 1500 : 300,
        }),
      );

      final data = jsonDecode(response.body);
      final content = data["choices"][0]["message"]["content"];

      if (mounted) {
        setState(() {
          if (moreContent) {
            _generatedContent += '\n\n$content';
            _showFullContent = true;
          } else {
            _initialContent = content;
            _generatedContent = content;
            _showContent = true;
          }
          _isGeneratingContent = false;
        });

        // Scroll to top when new content is loaded
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isGeneratingContent = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error generating content: ${e.toString()}'),
            backgroundColor: Colors.red[400],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    }
  }

  void _handleGenerateContent() async {
    if (_isLoading) return;

    // Dismiss keyboard
    FocusScope.of(context).unfocus();

    if (!_isGeneratingContent) {
      _generateLearningContent();
    }
  }

  void _handleSeeMore() async {
    // Dismiss keyboard
    FocusScope.of(context).unfocus();

    setState(() {
      _isGeneratingContent = true;
    });

    // Add a small delay to ensure state is updated
    await Future.delayed(const Duration(milliseconds: 100));

    if (mounted) {
      await _generateLearningContent(moreContent: true);
    }
  }

  Widget _buildMarkdownContent(String text) {
    final formattedText = formatMCQs(text);
    final lines = formattedText.split('\n');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children:
          lines.map((line) {
            if (line.startsWith('### ')) {
              return Padding(
                padding: const EdgeInsets.only(top: 16, bottom: 8),
                child: Text(
                  line.substring(4).trim(),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              );
            } else if (line.startsWith('- ') || line.startsWith('* ')) {
              return Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 4,
                  horizontal: 16,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '• ',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        line.substring(2),
                        style: TextStyle(
                          fontSize: 16,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            } else if (line.startsWith('```')) {
              final endIndex = lines.indexOf('```', lines.indexOf(line) + 1);
              if (endIndex == -1)
                return const SizedBox(); // Skip if no closing ```

              final codeLines = lines
                  .sublist(lines.indexOf(line) + 1, endIndex)
                  .join('\n');

              return Container(
                width: double.infinity,
                margin: const EdgeInsets.symmetric(vertical: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(context).dividerColor.withOpacity(0.1),
                  ),
                ),
                child: SelectableText(
                  codeLines,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              );
            } else if (line.trim().isEmpty) {
              return const SizedBox(height: 8);
            } else {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  line,
                  style: TextStyle(
                    fontSize: 16,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              );
            }
          }).toList(),
    );
  }

  Widget _buildGradientButton({
    required String text,
    required VoidCallback onPressed,
    required List<Color> colors,
    double? width,
  }) {
    return Container(
      width: width,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: colors.last.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ),
    );
  }

  Widget _buildCustomLoader({String? message}) {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.5),
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 20,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    // Outer rotating circle
                    AnimatedBuilder(
                      animation: _loaderAnimation,
                      builder: (context, child) {
                        return Transform.rotate(
                          angle: _loaderAnimation.value,
                          child: Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.blue[200]!.withOpacity(0.3),
                                width: 4,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    // Inner pulsing circle
                    AnimatedBuilder(
                      animation: _pulseAnimation,
                      builder: (context, child) {
                        return Transform.scale(
                          scale: _pulseAnimation.value,
                          child: Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: [
                                  Colors.blue[400]!,
                                  Colors.purple[400]!,
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.blue[300]!.withOpacity(0.3),
                                  blurRadius: 20,
                                  spreadRadius: 5,
                                ),
                              ],
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.auto_stories,
                                color: Colors.white,
                                size: 30,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    // Dots animation
                    ...List.generate(3, (index) {
                      return AnimatedBuilder(
                        animation: _loaderAnimation,
                        builder: (context, child) {
                          final angle =
                              _loaderAnimation.value +
                              (index * (2 * math.pi / 3));
                          final x = math.cos(angle) * 45;
                          final y = math.sin(angle) * 45;
                          return Positioned(
                            left: 40 + x,
                            top: 40 + y,
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: Colors.blue[400],
                                shape: BoxShape.circle,
                              ),
                            ),
                          );
                        },
                      );
                    }),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  message ?? 'Generating your learning guide...',
                  style: TextStyle(
                    color: Colors.grey[800],
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'This may take a few moments',
                  style: TextStyle(color: Colors.grey[600], fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGeneratingMoreLoader() {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.5),
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 20,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    // Outer rotating circle
                    AnimatedBuilder(
                      animation: _loaderAnimation,
                      builder: (context, child) {
                        return Transform.rotate(
                          angle: _loaderAnimation.value,
                          child: Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.purple[200]!.withOpacity(0.3),
                                width: 3,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    // Inner pulsing circle
                    AnimatedBuilder(
                      animation: _pulseAnimation,
                      builder: (context, child) {
                        return Transform.scale(
                          scale: _pulseAnimation.value,
                          child: Container(
                            width: 45,
                            height: 45,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: [
                                  Colors.purple[400]!,
                                  Colors.deepPurple[400]!,
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.purple[300]!.withOpacity(0.3),
                                  blurRadius: 15,
                                  spreadRadius: 3,
                                ),
                              ],
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.add,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Generating more content...',
                  style: TextStyle(
                    color: Colors.grey[800],
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuotaIndicator() {
    return const SizedBox.shrink();
  }

  Future<bool> _onWillPop() async {
    if (_showContent) {
      setState(() {
        _showContent = false;
        _generatedContent = '';
        _initialContent = '';
        _showFullContent = false;
        _topicController.clear();
      });
      return false;
    }
    // Redirect to HomeScreen
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const HomeScreen()),
      (route) => false,
    );
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Set system navigation bar color for dark mode
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        systemNavigationBarColor:
            isDark ? colorScheme.background : Colors.white,
        systemNavigationBarIconBrightness:
            isDark ? Brightness.light : Brightness.dark,
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      ),
    );
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          elevation: 0,
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          automaticallyImplyLeading: false,
          title: Text(
            _showContent
                ? 'Learning Guide: ${_topicController.text}'
                : 'Learning Center',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.bold,
              fontSize: 20,
            ),
          ),
          centerTitle: true,
          actions: [
            if (_showContent)
              IconButton(
                icon: Icon(
                  Icons.copy,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                onPressed: () async {
                  final contentToCopy =
                      _showFullContent ? _generatedContent : _initialContent;
                  await Clipboard.setData(ClipboardData(text: contentToCopy));
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('Content copied to clipboard!'),
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    );
                  }
                },
              ),
          ],
        ),
        body: Stack(
          children: [
            SingleChildScrollView(
              controller: _scrollController,
              physics: const BouncingScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!_showContent) ...[
                      const SizedBox(height: 24),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: Text(
                          'What would you like to learn today?',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onSurface,
                            height: 1.2,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Enter a topic to generate a comprehensive learning guide',
                        style: TextStyle(
                          fontSize: 16,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.6),
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Container(
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceVariant,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Theme.of(
                              context,
                            ).dividerColor.withOpacity(0.1),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Theme.of(
                                context,
                              ).shadowColor.withOpacity(0.03),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: TextField(
                          controller: _topicController,
                          focusNode: _topicFocusNode,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontSize: 16,
                          ),
                          decoration: InputDecoration(
                            hintText:
                                'e.g., Machine Learning, Flutter, Data Structures...',
                            hintStyle: TextStyle(
                              color:
                                  Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                              fontSize: 16,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 16,
                            ),
                            filled: true,
                            fillColor: Colors.transparent,
                            prefixIcon: Icon(
                              Icons.search,
                              color:
                                  Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                              size: 24,
                            ),
                          ),
                          maxLines: 1,
                          minLines: 1,
                          inputFormatters: [
                            LengthLimitingTextInputFormatter(100),
                          ],
                        ),
                      ),
                      if (_showDescriptionHint)
                        Padding(
                          padding: const EdgeInsets.only(top: 8, left: 4),
                          child: Row(
                            children: [
                              Icon(
                                Icons.info_outline,
                                size: 16,
                                color: Colors.orange[700],
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Please provide more details about your topic',
                                style: TextStyle(
                                  color: Colors.orange[700],
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 24),
                      if (_hasValidInput)
                        SizedBox(
                          width: double.infinity,
                          child: _buildGradientButton(
                            text: 'Generate Learning Guide',
                            onPressed: _handleGenerateContent,
                            colors: [Colors.blue[600]!, Colors.purple[600]!],
                          ),
                        ),
                      const SizedBox(height: 32),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceVariant,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Theme.of(
                              context,
                            ).dividerColor.withOpacity(0.1),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.trending_up,
                                  color: Colors.blue[700],
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Popular Topics',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue[700],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children:
                                  [
                                        'Flutter',
                                        'Machine Learning',
                                        'Data Structures',
                                        'Python',
                                        'React',
                                        'JavaScript',
                                      ]
                                      .map((topic) => _buildTopicChip(topic))
                                      .toList(),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (_showContent) ...[
                      const SizedBox(height: 16),
                      Container(
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Theme.of(
                                context,
                              ).shadowColor.withOpacity(0.1),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildMarkdownContent(
                                  _showFullContent
                                      ? _generatedContent
                                      : _initialContent,
                                ),
                                if (!_showFullContent) ...[
                                  const SizedBox(height: 24),
                                  _buildGradientButton(
                                    text: 'Generate More Content',
                                    onPressed: _handleSeeMore,
                                    colors: [
                                      Colors.blue[600]!,
                                      Colors.purple[600]!,
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      _buildInteractiveLearningCard(),
                    ],
                  ],
                ),
              ),
            ),
            if (_isGeneratingContent && !_showContent) _buildCustomLoader(),
            if (_isGeneratingContent && _showContent)
              _buildGeneratingMoreLoader(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopicChip(String topic) {
    return GestureDetector(
      onTap: () {
        _topicController.text = topic;
        _topicFocusNode.unfocus();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.blue[50],
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.blue[100]!),
        ),
        child: Text(
          topic,
          style: TextStyle(
            color: Colors.blue[700],
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildInteractiveLearningCard() {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        gradient:
            isDark
                ? null
                : LinearGradient(
                  colors: [Colors.purple[50]!, Colors.deepPurple[50]!],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
        color: isDark ? colorScheme.surfaceVariant : null,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color:
              isDark
                  ? colorScheme.outline.withOpacity(0.1)
                  : Colors.purple[200]!,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SafeArea(
            top: true,
            bottom: false,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? colorScheme.surface : Colors.purple[50],
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color:
                                  isDark
                                      ? colorScheme.secondaryContainer
                                      : Colors.purple[100],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.chat_bubble_outline,
                              color:
                                  isDark
                                      ? colorScheme.onSecondaryContainer
                                      : Colors.purple[700],
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Interactive Learning',
                            style: textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: isDark ? colorScheme.onSurface : null,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: isDark ? colorScheme.surfaceVariant : Colors.purple[100],
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(16),
              ),
            ),
            child: Column(
              children: [
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      _showInteractiveLearningDialog(
                        topic: _topicController.text.trim(),
                      );
                    },
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.play_circle_outline,
                            color:
                                isDark
                                    ? colorScheme.primary
                                    : Colors.purple[700],
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Start Interactive Session',
                            style: textTheme.titleMedium?.copyWith(
                              color:
                                  isDark
                                      ? colorScheme.primary
                                      : Colors.purple[700],
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class InteractiveLearningDialog extends StatefulWidget {
  final String? initialTopic;

  const InteractiveLearningDialog({super.key, this.initialTopic});

  @override
  State<InteractiveLearningDialog> createState() =>
      _InteractiveLearningDialogState();
}

class _InteractiveLearningDialogState extends State<InteractiveLearningDialog> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  bool _isLoading = false;
  String? _selectedMCQOption;
  bool _isMCQActive = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialTopic?.isNotEmpty ?? false) {
      _messages.add(
        ChatMessage(
          text:
              "I'd like to learn about " +
              widget.initialTopic! +
              ". Can you help me understand it better?",
          isUser: true,
        ),
      );
      _sendMessage(widget.initialTopic!);
    } else {
      _messages.add(
        ChatMessage(
          text:
              "Hello! I'm your AI learning assistant. What would you like to learn today?",
          isUser: false,
        ),
      );
    }
  }

  Future<void> _sendMessage([String? selectedOption]) async {
    if (_isLoading) return;

    final userMessage = selectedOption ?? _messageController.text.trim();
    if (userMessage.isEmpty) return;

    setState(() {
      _messages.add(ChatMessage(text: userMessage, isUser: true));
      _messageController.clear();
      _isLoading = true;
      _selectedMCQOption = null;
    });
    _scrollToBottom();

    // Check if the prompt is asking about ownership or creation
    final lowerPrompt = userMessage.toLowerCase();
    if (lowerPrompt.contains('who owns aicon studioz') ||
        lowerPrompt.contains('who owns hireiq') ||
        lowerPrompt.contains('who created aicon studioz') ||
        lowerPrompt.contains('who created hireiq') ||
        lowerPrompt.contains('who is the owner of aicon studioz') ||
        lowerPrompt.contains('who is the owner of hireiq')) {
      setState(() {
        _messages.add(
          ChatMessage(
            text: "Aicon Studioz and HireIQ are owned by Aman Raj Srivastva.",
            isUser: false,
          ),
        );
        _isLoading = false;
      });
      _scrollToBottom();
      return;
    }

    // Check if the prompt is asking about who created the AI
    if (lowerPrompt.contains('who created you') ||
        lowerPrompt.contains('who made you') ||
        lowerPrompt.contains('who developed you') ||
        lowerPrompt.contains('who are your creators')) {
      setState(() {
        _messages.add(
          ChatMessage(
            text:
                "I am created by Aicon Studioz, a team dedicated to building innovative AI solutions.",
            isUser: false,
          ),
        );
        _isLoading = false;
      });
      _scrollToBottom();
      return;
    }

    try {
      final apiKey = await ApiKeyService.getApiKeyToUse();
      final response = await http.post(
        Uri.parse('https://api.groq.com/openai/v1/chat/completions'),
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
                  "You are an expert technical educator. Engage in an interactive learning "
                  "session with the user. Ask clarifying questions, provide explanations, "
                  "give examples, and quiz the user to reinforce learning. Keep responses "
                  "concise but informative. For code, use markdown code blocks with syntax highlighting. "
                  "When asking multiple-choice questions, format each option on a new line with a letter (a, b, c, d) and a period, like this:\n"
                  "a. First option\n"
                  "b. Second option\n"
                  "c. Third option\n"
                  "d. Fourth option\n",
            },
            ..._messages.map(
              (m) => {
                "role": m.isUser ? "user" : "assistant",
                "content": m.text,
              },
            ),
          ],
          "temperature": 0.7,
          "max_tokens": 500,
        }),
      );

      final data = jsonDecode(response.body);
      final content = data["choices"][0]["message"]["content"];

      setState(() {
        _messages.add(ChatMessage(text: content, isUser: false));
        _isLoading = false;
        _isMCQActive = containsMCQs(content);
      });
      _scrollToBottom();
    } catch (e) {
      setState(() {
        _messages.add(
          ChatMessage(
            text: "Sorry, I encountered an error. Please try again.",
            isUser: false,
          ),
        );
        _isLoading = false;
      });
      _scrollToBottom();
    }
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

  void _handleMCQSelection(String option) {
    setState(() {
      _selectedMCQOption = option;
    });
    _sendMessage(option);
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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SafeArea(
      top: true,
      bottom: false,
      child: Material(
        color: Colors.transparent,
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
              boxShadow: [
                BoxShadow(
                  color: colorScheme.shadow.withOpacity(0.15),
                  blurRadius: 20,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: colorScheme.secondaryContainer,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  Icons.chat_bubble_outline,
                                  color: colorScheme.onSecondaryContainer,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Interactive Learning',
                                style: textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.onPrimaryContainer,
                                ),
                              ),
                            ],
                          ),
                          IconButton(
                            icon: Icon(
                              Icons.close,
                              color: colorScheme.onPrimaryContainer,
                            ),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[index];
                      final isLastAI =
                          !message.isUser &&
                          index == _messages.length - 1 &&
                          _isMCQActive;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ChatBubble(
                            text: message.text,
                            isUser: message.isUser,
                            colorScheme: colorScheme,
                            textTheme: textTheme,
                          ),
                          if (isLastAI)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: _buildMCQOptions(message.text),
                            ),
                        ],
                      );
                    },
                  ),
                ),
                if (_isLoading)
                  const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 16),
                        Text('AI is thinking...'),
                      ],
                    ),
                  ),
                SafeArea(
                  minimum: EdgeInsets.only(
                    left: 16,
                    right: 16,
                    bottom: MediaQuery.of(context).padding.bottom + 16,
                    top: 16,
                  ),
                  top: false,
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _messageController,
                          enabled: !_isMCQActive,
                          decoration: InputDecoration(
                            hintText:
                                _isMCQActive
                                    ? 'Select an option above...'
                                    : 'Type your message...',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide.none,
                            ),
                            filled: true,
                            fillColor: colorScheme.surfaceVariant,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                          ),
                          onSubmitted: (text) => _sendMessage(text),
                        ),
                      ),
                      const SizedBox(width: 8),
                      CircleAvatar(
                        backgroundColor: colorScheme.primary,
                        child: IconButton(
                          icon: Icon(Icons.send, color: colorScheme.onPrimary),
                          onPressed:
                              _isMCQActive
                                  ? null
                                  : () => _sendMessage(_messageController.text),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ChatMessage {
  final String text;
  final bool isUser;

  ChatMessage({required this.text, required this.isUser});
}

class ChatBubble extends StatelessWidget {
  final String text;
  final bool isUser;
  final ColorScheme colorScheme;
  final TextTheme textTheme;

  const ChatBubble({
    super.key,
    required this.text,
    required this.isUser,
    required this.colorScheme,
    required this.textTheme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isUser)
            CircleAvatar(
              backgroundColor: colorScheme.secondaryContainer,
              child: Icon(
                Icons.smart_toy,
                color: colorScheme.onSecondaryContainer,
              ),
            ),
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color:
                    isUser ? colorScheme.primary : colorScheme.surfaceVariant,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(12),
                  topRight: const Radius.circular(12),
                  bottomLeft: Radius.circular(isUser ? 12 : 0),
                  bottomRight: Radius.circular(isUser ? 0 : 12),
                ),
              ),
              child:
                  isUser
                      ? Text(
                        text,
                        style: textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onPrimary,
                        ),
                      )
                      : MarkdownBody(
                        data: formatMCQs(text),
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
                                color: colorScheme.onSurface.withOpacity(0.7),
                                fontStyle: FontStyle.italic,
                              ) ??
                              const TextStyle(),
                          code:
                              textTheme.bodySmall?.copyWith(
                                fontFamily: 'monospace',
                                color: colorScheme.primary,
                              ) ??
                              const TextStyle(),
                          codeblockDecoration: BoxDecoration(
                            color:
                                Theme.of(context).brightness == Brightness.dark
                                    ? const Color(0xFF23272F)
                                    : colorScheme.surfaceVariant,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: colorScheme.outline.withOpacity(0.15),
                            ),
                          ),
                        ),
                      ),
            ),
          ),
          if (isUser) const SizedBox(width: 8),
          if (isUser)
            FutureBuilder<String?>(
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
                return CircleAvatar(
                  backgroundColor: colorScheme.surfaceVariant,
                  child: Icon(
                    Icons.person,
                    color: colorScheme.onSurface.withOpacity(0.7),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
