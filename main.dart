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
        primaryColor: const Color(0xFFFF6700), // 小米/拓竹活力橙
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

  // 设备状态全局变量
  String _machineStatus = '就绪'; // 就绪, 正在雕刻, 暂停中, 异常告警
  bool _isLanMode = true;
  bool _isDoorClosed = true;
  bool _isLightOn = true;
  bool _isAirBlastOn = false;
  bool _isDustCollectorOn = false;

  // 坐标与刀具数据
  double _xPos = 120.450, _yPos = 85.200, _zPos = -12.500, _aPos = 0.00;
  double _feedrateOverride = 100; // 10% - 200%
  double _spindleOverride = 100;  // 50% - 150%
  int _currentTool = 1;

  // 任务执行仿真逻辑
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

  // 开始新任务
  void _startJob(String jobName) {
    _jobProgressTimer?.cancel();
    setState(() {
      _activeJobTitle = jobName;
      _isExecutingJob = true;
      _isJobPaused = false;
      _jobProgress = 0.0;
      _machineStatus = '正在雕刻';
      _tabIndex = 0; // 自动跳转至首页监控
    });

    // 模拟真实的雕刻进度推进
    _jobProgressTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
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

  // 暂停或继续任务
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
      const SnackBar(content: Text('已停止当前雕刻任务，主轴已归位。'), backgroundColor: Colors.orangeAccent),
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
                // Tab 0: 设备首页
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
                // Tab 1: 轴控与刀仓
                MotionControlView(
                  x: _xPos, y: _yPos, z: _zPos, a: _aPos,
                  isLanMode: _isLanMode,
                  currentTool: _currentTool,
                  onUpdateCoords: (nx, ny, nz) => setState(() {
                    _xPos = nx; _yPos = ny; _zPos = nz;
                  }),
                  onSelectTool: (t) => setState(() => _currentTool = t),
                ),
                // Tab 2: 创作模型库
                ModelHubView(
                  onLaunchJobWizard: (title) => _showPrepareJobWizard(context, title),
                ),
                // Tab 3: 一键维护 (替换原硬核终端与宏)
                QuickMaintenanceView(
                  onRunMaintenance: (actionName) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('正在执行: $actionName...'), duration: const Duration(seconds: 2)),
                    );
                  },
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
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined), activeIcon: Icon(Icons.home), label: '设备'),
          BottomNavigationBarItem(icon: Icon(Icons.tune_outlined), activeIcon: Icon(Icons.tune), label: '调机与刀仓'),
          BottomNavigationBarItem(icon: Icon(Icons.grid_view_outlined), activeIcon: Icon(Icons.grid_view), label: '创作模型库'),
          BottomNavigationBarItem(icon: Icon(Icons.build_outlined), activeIcon: Icon(Icons.build), label: '一键维护'),
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
              Text('运行状态: $_machineStatus', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
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
                Text('进给速度倍率: ${_feedrateOverride.toInt()}%', style: const TextStyle(color: Colors.white60, fontSize: 10)),
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
                Text('主轴转速倍率: ${_spindleOverride.toInt()}%', style: const TextStyle(color: Colors.white60, fontSize: 10)),
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

  void _showPrepareJobWizard(BuildContext context, String jobTitle) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => JobPreparationModal(
        jobTitle: jobTitle,
        onConfirmStart: () {
          Navigator.pop(context);
          _startJob(jobTitle);
        },
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
// 1. 首页 (小米/拓竹风格卡片看板)
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
        // 摄像头 Live 画面卡片
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
                    Text('1080P 高清监视画幅', style: TextStyle(color: Colors.white54, fontSize: 12)),
                  ],
                ),
              ),
              Positioned(
                top: 12, left: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: const Color(0xFF00AE42), borderRadius: BorderRadius.circular(6)),
                  child: const Text('● 实时直播', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 雕刻实时进度卡片 (仅在雕刻时或有任务时显示)
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

        // 智能开关快捷开关网格
        const Text('快捷辅助控制', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
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
        const SizedBox(height: 16),

        // 米家风格事件日志列表
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: const Color(0xFF1A1D26), borderRadius: BorderRadius.circular(16)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('设备近期动态', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              _eventLogItem('15:02', '传感器自检完成，防护盖状态正常'),
              _eventLogItem('14:55', '完成了《木质手机支架》对刀动作'),
              _eventLogItem('14:30', '设备连接至局域网 WebSocket 服务'),
            ],
          ),
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
              Text(isOn ? '已开启' : '已关闭', style: TextStyle(color: isOn ? const Color(0xFFFF6700) : Colors.white30, fontSize: 10)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _eventLogItem(String time, String content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        children: [
          Text(time, style: const TextStyle(color: Colors.white38, fontSize: 11, fontFamily: 'monospace')),
          const SizedBox(width: 12),
          Expanded(child: Text(content, style: const TextStyle(color: Colors.white70, fontSize: 11))),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 2. 调机与刀仓 (DRO Gauges + Jog)
// -----------------------------------------------------------------------------
class MotionControlView extends StatefulWidget {
  final double x, y, z, a;
  final bool isLanMode;
  final int currentTool;
  final Function(double, double, double) onUpdateCoords;
  final Function(int) onSelectTool;

  const MotionControlView({
    Key? key,
    required this.x, required this.y, required this.z, required this.a,
    required this.isLanMode, required this.currentTool,
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
        // DRO 坐标大字号数字看板
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: const Color(0xFF1A1D26), borderRadius: BorderRadius.circular(16)),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('坐标读出 (WCS G54)', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                  TextButton(
                    onPressed: () => widget.onUpdateCoords(0, 0, 0),
                    child: const Text('相对零点清零', style: TextStyle(color: Color(0xFFFF6700), fontSize: 12)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _axisGauge('X 轴', widget.x, Colors.redAccent),
                  _axisGauge('Y 轴', widget.y, Colors.greenAccent),
                  _axisGauge('Z 轴', widget.z, Colors.blueAccent),
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
                  const Text('手动微调点动', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
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

        // ATC 换刀位选择
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: const Color(0xFF1A1D26), borderRadius: BorderRadius.circular(16)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('ATC 自动换刀仓选择', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
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

  Widget _axisGauge(String label, double value, Color color) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(10)),
        child: Column(
          children: [
            Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(value.toStringAsFixed(3), style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
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
// 3. 创作模型库 (Bambu Handy 风格)
// -----------------------------------------------------------------------------
class ModelHubView extends StatelessWidget {
  final Function(String) onLaunchJobWizard;

  const ModelHubView({Key? key, required this.onLaunchJobWizard}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('官方推荐模型预设', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        _modelCard('木质榫卯手机支架', '120 × 80 × 12 mm', '推荐: 4mm 椴木板', '预计 15 分钟', () => onLaunchJobWizard('木质榫卯手机支架')),
        _modelCard('复古雕花黄铜茶杯垫', '90 × 90 × 3 mm', '推荐: 黄铜/胡桃木', '预计 25 分钟', () => onLaunchJobWizard('复古雕花黄铜茶杯垫')),
        _modelCard('PCB 双面测试电路板', '80 × 50 × 1.6 mm', '推荐: 覆铜板', '预计 10 分钟', () => onLaunchJobWizard('PCB 双面测试电路板')),
      ],
    );
  }

  Widget _modelCard(String title, String size, String material, String time, VoidCallback onPrepare) {
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
            onPressed: onPrepare,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF6700),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('准备加工', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 4. 一键维护 (替换硬核终端与宏)
// -----------------------------------------------------------------------------
class QuickMaintenanceView extends StatelessWidget {
  final Function(String) onRunMaintenance;

  const QuickMaintenanceView({Key? key, required this.onRunMaintenance}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('一键式维护与对刀快捷工具', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.4,
          children: [
            _maintCard('🎯 一键自动对刀', '自动下探定位 Z0 零点', Icons.vertical_align_bottom, () => onRunMaintenance('一键自动对刀')),
            _maintCard('📐 激光红光循边', '通过红光框线预览加工区域', Icons.crop_free, () => onRunMaintenance('激光红光循边')),
            _maintCard('🏠 机器一键复位', '安全回机械零点位置', Icons.home, () => onRunMaintenance('机器一键复位')),
            _maintCard('🧹 台面平整清理', '一键铣平牺牲底板', Icons.cleaning_services, () => onRunMaintenance('台面平整清理')),
          ],
        ),
      ],
    );
  }

  Widget _maintCard(String title, String desc, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: const Color(0xFF1A1D26), borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: const Color(0xFFFF6700), size: 24),
            const SizedBox(height: 8),
            Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
            const SizedBox(height: 2),
            Text(desc, style: const TextStyle(color: Colors.white38, fontSize: 9)),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 雕刻向导弹窗 Modal
// -----------------------------------------------------------------------------
class JobPreparationModal extends StatefulWidget {
  final String jobTitle;
  final VoidCallback onConfirmStart;

  const JobPreparationModal({Key? key, required this.jobTitle, required this.onConfirmStart}) : super(key: key);

  @override
  State<JobPreparationModal> createState() => _JobPreparationModalState();
}

class _JobPreparationModalState extends State<JobPreparationModal> {
  bool _isAutoProbed = false;
  bool _isFramed = false;

  @override
  Widget build(BuildContext context) {
    bool canStart = _isAutoProbed && _isFramed;
    return Container(
      height: MediaQuery.of(context).size.height * 0.65,
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Color(0xFF1A1D26),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('加工前准备 - 《${widget.jobTitle}》', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
          const Divider(color: Colors.white10, height: 20),
          Expanded(
            child: ListView(
              children: [
                CheckboxListTile(
                  title: const Text('步骤 1: 运行红光框线预览', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                  subtitle: const Text('确认板材未超界、无撞机隐患', style: TextStyle(color: Colors.white38, fontSize: 10)),
                  value: _isFramed,
                  activeColor: const Color(0xFFFF6700),
                  onChanged: (v) => setState(() => _isFramed = v!),
                ),
                CheckboxListTile(
                  title: const Text('步骤 2: 执行自动对刀锁零', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                  subtitle: const Text('对刀传感器自动测定 Z 轴表面高度', style: TextStyle(color: Colors.white38, fontSize: 10)),
                  value: _isAutoProbed,
                  activeColor: const Color(0xFFFF6700),
                  onChanged: (v) => setState(() => _isAutoProbed = v!),
                ),
              ],
            ),
          ),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton(
              onPressed: canStart ? widget.onConfirmStart : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6700),
                disabledBackgroundColor: Colors.white12,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(canStart ? '确认无误，开始加工' : '请先完成前置对刀与预览', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 配网向导 Modal
// -----------------------------------------------------------------------------
class DevicePairingModal extends StatelessWidget {
  const DevicePairingModal({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.5,
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Color(0xFF1A1D26),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('设备网络连接与蓝牙绑定', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
          const Divider(color: Colors.white10, height: 20),
          const SizedBox(height: 10),
          ListTile(
            leading: const Icon(Icons.bluetooth, color: Color(0xFFFF6700)),
            title: const Text('SmartCNC-3020-A88F', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
            subtitle: const Text('信号强度: 强 | 已通过 BLE 绑定账号', style: TextStyle(color: Colors.white38, fontSize: 10)),
            trailing: const Icon(Icons.check_circle, color: Color(0xFF00AE42)),
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF6700), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: const Text('返回控制终端', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}
