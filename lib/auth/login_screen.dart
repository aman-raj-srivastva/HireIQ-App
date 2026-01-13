import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:hireiq/screens/home_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:hireiq/services/chat_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class LoginScreen extends StatefulWidget {
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<Color?> _gradientAnimation;
  bool _isLoading = false;
  bool _showFeatures = false;
  final ScrollController _featureScrollController = ScrollController();
  final int _featureCount = 4; // Number of feature cards
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: Duration(seconds: 3),
    )..repeat(reverse: true);

    _gradientAnimation = ColorTween(
      begin: Colors.blueAccent,
      end: Colors.lightBlue[400],
    ).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    Future.delayed(Duration(milliseconds: 300), () {
      setState(() => _showFeatures = true);
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    _featureScrollController.dispose();
    super.dispose();
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);

    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        setState(() => _isLoading = false);
        return;
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final UserCredential userCredential = await _auth.signInWithCredential(
        credential,
      );
      final User? user = userCredential.user;

      if (user != null) {
        // Check if user document exists first
        final userDoc =
            await FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .get();

        if (!userDoc.exists) {
          // For new users, create document with isPro false
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .set({
                'isPro': false,
                'createdAt': FieldValue.serverTimestamp(),
                'displayName': user.displayName,
                'email': user.email,
                'photoURL': user.photoURL,
                'lastUpdated': FieldValue.serverTimestamp(),
              });
          debugPrint('Created new user document with isPro: false');
        } else {
          // For existing users, just update profile data if needed
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .update({
                'displayName': user.displayName,
                'email': user.email,
                'photoURL': user.photoURL,
                'lastUpdated': FieldValue.serverTimestamp(),
              });
          debugPrint('Updated existing user document, isPro status preserved');
        }

        // Store user profile data in Firestore
        final chatService = ChatService();
        await chatService.storeUserProfileData();

        // Successful sign in
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => HomeScreen()),
          );
        }
      }
    } catch (error) {
      setState(() => _isLoading = false);
      _showErrorSnackbar('Failed to sign in with Google: ${error.toString()}');
    }
  }

  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.white),
            SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red[600],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: Duration(seconds: 3),
      ),
    );
  }

  Future<void> _launchTerms() async {
    const url =
        'https://aiconstudiozapps.blogspot.com/2025/05/hireiq-privacy-policy-hireiq-privacy.html';
    try {
      if (await canLaunchUrl(Uri.parse(url))) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      } else {
        _showErrorSnackbar('Could not open Terms & Conditions');
      }
    } catch (e) {
      _showErrorSnackbar('An error occurred: ${e.toString()}');
    }
  }

  Widget _buildLoadingIndicator() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 40,
          height: 40,
          child: CircularProgressIndicator(
            strokeWidth: 3,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
          ),
        ),
        SizedBox(height: 16),
        Text(
          'Authenticating...',
          style: TextStyle(
            color: Colors.blue,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Color _getDotColor(int index) {
    if (!_featureScrollController.hasClients) {
      return index == 0 ? Colors.blue[600]! : Colors.grey[300]!;
    }

    final scrollPosition = _featureScrollController.position.pixels;
    final itemWidth = 160 + 12; // card width + margin
    final activeIndex = (scrollPosition / itemWidth).round().clamp(
      0,
      _featureCount - 1,
    );

    return index == activeIndex ? Colors.blue[600]! : Colors.grey[300]!;
  }

  double _getDotSize(int index) {
    if (!_featureScrollController.hasClients) {
      return index == 0 ? 8.0 : 6.0;
    }

    final scrollPosition = _featureScrollController.position.pixels;
    final itemWidth = 160 + 12;
    final page = scrollPosition / itemWidth;
    final distance = (page - index).abs();

    if (distance < 0.5) {
      return 6.0 + (8.0 - 6.0) * (0.5 - distance) * 2;
    }
    return 6.0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: Stack(
        children: [
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Logo and App Name
                  Padding(
                    padding: const EdgeInsets.only(top: 20.0, bottom: 16.0),
                    child: Row(
                      children: [
                        Hero(
                          tag: 'app-logo',
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.asset(
                              'assets/icon.png',
                              width: 68,
                              height: 68,
                              errorBuilder:
                                  (context, error, stackTrace) => Icon(
                                    Icons.work_rounded,
                                    size: 48,
                                    color: const Color.fromARGB(
                                      255,
                                      0,
                                      19,
                                      114,
                                    ),
                                  ),
                            ),
                          ),
                        ),
                        SizedBox(width: 1),
                        AnimatedBuilder(
                          animation: _gradientAnimation,
                          builder: (context, child) {
                            return RichText(
                              text: TextSpan(
                                children: [
                                  TextSpan(
                                    text: 'Hire',
                                    style: TextStyle(
                                      fontSize: 32,
                                      fontWeight: FontWeight.bold,
                                      color: const Color.fromARGB(
                                        255,
                                        0,
                                        1,
                                        58,
                                      ),
                                    ),
                                  ),
                                  TextSpan(
                                    text: 'IQ',
                                    style: TextStyle(
                                      fontSize: 32,
                                      fontWeight: FontWeight.bold,
                                      color: const Color.fromARGB(
                                        255,
                                        0,
                                        148,
                                        217,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),

                  // Tagline
                  AnimatedOpacity(
                    opacity: _showFeatures ? 1.0 : 0.0,
                    duration: Duration(milliseconds: 500),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 24.0),
                      child: Text(
                        'Unlock your career potential with AI-powered interviews',
                        style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                      ),
                    ),
                  ),

                  // Hero Image
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isTablet = constraints.maxWidth > 600;
                      return Container(
                        height: isTablet ? 300 : 200,
                        width: double.infinity,
                        margin: EdgeInsets.only(bottom: 24),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          image: DecorationImage(
                            image: AssetImage('assets/welcome.png'),
                            fit: isTablet ? BoxFit.contain : BoxFit.cover,
                            alignment: Alignment.topCenter,
                          ),
                        ),
                      );
                    },
                  ),

                  // Feature Cards with Scroll Indicator
                  Column(
                    children: [
                      AnimatedContainer(
                        duration: Duration(milliseconds: 500),
                        height: _showFeatures ? 160 : 0,
                        curve: Curves.easeOutQuart,
                        child: NotificationListener<ScrollNotification>(
                          onNotification: (notification) {
                            if (notification is ScrollUpdateNotification) {
                              setState(() {});
                            }
                            return true;
                          },
                          child: ListView(
                            controller: _featureScrollController,
                            scrollDirection: Axis.horizontal,
                            physics: BouncingScrollPhysics(),
                            children:
                                [
                                      _FeatureCard(
                                        icon: Icons.auto_awesome,
                                        title: 'AI Interviews',
                                        subtitle: 'Practice with our smart AI',
                                        color: Colors.blue[50]!,
                                      ),
                                      _FeatureCard(
                                        icon: Icons.work_outline,
                                        title: 'Job Matches',
                                        subtitle:
                                            'Personalized recommendations',
                                        color: Colors.green[50]!,
                                      ),
                                      _FeatureCard(
                                        icon: Icons.insights,
                                        title: 'Skill Analysis',
                                        subtitle: 'Identify your strengths',
                                        color: Colors.purple[50]!,
                                      ),
                                      _FeatureCard(
                                        icon: Icons.assignment_outlined,
                                        title: 'Resume Review',
                                        subtitle:
                                            'Get expert feedback for your profile',
                                        color: Colors.orange[50]!,
                                      ),
                                      _FeatureCard(
                                        icon: Icons.favorite_border,
                                        title: 'Loved Job Roles',
                                        subtitle:
                                            'Like and save your favorite roles',
                                        color: Colors.red[50]!,
                                      ),
                                      _FeatureCard(
                                        icon: Icons.check_circle_outline,
                                        title: 'Apply Now',
                                        subtitle:
                                            'Apply to your preferred jobs',
                                        color: Colors.yellow[50]!,
                                      ),
                                    ]
                                    .map(
                                      (card) => AnimatedPadding(
                                        padding: EdgeInsets.only(
                                          right: _showFeatures ? 12 : 0,
                                        ),
                                        duration: Duration(milliseconds: 500),
                                        child: card,
                                      ),
                                    )
                                    .toList(),
                          ),
                        ),
                      ),

                      // Animated Scroll Indicator
                      if (_showFeatures)
                        Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(_featureCount, (index) {
                              return AnimatedContainer(
                                duration: Duration(milliseconds: 200),
                                curve: Curves.easeInOut,
                                width: _getDotSize(index),
                                height: _getDotSize(index),
                                margin: EdgeInsets.symmetric(horizontal: 4),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _getDotColor(index),
                                ),
                              );
                            }),
                          ),
                        ),
                    ],
                  ),

                  SizedBox(height: 40),

                  // Google Sign In Button (the only sign-in option)
                  _AnimatedLoginButton(
                    icon: _buildSocialIcon('assets/google_logo.png'),
                    label: 'Continue with Google',
                    color: Colors.white,
                    textColor: Colors.black54,
                    onPressed: _signInWithGoogle,
                  ),

                  // Terms and Conditions
                  Padding(
                    padding: const EdgeInsets.only(top: 24.0, bottom: 16.0),
                    child: Center(
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTapDown: (_) => HapticFeedback.lightImpact(),
                          onTap: _launchTerms,
                          child: RichText(
                            textAlign: TextAlign.center,
                            text: TextSpan(
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 12,
                              ),
                              children: [
                                TextSpan(
                                  text:
                                      'By continuing, you agree to HireIQ\'s\n',
                                ),
                                TextSpan(
                                  text: 'Terms & Conditions',
                                  style: TextStyle(
                                    decoration: TextDecoration.underline,
                                    color: Colors.blue,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Loading Overlay
          if (_isLoading)
            Container(
              color: Colors.black.withOpacity(0.3),
              child: Center(
                child: Container(
                  padding: EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 10,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: _buildLoadingIndicator(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSocialIcon(String assetPath) {
    try {
      return Image.asset(
        assetPath,
        width: 24,
        height: 24,
        errorBuilder:
            (context, error, stackTrace) =>
                Icon(Icons.account_circle, size: 24, color: Colors.white),
      );
    } catch (e) {
      return Icon(Icons.account_circle, size: 24, color: Colors.white);
    }
  }
}

class _FeatureCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;

  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Container(
        width: 160,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: Colors.blue[800], size: 24),
              ),
              SizedBox(height: 16),
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: Colors.grey[900],
                ),
              ),
              SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(fontSize: 13, color: Colors.grey[700]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnimatedLoginButton extends StatefulWidget {
  final Widget icon;
  final String label;
  final Color color;
  final Color textColor;
  final VoidCallback onPressed;

  const _AnimatedLoginButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.textColor,
    required this.onPressed,
  });

  @override
  __AnimatedLoginButtonState createState() => __AnimatedLoginButtonState();
}

class __AnimatedLoginButtonState extends State<_AnimatedLoginButton> {
  bool _isHovering = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: Duration(milliseconds: 150),
          width: double.infinity,
          height: 50,
          decoration: BoxDecoration(
            color: widget.color,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color:
                  widget.color == Colors.white
                      ? Colors.grey[300]!
                      : Colors.transparent,
            ),
            boxShadow:
                _isHovering && !_isPressed
                    ? [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 12,
                        offset: Offset(0, 4),
                      ),
                    ]
                    : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              widget.icon,
              SizedBox(width: 12),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 16,
                  color: widget.textColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
