import 'package:flutter/material.dart';

import '../auth/login_page.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _controller = PageController();
  int _index = 0;

  final pages = const [
    _OnboardData(
      imagePath: "assets/onboarding/plant_hand.jpg",    
      title: "Welcome to AquaFarm\nMonitor",
      desc:
          "Discover the future of sustainable agriculture with our IoT-enabled aquaponics monitoring system. "
          "Grow fresh lettuce while maintaining perfect water quality automatically.",
      bullets: [],
    ),
    _OnboardData(
      imagePath: "assets/onboarding/dashboard.jpg",
      title: "Smart Sensor Network",
      desc:
          "Our advanced IoT sensors continuously monitor critical parameters to ensure optimal growing conditions for your aquaponics system.",
      bullets: [],
    ),
    _OnboardData(
      imagePath: "assets/onboarding/sensors.jpg",
      title: "Real-Time Dashboard",
      desc:
          "Access all your system data from anywhere with our intuitive mobile dashboard. Monitor, control, and analyze your aquaponics system with ease.",
      bullets: [
        "Live sensor readings with charts",
        "Remote pump and aerator controls",
      ],
    ),
    _OnboardData(
      imagePath: "assets/onboarding/alerts.jpg",
      title: "Smart Alerts &\nNotifications",
      desc:
          "Never miss a critical system event. Our intelligent alert system keeps you informed about your aquaponics system status 24/7.",
      bullets: [
        "Instant notifications for critical alerts",
        "Early warnings for abnormal readings",
      ],
    ),
  ];

  Future<void> _finish() async {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
    );
  }


  void _next() {
    if (_index >= pages.length - 1) {
      _finish();
    } else {
      _controller.nextPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final green = const Color(0xFF2E7D32); // similar to screenshot

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Top bar (Logo + Language + Globe)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: Row(
                children: [
                  Container(
                    height: 40,
                    width: 40,
                    decoration: BoxDecoration(
                      color: green,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.water_drop, color: Colors.white),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    "AquaFarm",
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: green,
                    ),
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      const Text("🇬🇧"),
                      const SizedBox(width: 8),
                      Text(
                        "English",
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                  const SizedBox(width: 16),
                  const Icon(Icons.language),
                ],
              ),
            ),

            // Pages
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: pages.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (_, i) => _OnboardCard(data: pages[i]),
              ),
            ),

            // Bottom controls (Skip + dots + Next button)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
              child: Row(
                children: [
                  TextButton(
                    onPressed: _finish,
                    child: const Text("Skip"),
                  ),
                  const Spacer(),

                  // Dots
                  Row(
                    children: List.generate(pages.length, (i) {
                      final active = i == _index;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        height: 8,
                        width: active ? 18 : 8,
                        decoration: BoxDecoration(
                          color: active ? green : Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(20),
                        ),
                      );
                    }),
                  ),

                  const Spacer(),
                  SizedBox(
                    height: 46,
                    child: ElevatedButton(
                      onPressed: _next,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: green,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                      ),
                      child: Row(
                        children: [
                          Text(_index == pages.length - 1 ? "Start" : "Next"),
                          const SizedBox(width: 8),
                          const Icon(Icons.arrow_forward),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardCard extends StatelessWidget {
  final _OnboardData data;
  const _OnboardCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Column(
        children: [
          // Big rounded image card
          Container(
            height: 340,
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
              image: DecorationImage(
                image: AssetImage(data.imagePath),
                fit: BoxFit.cover,
              ),
            ),
          ),

          const SizedBox(height: 26),

          Text(
            data.title,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),

          const SizedBox(height: 14),

          Text(
            data.desc,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: Colors.black54,
              height: 1.5,
            ),
          ),

          if (data.bullets.isNotEmpty) ...[
            const SizedBox(height: 16),
            Column(
              children: data.bullets
                  .map(
                    (b) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(width: 10),
                          const Icon(Icons.circle, size: 8, color: Color(0xFF2E7D32)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              b,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: Colors.black54,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],

          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _OnboardData {
  final String imagePath;
  final String title;
  final String desc;
  final List<String> bullets;

  const _OnboardData({
    required this.imagePath,
    required this.title,
    required this.desc,
    required this.bullets,
  });
}
