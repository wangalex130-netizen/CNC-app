import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SmartCncApp());
}

class SmartCncApp extends StatelessWidget {
  const SmartCncApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart CNC Pro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        primaryColor: const Color(0xFFFF6700), // 小米/拓竹橙
        scaffoldBackgroundColor: const Color(0xFF0F1117),
        cardColor: const Color(0xFF1A1D26),
        appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF141720), elevation: 0),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Color(0xFF141720),
          selectedItemColor: Color(0xFFFF6700),
          unselectedItemColor: Colors.white38,
        ),
      ),
      home: const MainDashboard(),
    );
  }
}

class MainDashboard extends StatefulWidget {
  const MainDashboard({Key? key}) : super(key: key);

  @override
  State<MainDashboard> createState() => _MainDashboardState();
}

class _MainDashboardState extends State<MainDashboard> {
  int _tabIndex = 0;

  // 设备状态
  String _machineStatus = '就绪'; // 就绪, 正在雕刻, 暂停中, 异常告警
  bool _isLanMode = true;
  bool _isDoorClosed = true;
  bool _isLightOn = true;
  bool _isAirBlastOn = false;
  bool _isDustCollectorOn = false;

  // DRO 坐标与工件原点设定 (WCS G54)
  double _xPos = 120.450, _yPos = 85.200, _zPos = -12.500;
  double _feedrateOverride = 100; // 进给倍率 10% - 200%
  double _spindleOverride = 100;  // 主轴转速倍率 50% - 150%
  int _currentTool = 1;

  // 雕刻任务仿真
  bool _isExecutingJob = false;
  bool _isJobPaused = false;
  double _jobProgress = 0.0;
  String _activeJobTitle = '';
  Timer? _jobProgressTimer;

  @override
  void dispose() {
    _jobProgressTimer?.cancel();
    super.dispose();
  }

  // 开始执行雕刻
  void _startJob(String jobName) {
    _jobProgressTimer?.cancel();
    setState(() {
      _activeJobTitle = jobName;
      _isExecutingJob = true;
      _isJobPaused = false;
      _jobProgress = 0.0;
      _machineStatus = '正在雕刻';
      _tabIndex = 0; // 自动跳转至首页看进度
    });

    // 仿真模拟加工进度推进
    _jobProgressTimer = Timer.periodic(const Duration(milliseconds: 600), (timer) {
      if (!_isJobPaused && _isExecutingJob) {
        setState(() {
          _jobProgress += 0.02;
          if (_jobProgress >= 1.0) {
            _jobProgress = 1.0;
            _isExecutingJob = false;
            _machineStatus = '就绪';
            timer.cancel();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('🎉 雕刻任务《$_activeJobTitle》已顺利完成！'), backgroundColor: const Color(0xFF00AE42)),
            );
          }
        });
      }
    });
  }

  // 暂停 / 继续
  void _togglePauseJob() {
    setState(() {
      _isJobPaused = !_isJobPaused;
      _machineStatus = _isJobPaused ? '暂停中' : '正在雕刻';
    });
  }

  // 终止任务
  void _stopJob() {
    _jobProgressTimer?.cancel();
    setState(() {
      _isExecutingJob = false;
      _isJobPaused = false;
      _jobProgress = 0.0;
      _machineStatus = '就绪';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已终止加工，主轴停转并安全抬刀。'), backgroundColor: Colors.orangeAccent),
    );
  }

  void _openPairingModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const DevicePairingModal(),
    );
  }

  void _showPrepareJobWizard(BuildContext context, String jobTitle) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => JobPreparationModal(
        jobTitle: jobTitle,
        currentX: _xPos,
        currentY: _yPos,
        onConfirmStart: () {
          Navigator.pop(context);
          _startJob(jobTitle);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildTopAppBar(),
      body: Column(
        children: [
          _buildGlobalStatusHeader(),
          Expanded(
            child: IndexedStack(
              index: _tabIndex,
              children: [
                // 1. 首页：监视与雕刻进度
                DeviceHomeView(
                  isExecuting: _isExecutingJob,
                  isPaused: _isJobPaused,
                  jobTitle: _activeJobTitle,
                  progress: _jobProgress,
                  isLightOn: _isLightOn,
                  isAirOn: _isAirBlastOn,
                  isDustOn: _isDustCollectorOn,
                  onToggleLight: () => setState(() => _isLightOn = !_isLightOn),
                  onToggleAir: () => setState(() => _isAirBlastOn = !_isAirBlastOn),
                  onToggleDust: () => setState(() => _isDustCollectorOn = !_isDustCollectorOn),
                  onPauseToggle: _togglePauseJob,
                  onStopJob: _stopJob,
                ),
                // 2. 轴控与对原点 (设置 X/Y/Z 工件原点)
                MotionControlView(
                  x: _xPos, y: _yPos, z: _zPos,
                  isLanMode: _isLanMode,
                  currentTool: _currentTool,
                  onSetZeroX: () => setState(() => _xPos = 0.0),
                  onSetZeroY: () => setState(() => _yPos = 0.0),
                  onSetZeroZ: () => setState(() => _zPos = 0.0),
                  onSetAllZero: () => setState(() { _xPos = 0; _yPos = 0; _zPos = 0; }),
                  onUpdateCoords: (nx, ny, nz) => setState(() { _xPos = nx; _yPos = ny; _zPos = nz; }),
                  onSelectTool: (t) => setState(() => _currentTool = t),
                ),
                // 3. 创作模型库 (点击准备加工 ➔ 唤起向导)
                ModelHubView(
                  onLaunchJobWizard: (title) => _showPrepareJobWizard(context, title),
                ),
                // 4. 设备服务与管理 (原点之外的常规维护)
                DeviceServicesView(
                  onOpenPairing: _openPairingModal,
                ),
              ],
            ),
          ),
          if (_isExecutingJob) _buildOverrideControlBar(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tabIndex,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFFFF6700),
        unselectedItemColor: Colors.white38,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
        unselectedLabelStyle: const TextStyle(fontSize: 11),
        onTap: (i) => setState(() => _tabIndex = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.videocam_outlined), activeIcon: Icon(Icons.videocam), label: '雕刻监视'),
          BottomNavigationBarItem(icon: Icon(Icons.gamepad_outlined), activeIcon: Icon(Icons.gamepad), label: '对机与原点'),
          BottomNavigationBarItem(icon: Icon(Icons.grid_view_outlined), activeIcon: Icon(Icons.grid_view), label: '模型库'),
          BottomNavigationBarItem(icon: Icon(Icons.build_outlined), activeIcon: Icon(Icons.build), label: '工具与维护'),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildTopAppBar() {
    return AppBar(
      titleSpacing: 16,
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFFF6700).withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFFF6700).withOpacity(0.6)),
            ),
            child: const Text('SmartCNC 3020', style: TextStyle(color: Color(0xFFFF6700), fontSize: 13, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: _openPairingModal,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _isLanMode ? const Color(0xFF00AE42).withOpacity(0.15) : Colors.orange.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _isLanMode ? const Color(0xFF00AE42) : Colors.orangeAccent),
              ),
              child: Row(
                children: [
                  Icon(Icons.wifi, size: 12, color: _isLanMode ? const Color(0xFF00AE42) : Colors.orangeAccent),
                  const SizedBox(width: 4),
                  Text(_isLanMode ? '局域网直连 (1ms)' : '远程访问', style: TextStyle(fontSize: 11, color: _isLanMode ? const Color(0xFF00AE42) : Colors.orangeAccent, fontWeight: FontWeight.bold)),
                  const Icon(Icons.keyboard_arrow_down, size: 14, color: Colors.white54),
                ],
              ),
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: () => _showESTOPDialog(context),
            icon: const Icon(Icons.report_problem, color: Colors.redAccent, size: 22),
            tooltip: '紧急停止',
          ),
        ],
      ),
    );
  }

  Widget _buildGlobalStatusHeader() {
    Color statusColor = _machineStatus == '正在雕刻' ? const Color(0xFF00AE42) : (_machineStatus == '异常告警' ? Colors.redAccent : Colors.amberAccent);
    return Container(
      color: const Color(0xFF181B24),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: statusColor)),
              const SizedBox(width: 8),
              Text('设备状态: $_machineStatus', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(width: 16),
              GestureDetector(
                onTap: () => setState(() => _isDoorClosed = !_isDoorClosed),
                child: Row(
                  children: [
                    Icon(_isDoorClosed ? Icons.security : Icons.warning_amber, size: 14, color: _isDoorClosed ? Colors.white54 : Colors.redAccent),
                    const SizedBox(width: 4),
                    Text(_isDoorClosed ? '防护盖闭合' : '防护盖开启!', style: TextStyle(color: _isDoorClosed ? Colors.white54 : Colors.redAccent, fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
          Text(_isExecutingJob ? '主轴: 12,000 RPM' : '主轴: 待机', style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildOverrideControlBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF141720),
        border: Border(top: BorderSide(color: Colors.white10)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('进给速度: ${_feedrateOverride.toInt()}%', style: const TextStyle(color: Colors.white60, fontSize: 10)),
                Slider(
                  value: _feedrateOverride, min: 10, max: 200, divisions: 19,
                  activeColor: const Color(0xFFFF6700),
                  onChanged: (v) => setState(() => _feedrateOverride = v),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('主轴转速: ${_spindleOverride.toInt()}%', style: const TextStyle(color: Colors.white60, fontSize: 10)),
                Slider(
                  value: _spindleOverride, min: 50, max: 150, divisions: 10,
                  activeColor: Colors.cyanAccent,
                  onChanged: (v) => setState(() => _spindleOverride = v),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showESTOPDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF261414),
        title: const Row(
          children: [
            Icon(Icons.report_problem, color: Colors.redAccent),
            SizedBox(width: 8),
            Text('紧急停止切断', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text('下发最高优先级急停指令：主轴与三轴驱动将立刻物理断电！'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消', style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade800),
            onPressed: () {
              Navigator.pop(ctx);
              _stopJob();
            },
            child: const Text('确认急停', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 1. 首页：监视与雕刻控制
// -----------------------------------------------------------------------------
class DeviceHomeView extends StatelessWidget {
  final bool isExecuting, isPaused;
  final String jobTitle;
  final double progress;
  final bool isLightOn, isAirOn, isDustOn;
  final VoidCallback onToggleLight, onToggleAir, onToggleDust;
  final VoidCallback onPauseToggle, onStopJob;

  const DeviceHomeView({
    Key? key,
    required this.isExecuting, required this.isPaused, required this.jobTitle, required this.progress,
    required this.isLightOn, required this.isAirOn, required this.isDustOn,
    required this.onToggleLight, required this.onToggleAir, required this.onToggleDust,
    required this.onPauseToggle, required this.onStopJob,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 摄像头 Live 画面
        Container(
          height: 200,
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white10),
          ),
          child: Stack(
            children: [
              const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.videocam_outlined, size: 48, color: Color(0xFF00AE42)),
                    SizedBox(height: 8),
                    Text('1080P 侧斜视实时画面监控', style: TextStyle(color: Colors.white54, fontSize: 12)),
                  ],
                ),
              ),
              Positioned(
                top: 12, left: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: const Color(0xFF00AE42), borderRadius: BorderRadius.circular(6)),
                  child: const Text('● LIVE', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 雕刻进度卡片 (仅雕刻中出现)
        if (isExecuting) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E222D),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFFF6700)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text('正在雕刻: $jobTitle', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14), overflow: TextOverflow.ellipsis),
                    ),
                    Text('${(progress * 100).toInt()}%', style: const TextStyle(color: Color(0xFFFF6700), fontWeight: FontWeight.bold, fontSize: 20)),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(value: progress, backgroundColor: Colors.white12, color: const Color(0xFFFF6700), minHeight: 8),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: onPauseToggle,
                        icon: Icon(isPaused ? Icons.play_arrow : Icons.pause, size: 18),
                        label: Text(isPaused ? '继续雕刻' : '暂停加工'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isPaused ? const Color(0xFF00AE42) : Colors.orange.shade800,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onStopJob,
                        icon: const Icon(Icons.stop, color: Colors.redAccent, size: 18),
                        label: const Text('终止任务', style: TextStyle(color: Colors.redAccent)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.redAccent),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // 辅助设备快捷开关
        const Text('设备辅助设施', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Row(
          children: [
            _quickSwitchTile('照明灯', Icons.lightbulb_outline, isLightOn, onToggleLight),
            const SizedBox(width: 12),
            _quickSwitchTile('切削吹气', Icons.air, isAirOn, onToggleAir),
            const SizedBox(width: 12),
            _quickSwitchTile('吸尘收集', Icons.cleaning_services_outlined, isDustOn, onToggleDust),
          ],
        ),
      ],
    );
  }

  Widget _quickSwitchTile(String title, IconData icon, bool isOn, VoidCallback onToggle) {
    return Expanded(
      child: GestureDetector(
        onTap: onToggle,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          decoration: BoxDecoration(
            color: isOn ? const Color(0xFFFF6700).withOpacity(0.15) : const Color(0xFF1A1D26),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: isOn ? const Color(0xFFFF6700) : Colors.white10),
          ),
          child: Column(
            children: [
              Icon(icon, color: isOn ? const Color(0xFFFF6700) : Colors.white38, size: 24),
              const SizedBox(height: 8),
              Text(title, style: TextStyle(color: isOn ? Colors.white : Colors.white54, fontSize: 11, fontWeight: FontWeight.bold)),
              Text(isOn ? '开启' : '关闭', style: TextStyle(color: isOn ? const Color(0xFFFF6700) : Colors.white30, fontSize: 10)),
            ],
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 2. 轴控与对原点 (设置工件原点 Set WCS Zero)
// -----------------------------------------------------------------------------
class MotionControlView extends StatefulWidget {
  final double x, y, z;
  final bool isLanMode;
  final int currentTool;
  final VoidCallback onSetZeroX, onSetZeroY, onSetZeroZ, onSetAllZero;
  final Function(double, double, double) onUpdateCoords;
  final Function(int) onSelectTool;

  const MotionControlView({
    Key? key,
    required this.x, required this.y, required this.z,
    required this.isLanMode, required this.currentTool,
    required this.onSetZeroX, required this.onSetZeroY, required this.onSetZeroZ, required this.onSetAllZero,
    required this.onUpdateCoords, required this.onSelectTool,
  }) : super(key: key);

  @override
  State<MotionControlView> createState() => _MotionControlViewState();
}

class _MotionControlViewState extends State<MotionControlView> {
  double _step = 1.0;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // DRO 大字号数显与原点设定按钮
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: const Color(0xFF1A1D26), borderRadius: BorderRadius.circular(16)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('工件坐标系 (WCS G54)', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                  ElevatedButton.icon(
                    onPressed: widget.onSetAllZero,
                    icon: const Icon(Icons.my_location, size: 14),
                    label: const Text('XYZ 设为当前原点', style: TextStyle(fontSize: 11)),
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF6700)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _axisGaugeWithZero('X 轴', widget.x, Colors.redAccent, widget.onSetZeroX),
                  _axisGaugeWithZero('Y 轴', widget.y, Colors.greenAccent, widget.onSetZeroY),
                  _axisGaugeWithZero('Z 轴', widget.z, Colors.blueAccent, widget.onSetZeroZ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Jog 点动控制器
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: const Color(0xFF1A1D26), borderRadius: BorderRadius.circular(16)),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('手动 Jog 点动对机', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                  Row(
                    children: [0.1, 1.0, 10.0].map((s) {
                      bool sel = _step == s;
                      return GestureDetector(
                        onTap: () => setState(() => _step = s),
                        child: Container(
                          margin: const EdgeInsets.only(left: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: sel ? const Color(0xFFFF6700) : Colors.white10,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text('${s}mm', style: TextStyle(color: sel ? Colors.black : Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  SizedBox(
                    width: 140, height: 140,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Positioned(top: 0, child: _jogBtn('Y+', () => widget.onUpdateCoords(widget.x, widget.y + _step, widget.z))),
                        Positioned(bottom: 0, child: _jogBtn('Y-', () => widget.onUpdateCoords(widget.x, widget.y - _step, widget.z))),
                        Positioned(left: 0, child: _jogBtn('X-', () => widget.onUpdateCoords(widget.x - _step, widget.y, widget.z))),
                        Positioned(right: 0, child: _jogBtn('X+', () => widget.onUpdateCoords(widget.x + _step, widget.y, widget.z))),
                      ],
                    ),
                  ),
                  Column(
                    children: [
                      _jogBtn('Z+', () => widget.onUpdateCoords(widget.x, widget.y, widget.z + _step)),
                      const SizedBox(height: 12),
                      _jogBtn('Z-', () => widget.onUpdateCoords(widget.x, widget.y, widget.z - _step)),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ATC 换刀测试
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: const Color(0xFF1A1D26), borderRadius: BorderRadius.circular(16)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('ATC 刀仓工位选择', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Row(
                children: [
                  _toolTile(1, '3.175 平刀'),
                  _toolTile(2, '60°V型 刀'),
                  _toolTile(3, '2.0 球头刀'),
                  _toolTile(4, '自动对刀块'),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _axisGaugeWithZero(String label, double value, Color color, VoidCallback onSetZero) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(10)),
        child: Column(
          children: [
            Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(value.toStringAsFixed(3), style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
            const SizedBox(height: 6),
            InkWell(
              onTap: onSetZero,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: color.withOpacity(0.2), borderRadius: BorderRadius.circular(4)),
                child: Text('清零', style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _jogBtn(String label, VoidCallback onPressed) {
    return ElevatedButton(
      onPressed: widget.isLanMode ? onPressed : null,
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF262B38),
        minimumSize: const Size(44, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
    );
  }

  Widget _toolTile(int slot, String name) {
    bool isSelected = widget.currentTool == slot;
    return Expanded(
      child: GestureDetector(
        onTap: () => widget.onSelectTool(slot),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFFFF6700).withOpacity(0.2) : Colors.black26,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: isSelected ? const Color(0xFFFF6700) : Colors.white10),
          ),
          child: Column(
            children: [
              Text('T$slot', style: TextStyle(color: isSelected ? const Color(0xFFFF6700) : Colors.white, fontWeight: FontWeight.bold)),
              Text(name, style: const TextStyle(color: Colors.white38, fontSize: 9)),
            ],
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 3. 创作模型库
// -----------------------------------------------------------------------------
class ModelHubView extends StatelessWidget {
  final Function(String) onLaunchJobWizard;

  const ModelHubView({Key? key, required this.onLaunchJobWizard}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('官方精选雕刻工程库', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        _modelCard('木质榫卯手机支架', '120 × 80 × 12 mm', '4mm 椴木板', '约 15 分钟', () => onLaunchJobWizard('木质榫卯手机支架')),
        _modelCard('复古雕花黄铜茶杯垫', '90 × 90 × 3 mm', '黄铜板/胡桃木', '约 25 分钟', () => onLaunchJobWizard('复古雕花黄铜茶杯垫')),
        _modelCard('PCB 双面测试电路板', '80 × 50 × 1.6 mm', '单面覆铜板', '约 10 分钟', () => onLaunchJobWizard('PCB 双面测试电路板')),
      ],
    );
  }

  Widget _modelCard(String title, String size, String material, String time, VoidCallback onStartWizard) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xFF1A1D26), borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          Container(
            width: 50, height: 50,
            decoration: BoxDecoration(color: const Color(0xFFFF6700).withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.precision_manufacturing, color: Color(0xFFFF6700)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 4),
                Text('$size | $material', style: const TextStyle(color: Colors.white38, fontSize: 10)),
                Text(time, style: const TextStyle(color: Color(0xFF00AE42), fontSize: 10, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: onStartWizard,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF6700),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('准备雕刻', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 4. 设备工具与服务 (台面扫平 / 配网OTA)
// -----------------------------------------------------------------------------
class DeviceServicesView extends StatelessWidget {
  final VoidCallback onOpenPairing;

  const DeviceServicesView({Key? key, required this.onOpenPairing}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('设备保养与高级功能', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        _serviceTile(Icons.cleaning_services, '台面平面铣平清理', '使用平刀一键扫平牺牲底板', () {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已发送台面扫平指令，主轴启动中...')));
        }),
        _serviceTile(Icons.home_work, '机器归零复位 ($H)', '让三轴快速回归机械原点', () {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('机器正在执行全轴归零工作...')));
        }),
        _serviceTile(Icons.bluetooth, '设备蓝牙配网与绑定', '重新绑定附近 SmartCNC 机器', onOpenPairing),
        _serviceTile(Icons.system_update, '固件 OTA 升级', '当前版本: v2.4.0 (已是最新)', () {}),
      ],
    );
  }

  Widget _serviceTile(IconData icon, String title, String desc, VoidCallback onTap) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(color: const Color(0xFF1A1D26), borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon, color: const Color(0xFFFF6700)),
        title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
        subtitle: Text(desc, style: const TextStyle(color: Colors.white38, fontSize: 10)),
        trailing: const Icon(Icons.arrow_forward_ios, size: 12, color: Colors.white38),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 雕刻前准备向导 Modal (整合：工件原点确认 ➔ 激光循边 ➔ 自动对刀)
// -----------------------------------------------------------------------------
class JobPreparationModal extends StatefulWidget {
  final String jobTitle;
  final double currentX, currentY;
  final VoidCallback onConfirmStart;

  const JobPreparationModal({
    Key? key,
    required this.jobTitle,
    required this.currentX, required this.currentY,
    required this.onConfirmStart,
  }) : super(key: key);

  @override
  State<JobPreparationModal> createState() => _JobPreparationModalState();
}

class _JobPreparationModalState extends State<JobPreparationModal> {
  bool _isFramingDone = false;
  bool _isProbingDone = false;
  bool _isProbingRunning = false;

  @override
  Widget build(BuildContext context) {
    bool canStart = _isFramingDone && _isProbingDone;

    return Container(
      height: MediaQuery.of(context).size.height * 0.72,
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Color(0xFF1A1D26),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('雕刻前准备向导 - 《${widget.jobTitle}》', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
          const Divider(color: Colors.white10, height: 20),
          Expanded(
            child: ListView(
              children: [
                // Step 1: 原点确认
                _stepBox(
                  '1', '工件零点确认', '已锁定当前位置为加工原点 (X0, Y0)',
                  const Icon(Icons.check_circle, color: Color(0xFF00AE42), size: 20),
                ),
                const SizedBox(height: 12),

                // Step 2: 激光红光循边
                _stepBox(
                  '2', '运行激光红光框线循边', '预览加工区域，确认未碰撞或超界',
                  ElevatedButton.icon(
                    onPressed: () => setState(() => _isFramingDone = true),
                    icon: Icon(_isFramingDone ? Icons.check : Icons.crop_free, size: 14),
                    label: Text(_isFramingDone ? '预览完成' : '运行红光预览', style: const TextStyle(fontSize: 10)),
                    style: ElevatedButton.styleFrom(backgroundColor: _isFramingDone ? const Color(0xFF00AE42) : const Color(0xFFFF6700)),
                  ),
                ),
                const SizedBox(height: 12),

                // Step 3: 一键自动下探对刀
                _stepBox(
                  '3', '自动精准下探对刀', '对刀快测定刀尖与板材表面 Z0 零点',
                  ElevatedButton.icon(
                    onPressed: _isProbingRunning ? null : () async {
                      setState(() => _isProbingRunning = true);
                      await Future.delayed(const Duration(seconds: 2)); // 模拟自动对刀过程
                      setState(() {
                        _isProbingRunning = false;
                        _isProbingDone = true;
                      });
                    },
                    icon: _isProbingRunning
                        ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Icon(_isProbingDone ? Icons.check : Icons.vertical_align_bottom, size: 14),
                    label: Text(_isProbingRunning ? '对刀中...' : (_isProbingDone ? '对刀成功' : '一键自动对刀'), style: const TextStyle(fontSize: 10)),
                    style: ElevatedButton.styleFrom(backgroundColor: _isProbingDone ? const Color(0xFF00AE42) : Colors.blueAccent),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: canStart ? widget.onConfirmStart : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6700),
                disabledBackgroundColor: Colors.white12,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(
                canStart ? '全部校验就绪，解锁开始雕刻 ➔' : '请先完成 Step 2 循边预览与 Step 3 自动对刀',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: canStart ? Colors.white : Colors.white38),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepBox(String stepNum, String title, String subtitle, Widget trailing) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          CircleAvatar(radius: 12, backgroundColor: const Color(0xFFFF6700), child: Text(stepNum, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold))),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                Text(subtitle, style: const TextStyle(color: Colors.white38, fontSize: 10)),
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 配网 Modal
// -----------------------------------------------------------------------------
class DevicePairingModal extends StatelessWidget {
  const DevicePairingModal({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.45,
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Color(0xFF1A1D26),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('SmartCNC 设备蓝牙配网', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
          const Divider(color: Colors.white10, height: 20),
          const ListTile(
            leading: Icon(Icons.bluetooth, color: Color(0xFFFF6700)),
            title: Text('SmartCNC-3020-A88F', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
            subtitle: Text('BLE 连接成功 | WebSocket 局域网直连 (1ms)', style: TextStyle(color: Colors.white38, fontSize: 10)),
            trailing: Icon(Icons.check_circle, color: Color(0xFF00AE42)),
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF6700), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: const Text('返回终端', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}
