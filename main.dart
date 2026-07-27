import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CncControlApp());
}

class CncControlApp extends StatelessWidget {
  const CncControlApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart CNC',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        primaryColor: const Color(0xFFFF6B00),
        scaffoldBackgroundColor: const Color(0xFF121212),
        cardColor: const Color(0xFF1E1E1E),
        appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF1E1E1E), elevation: 0),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Color(0xFF1E1E1E),
          selectedItemColor: Color(0xFFFF6B00),
          unselectedItemColor: Colors.grey,
        ),
      ),
      home: const AppShell(),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({Key? key}) : super(key: key);

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _currentIndex = 1;
  final List<Widget> _pages = const [
    Center(child: Text('1. 侧斜视角监控看板 (Monitor)', style: TextStyle(color: Colors.white, fontSize: 18))),
    ControlPage(),
    ModelHubPage(),
    Center(child: Text('4. 个人中心与设备设置 (Profile)', style: TextStyle(color: Colors.white, fontSize: 18))),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.circle, color: Colors.greenAccent, size: 12),
            const SizedBox(width: 8),
            const Text('局域网直连: 智能CNC-01', style: TextStyle(fontSize: 16)),
            const Spacer(),
            ElevatedButton.icon(
              onPressed: () => _showEmergencyStopDialog(context),
              icon: const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 18),
              label: const Text('急停', style: TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
          ],
        ),
      ),
      body: IndexedStack(index: _currentIndex, children: _pages),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        type: BottomNavigationBarType.fixed,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.videocam), label: '监控看板'),
          BottomNavigationBarItem(icon: Icon(Icons.gamepad), label: '设备控制'),
          BottomNavigationBarItem(icon: Icon(Icons.grid_view), label: '模型库'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: '我的'),
        ],
      ),
    );
  }

  void _showEmergencyStopDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2A1212),
        title: const Text('🚨 触发紧急停止 (E-STOP)', style: TextStyle(color: Colors.redAccent)),
        content: const Text('下位机将立即断开主轴电源并锁定全轴移动。确定执行吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已下发 E-STOP 急停指令！')),
              );
            },
            child: const Text('确认急停'),
          ),
        ],
      ),
    );
  }
}

// 设备控制页面
class ControlPage extends StatefulWidget {
  const ControlPage({Key? key}) : super(key: key);

  @override
  State<ControlPage> createState() => _ControlPageState();
}

class _ControlPageState extends State<ControlPage> {
  double _selectedStep = 1.0;
  bool _isLaserOn = false;
  double _x = 120.50, _y = 85.20, _z = 15.00;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildMiniMonitorCard(),
            const SizedBox(height: 16),
            _buildToolMagazineSection(),
            const SizedBox(height: 20),
            _buildJogControlSection(),
            const SizedBox(height: 20),
            _buildQuickActionsSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniMonitorCard() {
    return Container(
      height: 100,
      decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          const Expanded(
            flex: 6,
            child: Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.videocam, color: Colors.greenAccent, size: 20),
                  SizedBox(width: 8),
                  Text('侧斜画面 1080P', style: TextStyle(color: Colors.white70, fontSize: 13)),
                ],
              ),
            ),
          ),
          Expanded(
            flex: 4,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('X: ${_x.toStringAsFixed(2)} mm', style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                Text('Y: ${_y.toStringAsFixed(2)} mm', style: const TextStyle(color: Colors.greenAccent, fontSize: 12)),
                Text('Z: ${_z.toStringAsFixed(2)} mm', style: const TextStyle(color: Colors.blueAccent, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolMagazineSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('ATC 刀仓状态', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(
          children: [
            _buildSlotCard('T1', '3.175平刀', true, Colors.orangeAccent),
            const SizedBox(width: 8),
            _buildSlotCard('T2', '60°V型刀', true, Colors.blueAccent),
            const SizedBox(width: 8),
            _buildSlotCard('T3', '空置', false, Colors.grey),
            const SizedBox(width: 8),
            _buildSlotCard('T4', '空置', false, Colors.grey),
          ],
        ),
      ],
    );
  }

  Widget _buildSlotCard(String slot, String tool, bool isReady, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(8)),
        child: Column(
          children: [
            Text(slot, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 2),
            Text(tool, style: const TextStyle(color: Colors.white70, fontSize: 10)),
            const SizedBox(height: 4),
            Icon(isReady ? Icons.check_circle : Icons.remove_circle_outline, size: 12, color: isReady ? Colors.greenAccent : Colors.grey),
          ],
        ),
      ),
    );
  }

  Widget _buildJogControlSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('步进距离:', style: TextStyle(color: Colors.white70, fontSize: 12)),
              Row(
                children: [0.1, 1.0, 10.0].map((step) {
                  final isSelected = _selectedStep == step;
                  return Padding(
                    padding: const EdgeInsets.only(left: 6.0),
                    child: ChoiceChip(
                      label: Text('${step}mm', style: TextStyle(color: isSelected ? Colors.black : Colors.white, fontSize: 11)),
                      selected: isSelected,
                      selectedColor: const Color(0xFFFF6B00),
                      onSelected: (_) => setState(() => _selectedStep = step),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          const Divider(color: Colors.white12, height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              SizedBox(
                width: 150,
                height: 150,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned(top: 0, child: _buildJogBtn('Y+', () => setState(() => _y += _selectedStep))),
                    Positioned(bottom: 0, child: _buildJogBtn('Y-', () => setState(() => _y -= _selectedStep))),
                    Positioned(left: 0, child: _buildJogBtn('X-', () => setState(() => _x -= _selectedStep))),
                    Positioned(right: 0, child: _buildJogBtn('X+', () => setState(() => _x += _selectedStep))),
                  ],
                ),
              ),
              Column(
                children: [
                  const Text('Z 轴', style: TextStyle(color: Colors.blueAccent, fontSize: 12)),
                  const SizedBox(height: 6),
                  _buildJogBtn('Z+', () => setState(() => _z += _selectedStep)),
                  const SizedBox(height: 8),
                  _buildJogBtn('Z-', () => setState(() => _z -= _selectedStep)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildJogBtn(String label, VoidCallback onPressed) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF2C2C2C),
        minimumSize: const Size(44, 44),
        padding: EdgeInsets.zero,
      ),
      child: Text(label, style: const TextStyle(fontSize: 13, color: Colors.white)),
    );
  }

  Widget _buildQuickActionsSection() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () => setState(() => _isLaserOn = !_isLaserOn),
            icon: Icon(Icons.center_focus_strong, color: _isLaserOn ? Colors.redAccent : Colors.white, size: 16),
            label: Text(_isLaserOn ? '关闭激光十字' : '开启激光十字', style: const TextStyle(fontSize: 12)),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E1E1E), padding: const EdgeInsets.symmetric(vertical: 12)),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () => setState(() { _x = 0; _y = 0; _z = 0; }),
            icon: const Icon(Icons.home, color: Colors.orangeAccent, size: 16),
            label: const Text('全轴归零', style: TextStyle(fontSize: 12)),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E1E1E), padding: const EdgeInsets.symmetric(vertical: 12)),
          ),
        ),
      ],
    );
  }
}

// 模型库页面
class ModelHubPage extends StatelessWidget {
  const ModelHubPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('云端推荐模型', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          _buildModelCard(context, "木质手机支架", "100 × 80 × 12 mm", "推荐: 4mm 椴木板"),
          const SizedBox(height: 12),
          _buildModelCard(context, "复古雕花茶杯垫", "90 × 90 × 5 mm", "推荐: 亚克力/胡桃木"),
        ],
      ),
    );
  }

  Widget _buildModelCard(BuildContext context, String title, String size, String material) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          Container(width: 50, height: 50, color: Colors.orangeAccent.withOpacity(0.2), child: const Icon(Icons.interests, color: Colors.orangeAccent)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 4),
                Text('尺寸: $size | $material', style: const TextStyle(color: Colors.white54, fontSize: 11)),
              ],
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF6B00)),
            onPressed: () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => const EngravingWizardModal(),
              );
            },
            child: const Text('开始雕刻', style: TextStyle(fontSize: 12, color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

// 雕刻前 4 步向导弹窗
class EngravingWizardModal extends StatefulWidget {
  const EngravingWizardModal({Key? key}) : super(key: key);

  @override
  State<EngravingWizardModal> createState() => _EngravingWizardModalState();
}

class _EngravingWizardModalState extends State<EngravingWizardModal> {
  int _originMode = 0;
  bool _isTracingDone = false;
  bool _isSafetyChecked = false;
  bool _isProbingSuccess = false;
  bool _isProbing = false;
  double _slidePos = 0.0;

  bool get _canEngrave => _isSafetyChecked && _isProbingSuccess;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(color: Color(0xFF1E1E1E), borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('雕刻前向导 - 《木质手机支架》', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              IconButton(icon: const Icon(Icons.close, color: Colors.white54), onPressed: () => Navigator.pop(context)),
            ],
          ),
          const Divider(color: Colors.white12),
          Expanded(
            child: ListView(
              children: [
                _buildStepBox("1", "X/Y 零点选择", Column(
                  children: [
                    RadioListTile<int>(
                      value: 0, groupValue: _originMode, activeColor: const Color(0xFFFF6B00),
                      title: const Text('默认 L 型定位块模式', style: TextStyle(color: Colors.white, fontSize: 12)),
                      onChanged: (v) => setState(() => _originMode = v!),
                    ),
                    RadioListTile<int>(
                      value: 1, groupValue: _originMode, activeColor: const Color(0xFFFF6B00),
                      title: const Text('激光十字瞄准模式', style: TextStyle(color: Colors.white, fontSize: 12)),
                      onChanged: (v) => setState(() => _originMode = v!),
                    ),
                  ],
                )),
                const SizedBox(height: 10),
                _buildStepBox("2", "物理尺寸与防撞校验", Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2C2C2C)),
                        onPressed: () => setState(() => _isTracingDone = true),
                        child: Text(_isTracingDone ? '已完成激光循边' : '运行：激光红光循边预览', style: const TextStyle(fontSize: 12, color: Colors.white)),
                      ),
                    ),
                    CheckboxListTile(
                      value: _isSafetyChecked,
                      activeColor: Colors.greenAccent,
                      checkColor: Colors.black,
                      title: const Text('我已确认：红光框全程在板材内部，未超界', style: TextStyle(color: Colors.white70, fontSize: 11)),
                      onChanged: _isTracingDone ? (v) => setState(() => _isSafetyChecked = v!) : null,
                    ),
                  ],
                )),
                const SizedBox(height: 10),
                _buildStepBox("3", "Z 轴与 ATC 刀长测量", Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2C2C2C)),
                        onPressed: () async {
                          setState(() => _isProbing = true);
                          await Future.delayed(const Duration(seconds: 1));
                          setState(() { _isProbing = false; _isProbingSuccess = true; });
                        },
                        child: Text(_isProbing ? '正在自动对刀...' : '运行：一键自动下探对刀', style: const TextStyle(fontSize: 12, color: Colors.white)),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(_isProbingSuccess ? '✓ Z0 零点已锁定' : '需完成对刀后方可开始', style: TextStyle(color: _isProbingSuccess ? Colors.greenAccent : Colors.white38, fontSize: 11)),
                  ],
                )),
              ],
            ),
          ),
          // 4. 滑动解锁
          Container(
            height: 48,
            width: double.infinity,
            decoration: BoxDecoration(color: _canEngrave ? const Color(0xFF2C2C2C) : Colors.white10, borderRadius: BorderRadius.circular(24)),
            child: Stack(
              children: [
                Center(child: Text(_canEngrave ? '滑动解锁开始雕刻 ➔' : '请先完成 Step 2 确认与 Step 3 对刀', style: TextStyle(color: _canEngrave ? Colors.white : Colors.white38, fontSize: 12))),
                Positioned(
                  left: _slidePos,
                  child: GestureDetector(
                    onHorizontalDragUpdate: _canEngrave ? (d) => setState(() {
                      _slidePos = (_slidePos + d.delta.dx).clamp(0.0, 220.0);
                    }) : null,
                    onHorizontalDragEnd: (_) {
                      if (_slidePos >= 180) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('🚀 雕刻任务下发成功！'), backgroundColor: Colors.green));
                      } else {
                        setState(() => _slidePos = 0.0);
                      }
                    },
                    child: Container(
                      width: 44, height: 44, margin: const EdgeInsets.all(2),
                      decoration: BoxDecoration(color: _canEngrave ? const Color(0xFFFF6B00) : Colors.grey, shape: BoxShape.circle),
                      child: const Icon(Icons.arrow_forward, color: Colors.white, size: 20),
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

  Widget _buildStepBox(String num, String title, Widget child) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: const Color(0xFF2A2A2A), borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$num. $title', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}
