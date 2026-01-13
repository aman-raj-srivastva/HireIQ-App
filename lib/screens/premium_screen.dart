import 'package:flutter/material.dart';

class PremiumScreen extends StatefulWidget {
  const PremiumScreen({super.key});

  @override
  State<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends State<PremiumScreen> {
  String? _selectedPlan;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Go Premium', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Crown Icon
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [Colors.amber.shade300, Colors.orange],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.amber.withOpacity(0.4),
                    blurRadius: 15,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: const Icon(Icons.workspace_premium, size: 60, color: Colors.white),
            ),
            const SizedBox(height: 20),
            
            // Title
            ShaderMask(
              shaderCallback: (bounds) => LinearGradient(
                colors: [Colors.orange.shade700, Colors.amber],
              ).createShader(bounds),
              child: const Text(
                'Unlock Pro',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 30),
            
            // Features List
            ..._buildFeatureList(),
            const SizedBox(height: 40),
            
            // Pricing Cards with Equal Width
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: double.infinity),
              child: _buildPricingCard(
                title: 'Yearly Plan',
                price: '\$15/month',
                originalPrice: '\$20/month',
                discount: '17% OFF',
                billingText: 'Billed yearly, Cancel anytime',
                isPopular: true,
                isSelected: _selectedPlan == 'yearly',
                onTap: () => setState(() => _selectedPlan = 'yearly'),
              ),
            ),
            const SizedBox(height: 20),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: double.infinity),
              child: _buildPricingCard(
                title: 'Monthly Plan',
                price: '\$20/month',
                billingText: 'Billed monthly, Cancel anytime',
                isSelected: _selectedPlan == 'monthly',
                onTap: () => setState(() => _selectedPlan = 'monthly'),
              ),
            ),
            const SizedBox(height: 30),
            
            // Enhanced Upgrade Button
            SizedBox(
              width: double.infinity,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                decoration: BoxDecoration(
                  gradient: _selectedPlan != null 
                      ? LinearGradient(
                          colors: [Colors.orange.shade600, Colors.amber],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : LinearGradient(
                          colors: [Colors.grey.shade400, Colors.grey.shade500],
                        ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: _selectedPlan != null
                      ? [
                          BoxShadow(
                            color: Colors.orange.withOpacity(0.4),
                            blurRadius: 10,
                            spreadRadius: 2,
                          ),
                        ]
                      : null,
                ),
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _selectedPlan != null ? () {} : null,
                  child: Text(
                    'UPGRADE TO PRO',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                      color: _selectedPlan != null ? Colors.white : Colors.grey.shade200,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 30),
            
            // Footer Buttons
            _buildFooterButton(
              icon: Icons.mail_outline,
              text: 'Contact Our Team',
              onTap: () {},
            ),
            const SizedBox(height: 12),
            _buildFooterButton(
              icon: Icons.privacy_tip_outlined,
              text: 'Privacy Policy & Terms of Services',
              onTap: () {},
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildFeatureList() {
    final features = [
      {'icon': Icons.work, 'text': 'Unlimited Resume Reviews'},
      {'icon': Icons.video_call, 'text': 'Unlimited Mock Interviews'},
      {'icon': Icons.analytics, 'text': 'Advanced Analytics Dashboard'},
      {'icon': Icons.lock_open, 'text': 'Ad-Free Experience'},
      {'icon': Icons.star, 'text': 'Exclusive Content'},
    ];

    return features.map((feature) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(feature['icon'] as IconData, color: Colors.orange),
            ),
            const SizedBox(width: 15),
            Text(
              feature['text'] as String,
              style: const TextStyle(fontSize: 16),
            ),
          ],
        ),
      );
    }).toList();
  }

  Widget _buildPricingCard({
    required String title,
    required String price,
    required String billingText,
    String? originalPrice,
    String? discount,
    bool isPopular = false,
    bool isSelected = false,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isSelected ? Colors.orange.shade50 : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? Colors.orange
                : (isPopular ? Colors.orange.shade300 : Colors.grey.shade300),
            width: isSelected ? 2 : 1.5,
          ),
          boxShadow: [
            if (isSelected)
              BoxShadow(
                color: Colors.orange.withOpacity(0.2),
                blurRadius: 10,
                spreadRadius: 2,
              ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isPopular)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.amber, Colors.orange],
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'MOST POPULAR',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold),
                ),
              ),
            if (isPopular) const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: isSelected ? Colors.orange.shade800 : Colors.black,
              ),
            ),
            const SizedBox(height: 8),
            if (originalPrice != null)
              Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        originalPrice,
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey,
                          decoration: TextDecoration.lineThrough),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          discount!,
                          style: TextStyle(
                            color: Colors.green.shade800,
                            fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            Text(
              price,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              billingText,
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 13,
              ),
            ),
            if (isSelected)
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Icon(Icons.check_circle, color: Colors.green, size: 28),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooterButton({
    required IconData icon,
    required String text,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: Colors.grey.shade700),
            const SizedBox(width: 10),
            Text(
              text,
              style: TextStyle(
                color: Colors.grey.shade800,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}