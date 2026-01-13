import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:read_pdf_text/read_pdf_text.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../services/api_key_service.dart';
import 'package:encrypt/encrypt.dart' as encrypt;

class ResumeReviewScreen extends StatefulWidget {
  const ResumeReviewScreen({super.key});

  @override
  State<ResumeReviewScreen> createState() => _ResumeReviewScreenState();
}

class _ResumeReviewScreenState extends State<ResumeReviewScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _insightsKey = GlobalKey();

  bool _isLoading = true;
  bool _isUploading = false;
  bool _isAnalyzing = false;
  String _userName = '';
  List<Map<String, dynamic>> _reviews = [];
  String? _fileName;

  // Dashboard state variables
  int? _overallScore;
  int? _grammarScore;
  int? _contentScore;
  int? _clarityScore;
  String? _readTime;
  int? _wordCount;
  int? _impactScore;
  int? _concisenessScore;
  List<Map<String, dynamic>>? _impactChecks;
  List<Map<String, dynamic>>? _concisenessChecks;
  List<Map<String, dynamic>>? _basicChecks;
  List<String>? _keySkills;
  // Store last AI feedback for modal
  String? _lastAIFeedback;

  // Add state for selected review
  Map<String, dynamic>? _selectedReview;

  bool _isResumeValid = true;
  bool _showSkeleton = false;

  String? _aiReadTime;
  List<String>? _aiKeySkills;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadReviews();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    try {
      final User? user = _auth.currentUser;
      if (user != null) {
        DocumentSnapshot userDoc =
            await _firestore.collection('users').doc(user.uid).get();

        setState(() {
          _userName = user.displayName ?? 'User';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      debugPrint('Error loading user data: $e');
    }
  }

  Future<void> _loadReviews() async {
    try {
      final User? user = _auth.currentUser;
      if (user != null) {
        final reviewsSnapshot =
            await _firestore
                .collection('users')
                .doc(user.uid)
                .collection('resume_reviews')
                .orderBy('timestamp', descending: true)
                .get();

        final reviews =
            reviewsSnapshot.docs
                .map(
                  (doc) => {
                    'id': doc.id,
                    ...doc.data(),
                    'timestamp':
                        (doc.data()['timestamp'] as Timestamp).toDate(),
                    'aiReadTime': doc.data()['aiReadTime'],
                    'aiKeySkills': doc.data()['aiKeySkills'],
                    'wordCount': doc.data()['wordCount'],
                  },
                )
                .toList();

        setState(() {
          _reviews = reviews;
          // Select latest review by default
          if (reviews.isNotEmpty) {
            _selectedReview = reviews[0];
            _parseAIAnalysis(reviews[0]['feedback'], '');
            // Set AI read time, key skills, and word count from saved data
            _aiReadTime = reviews[0]['aiReadTime'];
            _aiKeySkills = reviews[0]['aiKeySkills']?.cast<String>();
            _wordCount = reviews[0]['wordCount'];
            _isResumeValid = true; // Set to true for initial review
          } else {
            _selectedReview = null;
            _isResumeValid = true; // Reset to true when no reviews
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading reviews: $e');
    }
  }

  Future<bool> _checkIfResumeIsValid(String resumeText) async {
    try {
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
                  "You are a resume expert. Is the following text a valid resume? Reply only with YES or NO.",
            },
            {"role": "user", "content": resumeText},
          ],
        }),
      );
      final data = jsonDecode(response.body);
      final reply =
          data["choices"]?[0]["message"]["content"]
              ?.toString()
              .trim()
              .toUpperCase() ??
          "NO";
      return reply.startsWith("YES");
    } catch (e) {
      return false;
    }
  }

  Future<String?> _getAIReadTime(String resumeText) async {
    try {
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
                  "Estimate the time (in minutes and seconds) it would take an average human to read the following resume from start to end. Reply only with the time in the format: X min Y sec or Y sec.",
            },
            {"role": "user", "content": resumeText},
          ],
        }),
      );
      final data = jsonDecode(response.body);
      final reply =
          data["choices"]?[0]["message"]["content"]?.toString().trim();
      return reply;
    } catch (e) {
      return null;
    }
  }

  Future<List<String>?> _getAIKeySkills(String resumeText) async {
    try {
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
                  "Extract only the core technical and professional skills (not soft skills, not section headers, not generic words) from the following resume. Reply only with a comma-separated list of skills, no extra text.",
            },
            {"role": "user", "content": resumeText},
          ],
        }),
      );
      final data = jsonDecode(response.body);
      final reply =
          data["choices"]?[0]["message"]["content"]?.toString().trim();
      if (reply == null) return null;
      // Post-process: remove duplicates, filter out common non-skill words
      final blacklist = [
        'skills',
        'summary',
        'experience',
        'education',
        'projects',
        'work',
        'professional',
        'technical',
        'objective',
        'responsibilities',
        'achievements',
        'certifications',
        'languages',
        'interests',
        'hobbies',
        'contact',
        'address',
        'email',
        'phone',
        'linkedin',
        'github',
        'profile',
        'personal',
        'details',
        'curriculum vitae',
        'cv',
        'resume',
        'proficient',
        'familiar',
        'knowledge',
        'ability',
        'team',
        'leadership',
        'communication',
        'management',
        'problem solving',
        'hardworking',
        'dedicated',
        'motivated',
        'adaptable',
        'organized',
        'creative',
        'detail-oriented',
        'self-motivated',
        'fast learner',
        'goal-oriented',
        'results-driven',
        'reliable',
        'flexible',
        'collaborative',
        'independent',
        'initiative',
        'passionate',
        'enthusiastic',
        'committed',
        'driven',
        'dynamic',
        'resourceful',
        'analytical',
        'strategic',
        'innovative',
        'efficient',
        'effective',
        'multitasking',
        'time management',
        'decision making',
        'critical thinking',
        'presentation',
        'public speaking',
        'negotiation',
        'conflict resolution',
        'customer service',
        'client relations',
        'relationship building',
        'networking',
        'sales',
        'marketing',
        'business development',
        'project management',
        'teamwork',
        'team player',
        'leadership skills',
        'communication skills',
        'interpersonal skills',
        'organizational skills',
        'problem-solving skills',
        'analytical skills',
        'technical skills',
        'soft skills',
        'hard skills',
        'computer skills',
        'language skills',
        'other skills',
        'additional skills',
        'references',
        'available upon request',
        'etc.',
      ];
      final skills =
          reply
              .split(',')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toSet()
              .toList();
      final filtered =
          skills.where((s) => !blacklist.contains(s.toLowerCase())).toList();
      return filtered;
    } catch (e) {
      return null;
    }
  }

  Future<void> _pickAndUploadResume() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'txt'],
      );

      if (result != null && result.files.single.path != null) {
        setState(() {
          _isUploading = true;
          _fileName = result.files.single.name;
          _isResumeValid = true;
        });

        String extractedText = '';
        String ext = result.files.single.extension?.toLowerCase() ?? '';
        if (ext == 'pdf') {
          extractedText = await ReadPdfText.getPDFtext(
            result.files.single.path!,
          );
        } else if (ext == 'txt') {
          extractedText = await File(result.files.single.path!).readAsString();
        } else {
          setState(() {
            _isUploading = false;
          });
          if (mounted) {
            _showTopToast(
              context,
              'Only PDF and TXT files are supported for text extraction. Please upload a PDF or TXT file.',
            );
          }
          return;
        }

        // Optionally limit text length
        if (extractedText.length > 8000) {
          extractedText = extractedText.substring(0, 8000);
        }

        // AI check for valid resume
        setState(() {
          _showSkeleton = true;
        });
        final isValid = await _checkIfResumeIsValid(extractedText);
        setState(() {
          _isResumeValid = isValid;
          _showSkeleton = false;
        });
        if (!isValid) {
          if (mounted) {
            _showTopToast(
              context,
              'This file is not a valid resume. Please upload a proper resume document.',
            );
          }
          setState(() {
            _isUploading = false;
            _fileName = null;
          });
          return;
        }

        // Get AI read time and key skills
        setState(() {
          _showSkeleton = true;
        });
        final aiReadTime = await _getAIReadTime(extractedText);
        final aiKeySkills = await _getAIKeySkills(extractedText);
        setState(() {
          _aiReadTime = aiReadTime;
          _aiKeySkills = aiKeySkills;
        });

        await _analyzeResume(extractedText);
        setState(() {
          _isUploading = false;
          _fileName = null;
          _showSkeleton = false;
        });
      }
    } catch (e) {
      setState(() {
        _isUploading = false;
        _fileName = null;
        _showSkeleton = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error uploading resume: $e')));
      }
    }
  }

  // Parser for AI feedback
  void _parseAIAnalysis(String analysis, String resumeText) {
    // Fallbacks
    int? overallScore;
    int? grammarScore;
    int? contentScore;
    int? clarityScore;
    String? readTime;
    int? wordCount;
    int? impactScore;
    int? concisenessScore;
    List<Map<String, dynamic>> impactChecks = [];
    List<Map<String, dynamic>> concisenessChecks = [];
    List<Map<String, dynamic>> basicChecks = [];
    List<String> keySkills = [];

    // Extract overall score (0-100 or 0-10)
    final overallMatch = RegExp(
      r'Overall Score:?[\s\n]*([0-9]{1,3}(?:\.[0-9]+)?)',
      caseSensitive: false,
    ).firstMatch(analysis);
    if (overallMatch != null) {
      double val = double.tryParse(overallMatch.group(1) ?? '') ?? 0;
      overallScore = val > 10 ? val.round() : (val * 10).round();
    }

    // Extract subscores (if present)
    final grammarMatch = RegExp(
      r'Grammar Score:?[\s\n]*([0-9]{1,3})',
      caseSensitive: false,
    ).firstMatch(analysis);
    if (grammarMatch != null)
      grammarScore = int.tryParse(grammarMatch.group(1) ?? '');
    final contentMatch = RegExp(
      r'Content Score:?[\s\n]*([0-9]{1,3})',
      caseSensitive: false,
    ).firstMatch(analysis);
    if (contentMatch != null)
      contentScore = int.tryParse(contentMatch.group(1) ?? '');
    final clarityMatch = RegExp(
      r'Clarity Score:?[\s\n]*([0-9]{1,3})',
      caseSensitive: false,
    ).firstMatch(analysis);
    if (clarityMatch != null)
      clarityScore = int.tryParse(clarityMatch.group(1) ?? '');

    // Only calculate word count if we have resume text and no saved word count
    if (resumeText.isNotEmpty && _wordCount == null) {
      wordCount =
          resumeText
              .split(RegExp(r'\s+'))
              .where((w) => w.trim().isNotEmpty)
              .length;
    }

    // Read time calculation with null check
    int wordsPerMinute = 200;
    int seconds = ((wordCount ?? 0) / wordsPerMinute * 60).round();
    int min = seconds ~/ 60;
    int sec = seconds % 60;
    readTime = '${min > 0 ? '$min min ' : ''}$sec sec';

    // Impact and Conciseness scores
    final impactMatch = RegExp(
      r'Impact:?[\s\n]*([0-9]{1,3})',
      caseSensitive: false,
    ).firstMatch(analysis);
    if (impactMatch != null)
      impactScore = int.tryParse(impactMatch.group(1) ?? '');
    final concisenessMatch = RegExp(
      r'Conciseness:?[\s\n]*([0-9]{1,3})',
      caseSensitive: false,
    ).firstMatch(analysis);
    if (concisenessMatch != null)
      concisenessScore = int.tryParse(concisenessMatch.group(1) ?? '');

    // Impact checklist
    impactChecks = [
      {
        'label': 'Quantifying Impact',
        'ok': analysis.toLowerCase().contains('quantifying impact: yes'),
      },
      {
        'label': 'Repetition',
        'ok': !analysis.toLowerCase().contains('repetition: yes'),
      },
      {
        'label': 'Strong Action Verbs',
        'ok': analysis.toLowerCase().contains('strong action verbs: yes'),
      },
      {
        'label': 'Focus on Accomplishments',
        'ok': analysis.toLowerCase().contains('focus on accomplishments: yes'),
      },
      {
        'label': 'Spell Check',
        'ok': !analysis.toLowerCase().contains('spelling errors: yes'),
      },
    ];
    // Conciseness checklist
    concisenessChecks = [
      {
        'label': 'Resume Length',
        'ok': !analysis.toLowerCase().contains('resume too long'),
      },
      {
        'label': 'Bullet Points Count',
        'ok': analysis.toLowerCase().contains('bullet points: sufficient'),
      },
      {
        'label': 'Bullet Points Usage',
        'ok': analysis.toLowerCase().contains('bullet points used'),
      },
    ];
    // Basic checks
    basicChecks = [
      {
        'label': 'Education Mentioned',
        'ok': analysis.toLowerCase().contains('education'),
      },
      {
        'label': 'Projects Mentioned',
        'ok': analysis.toLowerCase().contains('project'),
      },
      {
        'label': 'Achievements Mentioned',
        'ok': analysis.toLowerCase().contains('achievement'),
      },
      {
        'label': 'Work Experience Mentioned',
        'ok': analysis.toLowerCase().contains('work experience'),
      },
    ];
    // Key skills (look for a section or keywords)
    final skillsMatch = RegExp(
      r'Key Skills:?\s*([\s\S]+?)(?:\n\n|\n[A-Z][a-z]+:|\Z)',
      caseSensitive: false,
    ).firstMatch(analysis);
    if (skillsMatch != null) {
      final skillsText = skillsMatch.group(1) ?? '';
      keySkills =
          skillsText
              .split(RegExp(r'[,\n]'))
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList();
    }

    setState(() {
      _overallScore = overallScore;
      _grammarScore = grammarScore;
      _contentScore = contentScore;
      _clarityScore = clarityScore;
      _readTime = readTime;
      _wordCount = wordCount;
      _impactScore = impactScore;
      _concisenessScore = concisenessScore;
      _impactChecks = impactChecks;
      _concisenessChecks = concisenessChecks;
      _basicChecks = basicChecks;
      _keySkills = keySkills;
      _lastAIFeedback = analysis;
    });
  }

  Future<void> _analyzeResume(String resumeText) async {
    try {
      setState(() => _isAnalyzing = true);

      // Calculate word count
      final wordCount =
          resumeText
              .split(RegExp(r'\s+'))
              .where((w) => w.trim().isNotEmpty)
              .length;

      // Get AI read time and key skills first
      final aiReadTime = await _getAIReadTime(resumeText);
      final aiKeySkills = await _getAIKeySkills(resumeText);

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
                  "You are an expert resume reviewer. Analyze the following resume text and provide detailed feedback. "
                  "Include sections for: Overall Score (0-10), Strengths, Areas for Improvement, and Specific Recommendations. "
                  "Be professional and constructive in your feedback. Also provide Grammar Score, Content Score, Clarity Score, Impact (score and checklist), Conciseness (score and checklist), Basic Checks, and Key Skills as explicit sections in your response.",
            },
            {"role": "user", "content": "Resume Text:\n$resumeText"},
          ],
        }),
      );

      if (!mounted) return;

      final data = jsonDecode(response.body);
      print('Groq API response: $data');
      if (data["error"] != null) {
        setState(() {
          _isAnalyzing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('API Error: ${data["error"]["message"]}')),
        );
        return;
      }
      final analysis =
          data["choices"]?[0]["message"]["content"] ?? "No analysis available";

      // Parse and update dashboard state (this sets _overallScore)
      _parseAIAnalysis(analysis, resumeText);
      final score = _overallScore ?? 0;

      // Save review to Firestore using parsed score
      final User? user = _auth.currentUser;
      if (user != null) {
        await _firestore
            .collection('users')
            .doc(user.uid)
            .collection('resume_reviews')
            .add({
              'fileName': _fileName,
              'feedback': analysis,
              'score': score,
              'timestamp': FieldValue.serverTimestamp(),
              'status': 'Completed',
              'aiReadTime': aiReadTime,
              'aiKeySkills': aiKeySkills,
              'wordCount': wordCount,
            });

        // Reload reviews
        await _loadReviews();
      }

      setState(() => _isAnalyzing = false);
    } catch (e) {
      setState(() => _isAnalyzing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error analyzing resume: ${e.toString()}')),
        );
      }
    }
  }

  Widget _buildResumeInsightsDashboard() {
    if (_showSkeleton) {
      return _buildDashboardSkeleton();
    }
    if (!_isResumeValid) {
      return const SizedBox.shrink();
    }
    // Use real data if available, else fallback to mock
    double overallScore = (_overallScore ?? 8.5).toDouble();
    double grammarScore = (_grammarScore ?? 9.0).toDouble();
    double contentScore = (_contentScore ?? 8.5).toDouble();
    double clarityScore = (_clarityScore ?? 9.0).toDouble();
    double impactScore = (_impactScore ?? 8.0).toDouble();
    double concisenessScore = (_concisenessScore ?? 7.5).toDouble();
    // Convert scores >10 to 0-10 scale
    overallScore = overallScore > 10 ? (overallScore / 10.0) : overallScore;
    grammarScore = grammarScore > 10 ? (grammarScore / 10.0) : grammarScore;
    contentScore = contentScore > 10 ? (contentScore / 10.0) : contentScore;
    clarityScore = clarityScore > 10 ? (clarityScore / 10.0) : clarityScore;
    impactScore = impactScore > 10 ? (impactScore / 10.0) : impactScore;
    concisenessScore =
        concisenessScore > 10 ? (concisenessScore / 10.0) : concisenessScore;

    final readTime = _aiReadTime ?? _readTime ?? '2 min 10 sec';
    final wordCount = _wordCount ?? 436;
    final impactChecks =
        _impactChecks ??
        [
          {'label': 'Quantifying Impact', 'ok': true},
          {'label': 'Repetition', 'ok': false},
          {'label': 'Strong Action Verbs', 'ok': true},
          {'label': 'Focus on Accomplishments', 'ok': true},
          {'label': 'Spell Check', 'ok': false},
        ];
    final concisenessChecks =
        _concisenessChecks ??
        [
          {'label': 'Resume Length', 'ok': false},
          {'label': 'Bullet Points Count', 'ok': true},
          {'label': 'Bullet Points Usage', 'ok': true},
        ];
    final basicChecks =
        _basicChecks ??
        [
          {'label': 'Education Mentioned', 'ok': true},
          {'label': 'Projects Mentioned', 'ok': true},
          {'label': 'Achievements Mentioned', 'ok': true},
          {'label': 'Work Experience Mentioned', 'ok': true},
        ];
    final keySkills =
        _aiKeySkills ??
        _keySkills ??
        [
          'OOP',
          'Data Structures and Algorithms',
          'System Design',
          'Flutter SDK',
          'Node.JS',
          'MongoDB',
          'Git/Github',
          'Linux',
        ];
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 24),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Read Time and Word Count
            Row(
              children: [
                Icon(Icons.timer, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Read Time',
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                Text(readTime, style: textTheme.bodyMedium),
                const SizedBox(width: 8),
                Text(
                  '($wordCount words)',
                  style: textTheme.bodySmall?.copyWith(color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'This represents the time taken by a human to read your resume start to end.',
              style: textTheme.bodySmall?.copyWith(color: Colors.orange[800]),
            ),
            const SizedBox(height: 20),
            // Score Bars
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildScoreBar(
                  'Overall Score',
                  overallScore,
                  colorScheme.primary,
                ),
                _buildScoreBar('Grammar Score', grammarScore, Colors.green),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildScoreBar('Content Score', contentScore, Colors.blue),
                _buildScoreBar('Clarity Score', clarityScore, Colors.purple),
              ],
            ),
            const SizedBox(height: 24),
            // Impact Section
            _buildChecklistSection(
              'Impact',
              impactScore,
              impactChecks,
              colorScheme,
            ),
            const SizedBox(height: 16),
            // Conciseness Section
            _buildChecklistSection(
              'Conciseness',
              concisenessScore,
              concisenessChecks,
              colorScheme,
            ),
            const SizedBox(height: 16),
            // Basic Checks
            Text(
              'Basic Checks',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children:
                  basicChecks
                      .map(
                        (item) => Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              (item['ok'] as bool)
                                  ? Icons.check_circle
                                  : Icons.cancel,
                              color:
                                  (item['ok'] as bool)
                                      ? Colors.green
                                      : Colors.red,
                              size: 18,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              item['label'] as String,
                              style: textTheme.bodySmall,
                            ),
                          ],
                        ),
                      )
                      .toList(),
            ),
            const SizedBox(height: 20),
            // Key Skills
            Text(
              'Your Key Skills',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children:
                  keySkills
                      .map(
                        (skill) => Chip(
                          label: Text(skill as String),
                          backgroundColor: colorScheme.secondary.withOpacity(
                            0.15,
                          ),
                          labelStyle: textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      )
                      .toList(),
            ),
            const SizedBox(height: 20),
            // Overall Review Button
            if (_selectedReview != null && _selectedReview!['feedback'] != null)
              Center(
                child: ElevatedButton.icon(
                  onPressed:
                      () =>
                          _showFullAIReviewModal(_selectedReview!['feedback']),
                  icon: const Icon(Icons.description),
                  label: const Text('Show Full AI Review'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Helper for score bar
  Widget _buildScoreBar(String label, double score, Color color) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: score / 10.0,
            color: color,
            backgroundColor: color.withOpacity(0.15),
            minHeight: 8,
            borderRadius: BorderRadius.circular(8),
          ),
          const SizedBox(height: 2),
          Text(
            '${score.toStringAsFixed(1)}/10',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  // Helper for checklist section
  Widget _buildChecklistSection(
    String title,
    double score,
    List<Map<String, dynamic>> checks,
    ColorScheme colorScheme,
  ) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      color: colorScheme.surfaceVariant,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '$title ',
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${score.toStringAsFixed(1)} / 10',
                  style: textTheme.bodySmall?.copyWith(
                    color: Colors.orange[800],
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...checks.map(
              (item) => Row(
                children: [
                  Icon(
                    (item['ok'] as bool) ? Icons.check_circle : Icons.cancel,
                    color: (item['ok'] as bool) ? Colors.green : Colors.red,
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  Text(item['label'] as String, style: textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResumeUploadSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).dividerColor.withOpacity(0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Upload Your Resume',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          const Text(
            'Get AI-powered feedback on your resume from our expert system.',
            style: TextStyle(color: Colors.grey, fontSize: 14),
          ),
          const SizedBox(height: 8),
          const Text(
            'Upload text or PDF file only',
            style: TextStyle(
              color: Colors.red,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          if (_fileName != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.description, color: Colors.blue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _fileName!,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      setState(() {
                        _fileName = null;
                      });
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          ElevatedButton.icon(
            onPressed:
                _isUploading || _isAnalyzing ? null : _pickAndUploadResume,
            icon:
                _isUploading || _isAnalyzing
                    ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : const Icon(Icons.upload_file),
            label: Text(
              _isUploading
                  ? 'Uploading...'
                  : _isAnalyzing
                  ? 'Analyzing...'
                  : 'Upload Resume',
            ),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Update _onReviewTap to keep only the scroll to insights behavior
  void _onReviewTap(Map<String, dynamic> review) {
    setState(() {
      _selectedReview = review;
      _aiReadTime = review['aiReadTime'];
      _aiKeySkills = review['aiKeySkills']?.cast<String>();
      _wordCount = review['wordCount'];
      _isResumeValid = true;
    });
    _parseAIAnalysis(review['feedback'], '');
    // Scroll to insights dashboard after a short delay
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients && _insightsKey.currentContext != null) {
        final RenderBox box =
            _insightsKey.currentContext!.findRenderObject() as RenderBox;
        final position = box.localToGlobal(Offset.zero);
        final offset =
            position.dy - MediaQuery.of(context).padding.top - kToolbarHeight;
        _scrollController.animateTo(
          _scrollController.offset + offset,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  // Add a helper method to parse overall score from feedback
  double _parseOverallScoreFromFeedback(String feedback) {
    final overallMatch = RegExp(
      r'Overall Score:?[\s\n]*([0-9]{1,3}(?:\.[0-9]+)?)',
      caseSensitive: false,
    ).firstMatch(feedback);
    if (overallMatch != null) {
      double val = double.tryParse(overallMatch.group(1) ?? '') ?? 0;
      return val > 10 ? val / 10.0 : val; // Convert to 0-10 scale if needed
    }
    return 0.0;
  }

  // Update the review history list widget to use parsed score
  Widget _buildReviewHistoryList() {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Text(
            'Review History',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        if (_reviews.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'No reviews yet. Upload your resume to get started!',
                style: TextStyle(color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _reviews.length,
            itemBuilder: (context, index) {
              final review = _reviews[index];
              final isSelected =
                  _selectedReview != null &&
                  _selectedReview!['id'] == review['id'];
              // Parse overall score from feedback
              final overallScore = _parseOverallScoreFromFeedback(
                review['feedback'],
              );
              return GestureDetector(
                onTap: () => _onReviewTap(review),
                child: Card(
                  color:
                      isSelected
                          ? colorScheme.primary.withOpacity(0.08)
                          : colorScheme.surface,
                  margin: const EdgeInsets.only(bottom: 12),
                  elevation: isSelected ? 6 : 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // File name and date
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                review['fileName'] ?? 'Resume',
                                style: textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                review['timestamp'].toString().split('.')[0],
                                style: textTheme.bodySmall?.copyWith(
                                  color: Colors.grey[600],
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Row(
                          children: [
                            Icon(Icons.star, color: Colors.amber, size: 18),
                            const SizedBox(width: 4),
                            Text(
                              overallScore.toStringAsFixed(1),
                              style: textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (isSelected) ...[
                              const SizedBox(width: 8),
                              Icon(
                                Icons.arrow_right,
                                color: colorScheme.primary,
                                size: 28,
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  // Show full AI review in a modal
  void _showFullAIReviewModal(String feedback) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        final textTheme = Theme.of(context).textTheme;
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 44,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16, top: 0),
                  decoration: BoxDecoration(
                    color: colorScheme.outline.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      'Full AI Review',
                      style: textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy),
                    tooltip: 'Copy',
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: feedback));
                      _showTopToast(context, 'Copied to clipboard');
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.share),
                    tooltip: 'Share',
                    onPressed: () async {
                      final shareText =
                          'This Resume review is generated by HireIQ\n'
                          'Download the app now: https://play.google.com/store/apps/details?id=com.aicon.hireiq \n\n'
                          '$feedback';
                      await Share.share(shareText);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: SingleChildScrollView(
                  child: MarkdownBody(
                    data: feedback,
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
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // Custom toast/overlay for modal context
  void _showTopToast(BuildContext context, String message) {
    final overlay = Overlay.of(context);
    final isError =
        message.toLowerCase().contains('not a valid resume') ||
        message.toLowerCase().contains('not supported');

    final overlayEntry = OverlayEntry(
      builder:
          (context) => Positioned(
            top: 0,
            bottom: 0,
            left: 0,
            right: 0,
            child: Material(
              color: Colors.black.withOpacity(0.3),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 16,
                  ),
                  margin: const EdgeInsets.symmetric(horizontal: 40),
                  decoration: BoxDecoration(
                    color:
                        isError
                            ? const Color(0xFFD32F2F).withOpacity(
                              0.95,
                            ) // Material Red 700
                            : Colors.black.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: (isError
                                ? const Color(0xFFD32F2F)
                                : Colors.black)
                            .withOpacity(0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isError ? Icons.error_outline : Icons.info_outline,
                        color: Colors.white,
                        size: 28,
                      ),
                      const SizedBox(width: 16),
                      Flexible(
                        child: Text(
                          message,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
    );
    overlay.insert(overlayEntry);
    Future.delayed(const Duration(seconds: 3), () => overlayEntry.remove());
  }

  // Simple skeleton loader for dashboard
  Widget _buildDashboardSkeleton() {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 24),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 32,
              width: 180,
              color: colorScheme.surfaceVariant.withOpacity(0.4),
              margin: const EdgeInsets.only(bottom: 16),
            ),
            Row(
              children: [
                Container(
                  height: 18,
                  width: 80,
                  color: colorScheme.surfaceVariant.withOpacity(0.4),
                ),
                const SizedBox(width: 16),
                Container(
                  height: 18,
                  width: 60,
                  color: colorScheme.surfaceVariant.withOpacity(0.4),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              height: 16,
              width: double.infinity,
              color: colorScheme.surfaceVariant.withOpacity(0.4),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 12,
                    color: colorScheme.surfaceVariant.withOpacity(0.4),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    height: 12,
                    color: colorScheme.surfaceVariant.withOpacity(0.4),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 12,
                    color: colorScheme.surfaceVariant.withOpacity(0.4),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    height: 12,
                    color: colorScheme.surfaceVariant.withOpacity(0.4),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Container(
              height: 18,
              width: 120,
              color: colorScheme.surfaceVariant.withOpacity(0.4),
            ),
            const SizedBox(height: 12),
            Container(
              height: 12,
              width: double.infinity,
              color: colorScheme.surfaceVariant.withOpacity(0.4),
            ),
            const SizedBox(height: 16),
            Container(
              height: 18,
              width: 120,
              color: colorScheme.surfaceVariant.withOpacity(0.4),
            ),
            const SizedBox(height: 12),
            Container(
              height: 12,
              width: double.infinity,
              color: colorScheme.surfaceVariant.withOpacity(0.4),
            ),
            const SizedBox(height: 16),
            Container(
              height: 18,
              width: 120,
              color: colorScheme.surfaceVariant.withOpacity(0.4),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(
                6,
                (i) => Container(
                  height: 28,
                  width: 60,
                  color: colorScheme.surfaceVariant.withOpacity(0.4),
                ),
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Resume Review'), centerTitle: true),
      body: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildResumeUploadSection(),
            const SizedBox(height: 24),
            if (_selectedReview != null) ...[
              Container(
                key: _insightsKey,
                child: _buildResumeInsightsDashboard(),
              ),
              const SizedBox(height: 24),
            ],
            _buildReviewHistoryList(),
          ],
        ),
      ),
    );
  }
}
