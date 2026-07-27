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
      title: 'Smart CNC Pro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        primaryColor: const Color(0xFFFF6B00),
        scaffoldBackgroundColor: const Color(0xFF121212),
        cardColor: const Color(0xFF1E1E1E),
        appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF1A1A1A), elevation: 0),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Color(0xFF1A1A1A),
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
  bool _isLanMode = true;
  bool _isDoorClosed = true;
  bool _isLightOn = false;
  bool _isEngraving = false;

  double _progress = 0.35;
  int _activeTool = 1;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 10,
        title: Row(
          children: [
            InkWell(
              onTap: () {
                setState(() => _isLanMode = !_isLanMode);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(_isLanMode ? '已切换至 🟢 局域网直连模式' : '已切换至 🟡 异地外网远程模式'),
                    duration: const Duration(seconds: 1),
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _isLanMode ? Colors.green.withOpacity(0.2) : Colors.orange.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: _isLanMode ? Colors.greenAccent : Colors.orangeAccent),
                ),
                child: Row(
                  children: [
                    Icon(Icons.wifi, size: 12, color: _isLanMode ? Colors.greenAccent : Colors.orangeAccent),
                    const SizedBox(width: 4),
                    Text(
                      _isLanMode ? 'LAN 直连' : 'WAN 远程',
                      style: TextStyle(fontSize: 11, color: _isLanMode ? Colors.greenAccent : Colors.orangeAccent, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
            InkWell(
              onTap: () => setState(() => _isDoorClosed = !_isDoorClosed),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: _isDoorClosed ? Colors.white10 : Colors.redAccent.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Icon(_isDoorClosed ? Icons.sensor_door : Icons.sensor_door_outlined, size: 12, color: _isDoorClosed ? Colors.white70 : Colors.redAccent),
                    const SizedBox(width: 2),
                    Text(
                      _isDoorClosed ? '上盖关' : '盖打开!',
                      style: TextStyle(fontSize: 10, color: _isDoorClosed ? Colors.white70 : Colors.redAccent),
                    ),
                  ],
                ),
              ),
            ),
            const Spacer(),
            ElevatedButton.icon(
              onPressed: () => _showEmergencyStopDialog(context),
              icon: const Icon(Icons.error_outline, color: Colors.white, size: 18),
              label: const Text('急停', style: TextStyle(fontWeight: FontWeight.black, fontSize: 13)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade700,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                elevation: 4,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          if (!_isLanMode)
            Container(
              color: Colors.orange.shade900.withOpacity(0.8),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber, size: 14, color: Colors.white),
                  SizedBox(width: 6),
                  Text('当前为外网模式：已禁用 X/Y/Z 轴点动控制以防碰撞', style: TextStyle(color: Colors.white, fontSize: 11)),
                ],
              ),
            ),
          if (!_isDoorClosed)
            Container(
              color: Colors.red.shade900,
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
              child: const Row(
                children: [
                  Icon(Icons.dangerous, size: 14, color: Colors.white),
                  SizedBox(width: 6),
                  Text('警告：设备外罩已被打开！主轴已自动安全暂停', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          Expanded(
            child: IndexedStack(
              index: _currentIndex,
              children: [
                MonitorPage(isLightOn: _isLightOn, onLightToggle: () => setState(() => _isLightOn = !_isLightOn)),
                ControlPage(
                  isLanMode: _isLanMode,
                  isLightOn: _isLightOn,
                  isEngraving: _isEngraving,
                  progress: _progress,
                  activeTool: _activeTool,
                  onLightToggle: () => setState(() => _isLightOn = !_isLightOn),
                  onStartEngraveTest: () => setState(() => _isEngraving = !_isEngraving),
                ),
                const ModelHubPage(),
                const ProfilePage(),
              ],
            ),
          ),
        ],
      ),
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
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.redAccent),
            SizedBox(width: 8),
            Text('🚨 紧急停止 (E-STOP)', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text('下位机将立即断开主轴电源并锁定全轴移动。此操作不受网络模式限制！'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(ctx);
              setState(() => _isEngraving = false);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已下发最高优先级 E-STOP 急停指令！设备已断电。'), backgroundColor: Colors.red),
              );
            },
            child: const Text('确认急停', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

class MonitorPage extends StatelessWidget {
  final bool isLightOn;
  final VoidCallback onLightToggle;

  const MonitorPage({Key? key, required this.isLightOn, required this.onLightToggle}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12),
                ),
                child: Stack(
                  children: [
                    const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.videocam, color: Colors.greenAccent, size: 36),
                          SizedBox(height: 8),
                          Text('20cm 龙门架侧斜视实时画面 (1080P)', style: TextStyle(color: Colors.white70, fontSize: 13)),
                        ],
                      ),
                    ),
                    Positioned(
                      top: 10, left: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(4)),
                        child: const Text('● LIVE', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    Positioned(
                      bottom: 10, right: 10,
                      child: ElevatedButton.icon(
                        onPressed: onLightToggle,
                        icon: Icon(Icons.lightbulb, color: isLightOn ? Colors.yellowAccent : Colors.white, size: 16),
                        label: Text(isLightOn ? '照明灯: 开' : '照明灯: 关', style: const TextStyle(fontSize: 11)),
                        style: ElevatedButton.styleFrom(backgroundColor: isLightOn ? Colors.amber.shade900 : Colors.black54),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ControlPage extends StatefulWidget {
  final bool isLanMode;
  final bool isLightOn;
  final bool isEngraving;
  final double progress;
  final int activeTool;
  final VoidCallback onLightToggle;
  final VoidCallback onStartEngraveTest;

  const ControlPage({
    Key? key,
    required this.isLanMode,
    required this.isLightOn,
    required this.isEngraving,
    required this.progress,
    required this.activeTool,
    required this.onLightToggle,
    required this.onStartEngraveTest,
  }) : super(key: key);

  @override
  State<ControlPage> createState() => _ControlPageState();
}

class _ControlPageState extends State<ControlPage> {
  double _selectedStep = 1.0;
  bool _isPaused = false;
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
            if (widget.isEngraving) ...[
              _buildEngravingProgressCard(),
              const SizedBox(height: 16),
            ],
            _buildToolMagazineSection(),
            const SizedBox(height: 16),
            Opacity(
              opacity: widget.isLanMode ? 1.0 : 0.35,
              child: AbsorbPointer(
                absorbing: !widget.isLanMode,
                child: _buildJogControlSection(),
              ),
            ),
            const SizedBox(height: 16),
            _buildQuickActionsSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildEngravingProgressCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF231E1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFF6B00)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const SizedBox(
                    width: 12, height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFF6B00)),
                  ),
                  const SizedBox(width: 8),
                  Text(_isPaused ? '雕刻已暂停' : '正在雕刻: 《木质手机支架》', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                ],
              ),
              Text('${(widget.progress * 100).toInt()}%', style: const TextStyle(color: Color(0xFFFF6B00), fontWeight: FontWeight.black, fontSize: 18)),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: widget.progress, backgroundColor: Colors.white12, color: const Color(0xFFFF6B00), minHeight: 6),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Text('剩余时间: 12分45秒', style: TextStyle(color: Colors.white70, fontSize: 11)),
              Text('主轴转速: 12,000 RPM', style: TextStyle(color: Colors.white70, fontSize: 11)),
              Text('当前刀具: T1 平刀', style: TextStyle(color: Colors.orangeAccent, fontSize: 11, fontWeight: FontWeight.bold)),
            ],
          ),
          const Divider(color: Colors.white12, height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => setState(() => _isPaused = !_isPaused),
                  icon: Icon(_isPaused ? Icons.play_arrow : Icons.pause, size: 16),
                  label: Text(_isPaused ? '继续雕刻' : '暂停雕刻', style: const TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(backgroundColor: _isPaused ? Colors.green.shade800 : Colors.orange.shade800),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: widget.onStartEngraveTest,
                  icon: const Icon(Icons.stop, size: 16),
                  label: const Text('终止任务', style: TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade900),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildToolMagazineSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('ATC 刀仓状态', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(
          children: [
            _buildSlotCard('T1', '3.175平刀', true, widget.isEngraving && widget.activeTool == 1, Colors.orangeAccent),
            const SizedBox(width: 8),
            _buildSlotCard('T2', '60°V型刀', true, widget.isEngraving && widget.activeTool == 2, Colors.blueAccent),
            const SizedBox(width: 8),
            _buildSlotCard('T3', '空置', false, false, Colors.grey),
            const SizedBox(width: 8),
            _buildSlotCard('T4', '空置', false, false, Colors.grey),
          ],
        ),
      ],
    );
  }

  Widget _buildSlotCard(String slot, String tool, bool isReady, bool isWorking, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(
          color: isWorking ? color.withOpacity(0.2) : const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isWorking ? color : Colors.white12, width: isWorking ? 2.0 : 1.0),
        ),
        child: Column(
          children: [
            Text(slot, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 2),
            Text(tool, style: const TextStyle(color: Colors.white70, fontSize: 10)),
            const SizedBox(height: 4),
            Text(
              isWorking ? '⚡ 切削中' : (isReady ? '就位' : '--'),
              style: TextStyle(fontSize: 9, color: isWorking ? Colors.orangeAccent : Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildJogControlSection() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(widget.isLanMode ? '局域网 Jog 点动:' : '外网已禁用摇杆', style: TextStyle(color: widget.isLanMode ? Colors.white70 : Colors.orangeAccent, fontSize: 12)),
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
          const Divider(color: Colors.white12, height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              SizedBox(
                width: 140, height: 140,
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
        minimumSize: const Size(42, 42),
        padding: EdgeInsets.zero,
      ),
      child: Text(label, style: const TextStyle(fontSize: 12, color: Colors.white)),
    );
  }

  Widget _buildQuickActionsSection() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: widget.onLightToggle,
            icon: Icon(Icons.lightbulb, color: widget.isLightOn ? Colors.yellowAccent : Colors.white, size: 16),
            label: Text(widget.isLightOn ? '关闭照明灯' : '开启照明灯', style: const TextStyle(fontSize: 11)),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E1E1E), padding: const EdgeInsets.symmetric(vertical: 12)),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: widget.onStartEngraveTest,
            icon: Icon(widget.isEngraving ? Icons.stop_circle : Icons.play_circle, color: Colors.orangeAccent, size: 16),
            label: Text(widget.isEngraving ? '模拟停止' : '模拟开始雕刻', style: const TextStyle(fontSize: 11)),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E1E1E), padding: const EdgeInsets.symmetric(vertical: 12)),
          ),
        ),
      ],
    );
  }
}

class ModelHubPage extends StatefulWidget {
  const ModelHubPage({Key? key}) : super(key: key);

  @override
  State<ModelHubPage> createState() => _ModelHubPageState();
}

class _ModelHubPageState extends State<ModelHubPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(48),
        child: Container(
          color: const Color(0xFF1E1E1E),
          child: TabBar(
            controller: _tabController,
            indicatorColor: const Color(0xFFFF6B00),
            labelColor: const Color(0xFFFF6B00),
            unselectedLabelColor: Colors.white60,
            tabs: const [
              Tab(text: '🌐 官方公共模型库'),
              Tab(text: '📁 个人云端工程'),
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildModelCard(context, "木质手机支架", "100 × 80 × 12 mm", "推荐: 4mm 椴木板"),
              const SizedBox(height: 12),
              _buildModelCard(context, "复古雕花茶杯垫", "90 × 90 × 5 mm", "推荐: 亚克力/胡桃木"),
            ],
          ),
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildModelCard(context, "我的网页端导出项目_01.gcode", "120 × 120 × 10 mm", "自定 CAM 刀路参数"),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildModelCard(BuildContext context, String title, String size, String material) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          Container(width: 46, height: 46, color: Colors.orangeAccent.withOpacity(0.15), child: const Icon(Icons.interests, color: Colors.orangeAccent, size: 22)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 2),
                Text('尺寸: $size | $material', style: const TextStyle(color: Colors.white54, fontSize: 10)),
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
            child: const Text('准备雕刻', style: TextStyle(fontSize: 11, color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

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
              const Text('雕刻前准备向导 - 《木质手机支架》', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
              IconButton(icon: const Icon(Icons.close, color: Colors.white54), onPressed: () => Navigator.pop(context)),
            ],
          ),
          const Divider(color: Colors.white12),
          Expanded(
            child: ListView(
              children: [
                _buildStepBox("1", "X/Y 零点选择", true, Column(
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
                _buildStepBox("2", "物理尺寸与防撞校验", _isSafetyChecked, Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2C2C2C)),
                        onPressed: () => setState(() => _isTracingDone = true),
                        icon: const Icon(Icons.crop_free, color: Colors.redAccent, size: 16),
                        label: Text(_isTracingDone ? '已完成激光循边' : '运行：激光红光循边预览', style: const TextStyle(fontSize: 11, color: Colors.white)),
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
                _buildStepBox("3", "Z 轴与 ATC 刀长测量", _isProbingSuccess, Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2C2C2C)),
                        onPressed: () async {
                          setState(() => _isProbing = true);
                          await Future.delayed(const Duration(seconds: 1));
                          setState(() { _isProbing = false; _isProbingSuccess = true; });
                        },
                        icon: _isProbing ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.vertical_align_bottom, color: Colors.blueAccent, size: 16),
                        label: Text(_isProbing ? '正在自动对刀...' : '运行：一键自动下探对刀', style: const TextStyle(fontSize: 11, color: Colors.white)),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(_isProbingSuccess ? '✓ Z0 零点已锁定' : '需完成对刀后方可开始', style: TextStyle(color: _isProbingSuccess ? Colors.greenAccent : Colors.white38, fontSize: 11)),
                  ],
                )),
              ],
            ),
          ),
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

  Widget _buildStepBox(String num, String title, bool isFinished, Widget child) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: const Color(0xFF2A2A2A), borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('$num. $title', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
              const Spacer(),
              Icon(isFinished ? Icons.check_circle : Icons.radio_button_unchecked, size: 16, color: isFinished ? Colors.greenAccent : Colors.grey),
            ],
          ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}

class ProfilePage extends StatelessWidget {
  const ProfilePage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          ListTile(leading: Icon(Icons.router, color: Colors.orangeAccent), title: Text('设备绑定与网络管理', style: TextStyle(color: Colors.white))),
          ListTile(leading: Icon(Icons.build_circle, color: Colors.orangeAccent), title: Text('刀具磨损与寿命跟踪', style: TextStyle(color: Colors.white))),
          ListTile(leading: Icon(Icons.system_update, color: Colors.orangeAccent), title: Text('下位机固件 OTA 升级', style: TextStyle(color: Colors.white))),
        ],
      ),
    );
  }
}
