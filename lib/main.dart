import 'package:flutter/material.dart';

void main() {
  runApp(const SmartCNCApp());
}

class SmartCNCApp extends StatelessWidget {
  const SmartCNCApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart CNC Pro',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0a0a0a),
        primaryColor: const Color(0xFF00FF7F),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00FF7F),
          secondary: Color(0xFF2196F3),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Color(0xFF141414),
          selectedItemColor: Color(0xFF00FF7F),
          unselectedItemColor: Color(0xFF666666),
        ),
      ),
      home: const MainDashboard(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class MainDashboard extends StatefulWidget {
  const MainDashboard({super.key});

  @override
  State<MainDashboard> createState() => _MainDashboardState();
}

class _MainDashboardState extends State<MainDashboard> {
  int _currentIndex = 1; // 默认停留在“控制台”

  // 预留的三个核心页面
  final List<Widget> _pages = [
    const Center(child: Text('模型库页面 (开发中...)', style: TextStyle(color: Colors.white, fontSize: 20))),
    const Center(child: Text('设备控制台 (开发中...)', style: TextStyle(color: Colors.white, fontSize: 20))),
    const Center(child: Text('个人中心 (开发中...)', style: TextStyle(color: Colors.white, fontSize: 20))),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart CNC Pro', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF121212),
        elevation: 0,
        centerTitle: true,
      ),
      body: _pages[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.lightbulb_outline), label: '图库'),
          BottomNavigationBarItem(icon: Icon(Icons.settings_applications), label: '控制台'),
          BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: '我的'),
        ],
      ),
    );
  }
}
