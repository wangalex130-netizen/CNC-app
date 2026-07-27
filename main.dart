import 'dart:async';
import 'package:flutter/material.dart';

/// ============================================================
/// 包覆款桌面 CNC 智能控制 App（友好化重设计 · 单文件版）
/// 原 8 个文件已合并于此，直接替换你仓库里的 lib/main.dart 即可
/// ============================================================

// ----------------------------- 工具函数 -----------------------------
String formatDuration(int totalSeconds) {
  final s = totalSeconds < 0 ? 0 : totalSeconds;
  final m = s ~/ 60;
  final sec = s % 60;
  return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
}

String statusText(String status) {
  switch (status) {
    case 'RUN':
      return '工作中';
    case 'ALARM':
      return '报警';
    case 'HOLD':
      return '已暂停';
    default:
      return '空闲';
  }
}

Color statusColor(String status) {
  switch (status) {
    case 'RUN':
      return const Color(0xFF19B36B);
    case 'ALARM':
      return const Color(0xFFE5484D);
    case 'HOLD':
      return const Color(0xFFF2A33C);
    default:
      return const Color(0xFF9AA0A6);
  }
}

BoxDecoration cardDecoration() {
  return BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(16),
    boxShadow: const [
      BoxShadow(color: Color(0x0D000000), blurRadius: 10, offset: Offset(0, 2)),
    ],
  );
}

Widget sectionTitle(String text) {
  return Text(
    text,
    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF1A1D1F)),
  );
}

// ----------------------------- 常量 -----------------------------
const List<Map<String, String>> kTools = [
  {'slot': '1', 'name': '3.175 平底刀'},
  {'slot': '2', 'name': '60° V 型刀'},
  {'slot': '3', 'name': '2.0 球头刀'},
  {'slot': '4', 'name': '自动对刀块'},
];

const List<Map<String, String>> kProjects = [
  {'name': '铝合金散热壳加工', 'size': '100 × 60 × 15 mm', 'tools': 'T1 平底刀', 'duration': '75'},
  {'name': '木质榫卯手机支架', 'size': '150 × 80 × 12 mm', 'tools': 'T1 / T2', 'duration': '90'},
  {'name': 'PCB 电路板雕刻 V2', 'size': '80 × 50 × 1.6 mm', 'tools': 'T2 V 型刀', 'duration': '60'},
  {'name': '亚克力收纳盒', 'size': '120 × 90 × 40 mm', 'tools': 'T1 / T3', 'duration': '120'},
];

// ----------------------------- 共享状态 -----------------------------
class MachineState {
  final bool isLanMode;
  final String status;
  final bool doorClosed;
  final bool lightOn;
  final bool airOn;
  final bool dustOn;
  final double x, y, z;
  final int tool;
  final double feedOverride;
  final double spindleOverride;
  final bool jobRunning;
  final bool jobPaused;
  final double jobProgress;
  final String jobName;
  final int jobElapsedSec;
  final int jobDurationSec;
  final List<String> activityLog;

  const MachineState({
    required this.isLanMode,
    required this.status,
    required this.doorClosed,
    required this.lightOn,
    required this.airOn,
    required this.dustOn,
    required this.x,
    required this.y,
    required this.z,
    required this.tool,
    required this.feedOverride,
    required this.spindleOverride,
    required this.jobRunning,
    required this.jobPaused,
    required this.jobProgress,
    required this.jobName,
    required this.jobElapsedSec,
    required this.jobDurationSec,
    required this.activityLog,
  });

  factory MachineState.initial() => MachineState(
        isLanMode: true,
        status: 'IDLE',
        doorClosed: true,
        lightOn: true,
        airOn: false,
        dustOn: false,
        x: 120.450,
        y: 85.200,
        z: -12.500,
        tool: 1,
        feedOverride: 100,
        spindleOverride: 100,
        jobRunning: false,
        jobPaused: false,
        jobProgress: 0,
        jobName: '',
        jobElapsedSec: 0,
        jobDurationSec: 75,
        activityLog: const ['设备已就绪，等待指令'],
      );

  MachineState copyWith({
    bool? isLanMode,
    String? status,
    bool? doorClosed,
    bool? lightOn,
    bool? airOn,
    bool? dustOn,
    double? x,
    double? y,
    double? z,
    int? tool,
    double? feedOverride,
    double? spindleOverride,
    bool? jobRunning,
    bool? jobPaused,
    double? jobProgress,
    String? jobName,
    int? jobElapsedSec,
    int? jobDurationSec,
    List<String>? activityLog,
  }) {
    return MachineState(
      isLanMode: isLanMode ?? this.isLanMode,
      status: status ?? this.status,
      doorClosed: doorClosed ?? this.doorClosed,
      lightOn: lightOn ?? this.lightOn,
      airOn: airOn ?? this.airOn,
      dustOn: dustOn ?? this.dustOn,
      x: x ?? this.x,
      y: y ?? this.y,
      z: z ?? this.z,
      tool: tool ?? this.tool,
      feedOverride: feedOverride ?? this.feedOverride,
      spindleOverride: spindleOverride ?? this.spindleOverride,
      jobRunning: jobRunning ?? this.jobRunning,
      jobPaused: jobPaused ?? this.jobPaused,
      jobProgress: jobProgress ?? this.jobProgress,
      jobName: jobName ?? this.jobName,
      jobElapsedSec: jobElapsedSec ?? this.jobElapsedSec,
      jobDurationSec: jobDurationSec ?? this.jobDurationSec,
      activityLog: activityLog ?? this.activityLog,
    );
  }
}

class MachineActions {
  final VoidCallback toggleLight;
  final VoidCallback toggleAir;
  final VoidCallback toggleDust;
  final VoidCallback toggleDoor;
  final void Function(double dx, double dy, double dz) jog;
  final void Function(int) selectTool;
  final void Function(double) setFeed;
  final void Function(double) setSpindle;
  final void Function(String, int) startJob;
  final VoidCallback pauseJob;
  final VoidCallback resumeJob;
  final VoidCallback abortJob;
  final void Function(String) addLog;
  final VoidCallback requestPairing;
  final VoidCallback estop;
  final VoidCallback clearAlarm;

  const MachineActions({
    required this.toggleLight,
    required this.toggleAir,
    required this.toggleDust,
    required this.toggleDoor,
    required this.jog,
    required this.selectTool,
    required this.setFeed,
    required this.setSpindle,
    required this.startJob,
    required this.pauseJob,
    required this.resumeJob,
    required this.abortJob,
    required this.addLog,
    required this.requestPairing,
    required this.estop,
    required this.clearAlarm,
  });
}

// ----------------------------- 程序入口 -----------------------------
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart CNC',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        primaryColor: const Color(0xFF19B36B),
        scaffoldBackgroundColor: const Color(0xFFF4F6F8),
        appBarTheme: const AppBarTheme(backgroundColor: Colors.white, foregroundColor: Color(0xFF1A1D1F), elevation: 0),
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF19B36B), brightness: Brightness.light),
        cardColor: Colors.white,
        sliderTheme: SliderThemeData(
          activeTrackColor: const Color(0xFF19B36B),
          thumbColor: const Color(0xFF19B36B),
          inactiveTrackColor: const Color(0xFFE3E8EC),
        ),
      ),
      home: const MainScaffold(),
    );
  }
}

class MainScaffold extends StatefulWidget {
  const MainScaffold({Key? key}) : super(key: key);
  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  int _tab = 0;
  late MachineState _s;
  Timer? _jobTimer;

  @override
  void initState() {
    super.initState();
    _s = MachineState.initial();
  }

  @override
  void dispose() {
    _jobTimer?.cancel();
    super.dispose();
  }

  String _stamp() {
    final n = DateTime.now();
    return '${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}:${n.second.toString().padLeft(2, '0')}';
  }

  void _log(String msg) {
    setState(() {
      _s = _s.copyWith(activityLog: ['${_stamp()}  $msg', ..._s.activityLog].take(50).toList());
    });
  }

  void _toggleLight() => setState(() => _s = _s.copyWith(lightOn: !_s.lightOn));
  void _toggleAir() => setState(() => _s = _s.copyWith(airOn: !_s.airOn));
  void _toggleDust() => setState(() => _s = _s.copyWith(dustOn: !_s.dustOn));
  void _toggleDoor() => setState(() => _s = _s.copyWith(doorClosed: !_s.doorClosed));

  void _jog(double dx, double dy, double dz) {
    setState(() => _s = _s.copyWith(x: _s.x + dx, y: _s.y + dy, z: _s.z + dz));
  }

  void _selectTool(int t) {
    setState(() => _s = _s.copyWith(tool: t));
    _log('已切换至 T$t 刀具');
  }

  void _setFeed(double v) => setState(() => _s = _s.copyWith(feedOverride: v));
  void _setSpindle(double v) => setState(() => _s = _s.copyWith(spindleOverride: v));

  /// 开始加工：用定时器推进进度，完成后自动回到空闲（修复"卡在执行中"）
  void _startJob(String name, int durationSec) {
    if (_s.jobRunning) return;
    _jobTimer?.cancel();
    setState(() => _s = _s.copyWith(
          jobRunning: true,
          jobPaused: false,
          jobProgress: 0,
          jobElapsedSec: 0,
          jobDurationSec: durationSec,
          jobName: name,
          status: 'RUN',
        ));
    _log('开始加工：$name');
    _jobTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (_s.jobPaused) return;
      final elapsed = _s.jobElapsedSec + 250;
      final p = elapsed / 1000 / _s.jobDurationSec;
      if (p >= 1.0) {
        _jobTimer?.cancel();
        _jobTimer = null;
        setState(() => _s = _s.copyWith(jobProgress: 1.0, jobRunning: false, jobElapsedSec: _s.jobDurationSec * 1000, status: 'IDLE'));
        _log('加工完成：$name');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$name 加工完成 ✅'), backgroundColor: const Color(0xFF19B36B)),
          );
        }
      } else {
        setState(() => _s = _s.copyWith(jobProgress: p, jobElapsedSec: elapsed));
      }
    });
  }

  void _pauseJob() {
    if (!_s.jobRunning || _s.jobPaused) return;
    setState(() => _s = _s.copyWith(jobPaused: true, status: 'HOLD'));
    _log('已暂停加工');
  }

  void _resumeJob() {
    if (!_s.jobRunning || !_s.jobPaused) return;
    setState(() => _s = _s.copyWith(jobPaused: false, status: 'RUN'));
    _log('继续加工');
  }

  void _abortJob() {
    _jobTimer?.cancel();
    _jobTimer = null;
    final name = _s.jobName;
    setState(() => _s = _s.copyWith(jobRunning: false, jobPaused: false, jobProgress: 0, status: 'IDLE'));
    _log('已终止加工：$name');
  }

  void _estop() {
    _jobTimer?.cancel();
    _jobTimer = null;
    setState(() => _s = _s.copyWith(jobRunning: false, jobPaused: false, jobProgress: 0, status: 'ALARM', doorClosed: false));
    _log('⚠ 紧急停止已触发，机器已锁停');
  }

  void _clearAlarm() {
    setState(() => _s = _s.copyWith(status: 'IDLE', doorClosed: true));
    _log('报警已解除，机器恢复空闲');
  }

  void _openPairing() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const PairingSheet(),
    );
  }

  void _confirmEstop() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认紧急停止？'),
        content: const Text('将立即切断主轴与运动驱动，机器会锁停。仅在紧急情况下使用。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(ctx);
              _estop();
            },
            child: const Text('紧急停止'),
          ),
        ],
      ),
    );
  }

  MachineActions _actions() => MachineActions(
        toggleLight: _toggleLight,
        toggleAir: _toggleAir,
        toggleDust: _toggleDust,
        toggleDoor: _toggleDoor,
        jog: _jog,
        selectTool: _selectTool,
        setFeed: _setFeed,
        setSpindle: _setSpindle,
        startJob: _startJob,
        pauseJob: _pauseJob,
        resumeJob: _resumeJob,
        abortJob: _abortJob,
        addLog: _log,
        requestPairing: _openPairing,
        estop: _estop,
        clearAlarm: _clearAlarm,
      );

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      titleSpacing: 12,
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: const Color(0xFF19B36B).withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
            child: const Text('Smart CNC 3020', style: TextStyle(color: Color(0xFF19B36B), fontSize: 13, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: _openPairing,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: Colors.green.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
              child: Row(
                children: [
                  Icon(Icons.wifi, size: 13, color: Colors.green.shade700),
                  const SizedBox(width: 4),
                  Text(_s.isLanMode ? '已连接' : '远程', style: TextStyle(fontSize: 11, color: Colors.green.shade700, fontWeight: FontWeight.w600)),
                  const Icon(Icons.arrow_drop_down, size: 14, color: Colors.black54),
                ],
              ),
            ),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: _confirmEstop,
            icon: const Icon(Icons.power_settings_new, color: Colors.red, size: 16),
            label: const Text('急停', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12)),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
          ),
        ],
      ),
    );
  }

  Widget _buildNavBar() {
    const items = [
      BottomNavigationBarItem(icon: Icon(Icons.home_outlined), activeIcon: Icon(Icons.home), label: '首页'),
      BottomNavigationBarItem(icon: Icon(Icons.tune_outlined), activeIcon: Icon(Icons.tune), label: '控制台'),
      BottomNavigationBarItem(icon: Icon(Icons.widgets_outlined), activeIcon: Icon(Icons.widgets), label: '作品'),
      BottomNavigationBarItem(icon: Icon(Icons.person_outline), activeIcon: Icon(Icons.person), label: '我的'),
    ];
    return BottomNavigationBar(
      currentIndex: _tab,
      type: BottomNavigationBarType.fixed,
      selectedItemColor: const Color(0xFF19B36B),
      unselectedItemColor: Colors.black45,
      selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 11),
      unselectedLabelStyle: const TextStyle(fontSize: 11),
      backgroundColor: Colors.white,
      elevation: 8,
      onTap: (i) => setState(() => _tab = i),
      items: items,
    );
  }

  @override
  Widget build(BuildContext context) {
    final actions = _actions();
    return Scaffold(
      appBar: _buildAppBar(),
      body: IndexedStack(
        index: _tab,
        children: [
          HomeScreen(state: _s, actions: actions, onNavigate: (i) => setState(() => _tab = i)),
          ControlScreen(state: _s, actions: actions),
          ProjectsScreen(state: _s, actions: actions, onNavigate: (i) => setState(() => _tab = i)),
          MoreScreen(state: _s, actions: actions),
        ],
      ),
      bottomNavigationBar: _buildNavBar(),
    );
  }
}

// ----------------------------- 配网向导 -----------------------------
class PairingSheet extends StatefulWidget {
  const PairingSheet({Key? key}) : super(key: key);
  @override
  State<PairingSheet> createState() => _PairingSheetState();
}

class _PairingSheetState extends State<PairingSheet> {
  int _step = 0;
  bool _scanning = false;
  String? _device;
  final _ssid = TextEditingController(text: '我的Wi-Fi_2.4G');
  final _pass = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.78,
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('连接我的 CNC', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: Colors.black45)),
            ],
          ),
          _stepIndicator(),
          const SizedBox(height: 12),
          Expanded(child: _step == 0 ? _scanStep() : _step == 1 ? _wifiStep() : _doneStep()),
        ],
      ),
    );
  }

  Widget _stepIndicator() {
    return Row(
      children: List.generate(3, (i) {
        final active = i <= _step;
        return Expanded(
          child: Container(
            height: 4,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(color: active ? const Color(0xFF19B36B) : const Color(0xFFE3E8EC), borderRadius: BorderRadius.circular(2)),
          ),
        );
      }),
    );
  }

  Widget _scanStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('第 1 步 · 打开手机蓝牙，确保 CNC 已通电', style: TextStyle(color: Colors.black54, fontSize: 13)),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 46,
          child: FilledButton.icon(
            onPressed: () async {
              setState(() => _scanning = true);
              await Future.delayed(const Duration(seconds: 2));
              if (!mounted) return;
              setState(() {
                _scanning = false;
                _device = 'SmartCNC-3020-A88F';
              });
            },
            icon: _scanning
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.bluetooth_searching),
            label: Text(_scanning ? '正在搜索…' : '搜索附近设备'),
          ),
        ),
        const SizedBox(height: 16),
        if (_device != null)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: const Color(0xFF19B36B).withOpacity(0.08), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFF19B36B).withOpacity(0.4))),
            child: Row(
              children: [
                const Icon(Icons.precision_manufacturing, color: Color(0xFF19B36B)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_device!, style: const TextStyle(fontWeight: FontWeight.bold)),
                      const Text('信号强 · 等待连接', style: TextStyle(color: Colors.black45, fontSize: 12)),
                    ],
                  ),
                ),
                FilledButton(onPressed: () => setState(() => _step = 1), child: const Text('连接')),
              ],
            ),
          ),
      ],
    );
  }

  Widget _wifiStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('第 2 步 · 选择 2.4G Wi-Fi 完成联网', style: TextStyle(color: Colors.black54, fontSize: 13)),
        const SizedBox(height: 16),
        TextField(controller: _ssid, decoration: const InputDecoration(labelText: 'Wi-Fi 名称', filled: true, fillColor: Color(0xFFF4F6F8))),
        const SizedBox(height: 12),
        TextField(controller: _pass, obscureText: true, decoration: const InputDecoration(labelText: 'Wi-Fi 密码', filled: true, fillColor: Color(0xFFF4F6F8))),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 46,
          child: FilledButton(onPressed: () => setState(() => _step = 2), child: const Text('完成连接', style: TextStyle(fontWeight: FontWeight.bold))),
        ),
      ],
    );
  }

  Widget _doneStep() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.check_circle, color: Color(0xFF19B36B), size: 64),
        const SizedBox(height: 14),
        const Text('连接成功！', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        const SizedBox(height: 6),
        const Text('已通过局域网直连，控制低延迟', style: TextStyle(color: Colors.black45, fontSize: 13)),
        const SizedBox(height: 24),
        SizedBox(
          width: 220,
          height: 44,
          child: FilledButton(onPressed: () => Navigator.pop(context), child: const Text('开始使用', style: TextStyle(fontWeight: FontWeight.bold))),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _ssid.dispose();
    _pass.dispose();
    super.dispose();
  }
}

// ----------------------------- 首页 -----------------------------
class HomeScreen extends StatelessWidget {
  final MachineState state;
  final MachineActions actions;
  final void Function(int) onNavigate;
  const HomeScreen({Key? key, required this.state, required this.actions, required this.onNavigate}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _statusCard(),
          const SizedBox(height: 16),
          _cameraCard(),
          if (state.jobRunning) ...[
            const SizedBox(height: 16),
            _runningCard(),
          ],
          const SizedBox(height: 16),
          _quickActions(),
          const SizedBox(height: 16),
          _startWorkCard(),
          const SizedBox(height: 16),
          _activityCard(),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _statusCard() {
    final c = statusColor(state.status);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [c.withOpacity(0.14), Colors.white], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(shape: BoxShape.circle, color: c)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Smart CNC 3020', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                Text(state.isLanMode ? '局域网已连接 · 低延迟' : '远程连接 · 45ms', style: const TextStyle(color: Colors.black54, fontSize: 12)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(20)),
            child: Text(statusText(state.status), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _cameraCard() {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        decoration: BoxDecoration(color: const Color(0xFF1A1D1F), borderRadius: BorderRadius.circular(16)),
        child: Stack(
          children: [
            const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.videocam_outlined, size: 40, color: Colors.white70),
                  SizedBox(height: 6),
                  Text('实时加工画面', style: TextStyle(color: Colors.white54, fontSize: 12)),
                ],
              ),
            ),
            Positioned(
              top: 12,
              left: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(6)),
                child: const Text('● LIVE', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ),
            Positioned(
              bottom: 12,
              right: 12,
              child: OutlinedButton.icon(
                onPressed: actions.toggleLight,
                icon: Icon(state.lightOn ? Icons.lightbulb : Icons.lightbulb_outline, size: 14, color: state.lightOn ? Colors.amber : Colors.white70),
                label: Text(state.lightOn ? '舱灯 开' : '舱灯 关', style: const TextStyle(fontSize: 11)),
                style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white30), backgroundColor: Colors.black45),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _runningCard() {
    final elapsedSec = (state.jobDurationSec * state.jobProgress).round();
    final remainSec = (state.jobDurationSec * (1 - state.jobProgress)).round();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.precision_manufacturing, color: Color(0xFF19B36B)),
              const SizedBox(width: 8),
              Expanded(child: Text(state.jobName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14))),
              Text('${(state.jobProgress * 100).toInt()}%', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF19B36B))),
            ],
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(value: state.jobProgress, backgroundColor: const Color(0xFFEDEFF2), color: const Color(0xFF19B36B)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('已用 ${formatDuration(elapsedSec)}', style: const TextStyle(color: Colors.black54, fontSize: 11)),
              Text('剩余 ${formatDuration(remainSec)}', style: const TextStyle(color: Colors.black54, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: state.jobPaused
                    ? FilledButton.icon(onPressed: actions.resumeJob, icon: const Icon(Icons.play_arrow), label: const Text('继续'))
                    : OutlinedButton.icon(onPressed: actions.pauseJob, icon: const Icon(Icons.pause), label: const Text('暂停')),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: actions.abortJob,
                  icon: const Icon(Icons.stop),
                  label: const Text('停止'),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _quickActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        sectionTitle('快捷操作'),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: 4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 0.92,
          children: [
            _qaTile(Icons.lightbulb, state.lightOn ? '舱灯 开' : '舱灯 关', state.lightOn ? Colors.amber : Colors.grey, actions.toggleLight),
            _qaTile(Icons.home, '回零', const Color(0xFF19B36B), () => actions.addLog('执行回零（回到机械原点）')),
            _qaTile(Icons.gps_fixed, '自动对刀', const Color(0xFF3B82F6), () => actions.addLog('开始 Z 轴自动对刀')),
            _qaTile(Icons.center_focus_weak, '红光定位', const Color(0xFF8B5CF6), () => actions.addLog('开启红光轮廓定位')),
          ],
        ),
      ],
    );
  }

  Widget _qaTile(IconData icon, String label, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 8, offset: Offset(0, 2))]),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _startWorkCard() {
    return InkWell(
      onTap: () => onNavigate(2),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF19B36B), Color(0xFF138A57)]), borderRadius: BorderRadius.all(Radius.circular(16))),
        child: const Row(
          children: [
            Icon(Icons.add_circle_outline, color: Colors.white),
            SizedBox(width: 10),
            Expanded(child: Text('选择作品开始加工', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15))),
            Icon(Icons.arrow_forward_ios, color: Colors.white70, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _activityCard() {
    final logs = state.activityLog.take(6).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        sectionTitle('设备动态'),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: cardDecoration(),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: logs.length,
            separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFEEF0F2)),
            itemBuilder: (_, i) => Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(logs[i], style: const TextStyle(fontSize: 12, color: Colors.black87))),
          ),
        ),
      ],
    );
  }
}

// ----------------------------- 控制台 -----------------------------
class ControlScreen extends StatefulWidget {
  final MachineState state;
  final MachineActions actions;
  const ControlScreen({Key? key, required this.state, required this.actions}) : super(key: key);
  @override
  State<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends State<ControlScreen> {
  double _step = 1.0;

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final a = widget.actions;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _axisCard(s, a),
          const SizedBox(height: 16),
          _jogCard(a),
          const SizedBox(height: 16),
          _commonOps(a),
          const SizedBox(height: 16),
          _toolCard(s, a),
          const SizedBox(height: 16),
          _auxCard(s, a),
          const SizedBox(height: 16),
          _overrideCard(s, a),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _axisCard(MachineState s, MachineActions a) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: cardDecoration(),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('当前坐标', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              TextButton(
                onPressed: () {
                  a.jog(-s.x, -s.y, -s.z);
                  a.addLog('已设置工作原点 (X/Y/Z = 0)');
                },
                child: const Text('设为原点', style: TextStyle(color: Color(0xFF19B36B))),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _axisItem('X', s.x, const Color(0xFFE5484D)),
              _axisItem('Y', s.y, const Color(0xFF19B36B)),
              _axisItem('Z', s.z, const Color(0xFF3B82F6)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _axisItem(String axis, double val, Color color) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(color: const Color(0xFFF4F6F8), borderRadius: BorderRadius.circular(10)),
        child: Column(
          children: [
            Text(axis, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(val.toStringAsFixed(3), style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace')),
          ],
        ),
      ),
    );
  }

  Widget _jogCard(MachineActions a) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: cardDecoration(),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('手动移动', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              Row(
                children: [0.1, 1.0, 10.0].map((st) {
                  final sel = _step == st;
                  return GestureDetector(
                    onTap: () => setState(() => _step = st),
                    child: Container(
                      margin: const EdgeInsets.only(left: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: sel ? const Color(0xFF19B36B) : const Color(0xFFF4F6F8), borderRadius: BorderRadius.circular(8)),
                      child: Text('${st}mm', style: TextStyle(color: sel ? Colors.white : Colors.black54, fontWeight: FontWeight.w600, fontSize: 12)),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _jogBtn('X-', () => a.jog(-_step, 0, 0)),
              const SizedBox(width: 14),
              Column(
                children: [
                  _jogBtn('Y+', () => a.jog(0, _step, 0)),
                  const SizedBox(height: 14),
                  _jogBtn('Y-', () => a.jog(0, -_step, 0)),
                ],
              ),
              const SizedBox(width: 14),
              _jogBtn('X+', () => a.jog(_step, 0, 0)),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _jogBtn('Z+', () => a.jog(0, 0, _step)),
              const SizedBox(width: 14),
              _jogBtn('Z-', () => a.jog(0, 0, -_step)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _jogBtn(String label, VoidCallback onTap) {
    return SizedBox(
      width: 64,
      height: 48,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF4F6F8), foregroundColor: Colors.black87, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _commonOps(MachineActions a) {
    final ops = [
      {'icon': Icons.gps_fixed, 'label': '自动对刀', 'color': const Color(0xFF3B82F6), 'msg': '开始 Z 轴自动对刀'},
      {'icon': Icons.home, 'label': '回零', 'color': const Color(0xFF19B36B), 'msg': '执行回零（回到机械原点）'},
      {'icon': Icons.center_focus_weak, 'label': '红光定位', 'color': const Color(0xFF8B5CF6), 'msg': '开启红光轮廓定位'},
      {'icon': Icons.flaky, 'label': '台面找平', 'color': const Color(0xFFF2A33C), 'msg': '开始工作台自动找平'},
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        sectionTitle('常用操作'),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 2.6,
          children: ops.map((o) {
            return InkWell(
              onTap: () => a.addLog(o['msg'] as String),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 8, offset: Offset(0, 2))]),
                child: Row(
                  children: [
                    Icon(o['icon'] as IconData, color: o['color'] as Color, size: 20),
                    const SizedBox(width: 10),
                    Text(o['label'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _toolCard(MachineState s, MachineActions a) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('刀具', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 10),
          Row(
            children: kTools.map((t) {
              final slot = int.parse(t['slot']!);
              final active = s.tool == slot;
              return Expanded(
                child: GestureDetector(
                  onTap: () => a.selectTool(slot),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                    decoration: BoxDecoration(
                      color: active ? const Color(0xFF19B36B).withOpacity(0.12) : const Color(0xFFF4F6F8),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: active ? const Color(0xFF19B36B) : Colors.transparent),
                    ),
                    child: Column(
                      children: [
                        Text('T$slot', style: TextStyle(color: active ? const Color(0xFF19B36B) : Colors.black87, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text(t['name']!, style: const TextStyle(fontSize: 10, color: Colors.black54), textAlign: TextAlign.center),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _auxCard(MachineState s, MachineActions a) {
    return Row(
      children: [
        Expanded(child: _auxTile(Icons.air, '切削吹气', s.airOn, () => a.toggleAir())),
        const SizedBox(width: 12),
        Expanded(child: _auxTile(Icons.cleaning_services, '吸尘', s.dustOn, () => a.toggleDust())),
      ],
    );
  }

  Widget _auxTile(IconData icon, String label, bool on, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: on ? const Color(0xFF19B36B).withOpacity(0.12) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: on ? const Color(0xFF19B36B) : const Color(0xFFEDEFF2)),
        ),
        child: Column(
          children: [
            Icon(icon, color: on ? const Color(0xFF19B36B) : Colors.black45),
            const SizedBox(height: 6),
            Text('$label · ${on ? '开' : '关'}', style: TextStyle(color: on ? const Color(0xFF19B36B) : Colors.black54, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _overrideCard(MachineState s, MachineActions a) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('进给 / 主轴倍率', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('进给', style: TextStyle(color: Colors.black54, fontSize: 12)),
              Expanded(child: Slider(value: s.feedOverride, min: 10, max: 200, divisions: 19, label: '${s.feedOverride.toInt()}%', onChanged: a.setFeed)),
              Text('${s.feedOverride.toInt()}%', style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
          Row(
            children: [
              const Text('主轴', style: TextStyle(color: Colors.black54, fontSize: 12)),
              Expanded(child: Slider(value: s.spindleOverride, min: 50, max: 150, divisions: 10, label: '${s.spindleOverride.toInt()}%', onChanged: a.setSpindle)),
              Text('${s.spindleOverride.toInt()}%', style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }
}

// ----------------------------- 作品库 -----------------------------
class ProjectsScreen extends StatelessWidget {
  final MachineState state;
  final MachineActions actions;
  final void Function(int) onNavigate;
  const ProjectsScreen({Key? key, required this.state, required this.actions, required this.onNavigate}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final s = state;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('作品库', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text('选择一件作品即可开始加工', style: TextStyle(color: Colors.black54, fontSize: 13)),
          const SizedBox(height: 14),
          if (s.jobRunning) _runningBanner(s),
          ...kProjects.map((p) => _projectCard(p, s)).toList(),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _runningBanner(MachineState s) {
    final remainSec = (s.jobDurationSec * (1 - s.jobProgress)).round();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xFF19B36B).withOpacity(0.1), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFF19B36B).withOpacity(0.4))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.precision_manufacturing, color: Color(0xFF19B36B)),
              const SizedBox(width: 8),
              Expanded(child: Text('正在加工：${s.jobName}', style: const TextStyle(fontWeight: FontWeight.bold))),
              Text('${(s.jobProgress * 100).toInt()}%', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF19B36B))),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: s.jobProgress, backgroundColor: const Color(0xFFEDEFF2), color: const Color(0xFF19B36B)),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('剩余 ${formatDuration(remainSec)}', style: const TextStyle(color: Colors.black54, fontSize: 11)),
              TextButton(onPressed: actions.abortJob, child: const Text('停止', style: TextStyle(color: Colors.red))),
            ],
          ),
          const SizedBox(height: 4),
          const Text('加工中，下方作品暂不可开始', style: TextStyle(color: Colors.black45, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _projectCard(Map<String, String> p, MachineState s) {
    final running = s.jobRunning;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: cardDecoration(),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: const Color(0xFF19B36B).withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.square_outlined, color: Color(0xFF19B36B)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p['name']!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 2),
                Text('尺寸 ${p['size']} · ${p['tools']}', style: const TextStyle(color: Colors.black54, fontSize: 12)),
              ],
            ),
          ),
          FilledButton(
            onPressed: running ? null : () => actions.startJob(p['name']!, int.parse(p['duration']!)),
            child: Text(running ? '加工中' : '开始加工'),
          ),
        ],
      ),
    );
  }
}

// ----------------------------- 我的 -----------------------------
class MoreScreen extends StatelessWidget {
  final MachineState state;
  final MachineActions actions;
  const MoreScreen({Key? key, required this.state, required this.actions}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _profile(),
          const SizedBox(height: 16),
          if (state.status == 'ALARM') _alarmBanner(),
          _connectionCard(),
          const SizedBox(height: 12),
          _settingsCard(),
          const SizedBox(height: 12),
          _advancedCard(),
          const SizedBox(height: 20),
          const Center(child: Text('Smart CNC 3020 · v1.0.0', style: TextStyle(color: Colors.black38, fontSize: 11))),
        ],
      ),
    );
  }

  Widget _profile() {
    return Row(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(color: const Color(0xFF19B36B).withOpacity(0.12), borderRadius: BorderRadius.circular(16)),
          child: const Icon(Icons.precision_manufacturing, color: Color(0xFF19B36B), size: 28),
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('我的 CNC', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              Text('包覆款桌面 CNC · 智能控制', style: TextStyle(color: Colors.black54, fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _alarmBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.red.shade200)),
      child: Row(
        children: [
          const Icon(Icons.warning_amber, color: Colors.red),
          const SizedBox(width: 10),
          const Expanded(child: Text('机器处于报警状态', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600))),
          TextButton(onPressed: actions.clearAlarm, child: const Text('解除报警')),
        ],
      ),
    );
  }

  Widget _connectionCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: cardDecoration(),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.wifi, color: Color(0xFF19B36B)),
        title: const Text('设备连接', style: TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(state.isLanMode ? '局域网已连接 · 低延迟' : '远程连接 · 45ms', style: const TextStyle(color: Colors.black54, fontSize: 12)),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.black38),
        onTap: actions.requestPairing,
      ),
    );
  }

  Widget _settingsCard() {
    final items = [
      {'icon': Icons.notifications_outlined, 'label': '通知设置'},
      {'icon': Icons.info_outline, 'label': '关于本机'},
      {'icon': Icons.help_outline, 'label': '帮助中心'},
    ];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: cardDecoration(),
      child: Column(
        children: items.map((it) {
          return ListTile(
            leading: Icon(it['icon'] as IconData, color: Colors.black54),
            title: Text(it['label'] as String, style: const TextStyle(fontWeight: FontWeight.w500)),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.black38),
            onTap: () {},
          );
        }).toList(),
      ),
    );
  }

  Widget _advancedCard() {
    return Container(
      decoration: cardDecoration(),
      child: ExpansionTile(
        leading: const Icon(Icons.terminal, color: Colors.black54),
        title: const Text('开发者选项 · 调试终端', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: const Text('高级用户查看原始指令', style: TextStyle(fontSize: 11, color: Colors.black45)),
        childrenPadding: const EdgeInsets.all(14),
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: const Color(0xFF1A1D1F), borderRadius: BorderRadius.circular(10)),
            child: const Text('\$100=250.000\n\$101=250.000\n\$102=400.000\nok', style: TextStyle(color: Color(0xFF19B36B), fontSize: 11, fontFamily: 'monospace')),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  style: const TextStyle(fontSize: 12),
                  decoration: const InputDecoration(
                    hintText: '输入 G 代码或 \$ 命令…',
                    filled: true,
                    fillColor: Color(0xFFF4F6F8),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    border: OutlineInputBorder(borderSide: BorderSide.none, borderRadius: BorderRadius.all(Radius.circular(10))),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: () {}, child: const Text('发送')),
            ],
          ),
        ],
      ),
    );
  }
}
