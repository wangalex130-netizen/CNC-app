import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SmartCncApp());
}

/// ============ 数据模型 ============
class MachineTelemetry {
  final String status; // Idle / Run / Hold / Alarm / Check / Door
  final double x, y, z;
  final int feed; // 当前进给 mm/min
  final int spindle; // 主轴转速 RPM
  final bool doorClosed;
  const MachineTelemetry({
    this.status = 'Disconnected',
    this.x = 0,
    this.y = 0,
    this.z = 0,
    this.feed = 0,
    this.spindle = 0,
    this.doorClosed = true,
  });
}

class GcodeJob {
  final String name;
  final String size;
  final String tools;
  final List<String> lines;
  const GcodeJob(this.name, this.size, this.tools, this.lines);
}

/// 预设作品（lines 是真实可发送的 G-code，演示用，可按需替换）
const List<GcodeJob> kPresetJobs = [
  GcodeJob('铝合金散热壳加工', '100 × 60 × 15 mm', '刀具: T1 (3.175mm)', [
    'G21', 'G90', 'M3 S12000',
    'G0 X0 Y0 Z5', 'G1 Z-1 F200',
    'G1 X20 Y0 F800', 'G1 X20 Y10', 'G1 X0 Y10', 'G1 X0 Y0',
    'G0 Z5', 'M5', 'G0 X0 Y0',
  ]),
  GcodeJob('木质榫卯手机支架', '150 × 80 × 12 mm', '刀具: T1, T2', [
    'G21', 'G90', 'M3 S8000',
    'G0 X0 Y0 Z5', 'G1 Z-2 F150',
    'G1 X30 Y0 F600', 'G1 X30 Y20', 'G1 X0 Y20', 'G1 X0 Y0',
    'G0 Z5', 'M5', 'G0 X0 Y0',
  ]),
  GcodeJob('PCB 雕刻电路板', '80 × 50 × 1.6 mm', '刀具: T2 (V型刀)', [
    'G21', 'G90', 'M3 S10000',
    'G0 X0 Y0 Z2', 'G1 Z-0.2 F100',
    'G1 X40 Y0 F500', 'G1 X40 Y25', 'G1 X0 Y25', 'G1 X0 Y0',
    'G0 Z2', 'M5', 'G0 X0 Y0',
  ]),
];

/// ============ GRBL over Wi-Fi (TCP) 通信层 ============
class CncClient {
  Socket? _socket;
  bool _connected = false;
  String _buffer = '';
  final _lines = StreamController<String>.broadcast();

  bool get connected => _connected;
  Stream<String> get lines => _lines.stream;

  Future<String> connect(String ip, int port) async {
    try {
      _socket = await Socket.connect(ip, port, timeout: const Duration(seconds: 5));
      _connected = true;
      _socket!.listen(
        (data) {
          _buffer += String.fromCharCodes(data);
          // 按 \n 或 \r 切分成行
          while (true) {
            final iN = _buffer.indexOf('\n');
            final iR = _buffer.indexOf('\r');
            if (iN == -1 && iR == -1) break;
            int cut;
            if (iN == -1) {
              cut = iR;
            } else if (iR == -1) {
              cut = iN;
            } else {
              cut = min(iN, iR);
            }
            final line = _buffer.substring(0, cut).trim();
            _buffer = _buffer.substring(cut + 1);
            if (line.isNotEmpty) _lines.add(line);
          }
        },
        onDone: () {
          _connected = false;
          _lines.add('__DISCONNECTED__');
        },
        onError: (e) {
          _connected = false;
          _lines.add('__ERROR__:$e');
        },
      );
      return 'ok';
    } catch (e) {
      return 'error:$e';
    }
  }

  void send(String cmd) {
    if (_socket == null || !_connected) return;
    _socket!.write('$cmd\n');
  }

  /// 发送软复位 (Ctrl-X, 0x18)，用于急停/终止
  void sendReset() {
    if (_socket == null || !_connected) return;
    _socket!.add([0x18]);
  }

  void disconnect() {
    _socket?.destroy();
    _socket = null;
    _connected = false;
  }
}

/// ============ 入口 ============
class SmartCncApp extends StatelessWidget {
  const SmartCncApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart CNC',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        primaryColor: const Color(0xFF19B36B),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF19B36B),
          primary: const Color(0xFF19B36B),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF5F6F8),
        cardColor: Colors.white,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF1A1A1A),
          elevation: 0,
          centerTitle: false,
        ),
      ),
      home: const MainScaffold(),
    );
  }
}

/// ============ 主框架：持有通信与全局状态 ============
class MainScaffold extends StatefulWidget {
  const MainScaffold({super.key});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  int _tab = 0;
  final _client = CncClient();

  // 连接
  bool _connected = false;
  String _connMsg = '未连接';
  final _ipCtl = TextEditingController(text: '192.168.1.100');
  final _portCtl = TextEditingController(text: '23');

  // 机器实时数据
  MachineTelemetry _tele = const MachineTelemetry();

  // 辅助开关（UI 反馈用，灯为本地；气/尘映射到 M 指令）
  bool _lightOn = true;
  bool _airOn = false;
  bool _dustOn = false;

  // 加工任务
  bool _jobExecuting = false;
  bool _jobPaused = false;
  bool _jobAllSent = false;
  double _jobProgress = 0;
  int _jobIndex = 0;
  List<String> _jobLines = [];
  GcodeJob? _activeJob;

  // 日志
  final List<String> _events = [];
  final List<String> _devLog = [];

  @override
  void initState() {
    super.initState();
    _client.lines.listen(_onLine);
    _loadSaved();
    // 状态轮询：每 300ms 问机器要一次状态
    Timer.periodic(const Duration(milliseconds: 300), (_) {
      if (_client.connected) _client.send('?');
    });
  }

  Future<void> _loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    final ip = prefs.getString('cnc_ip');
    final port = prefs.getString('cnc_port');
    if (ip != null) _ipCtl.text = ip;
    if (port != null) _portCtl.text = port;
  }

  Future<void> _saveConn() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cnc_ip', _ipCtl.text.trim());
    await prefs.setString('cnc_port', _portCtl.text.trim());
  }

  void _onLine(String line) {
    // 连接事件
    if (line == '__DISCONNECTED__') {
      setState(() => _connected = false);
      _addEvent('⚠️ 与机器断开连接');
      return;
    }
    if (line.startsWith('__ERROR__')) {
      setState(() => _connMsg = line);
      return;
    }
    // 状态回报 <...>
    if (line.startsWith('<') && line.endsWith('>')) {
      _parseStatus(line);
      return;
    }
    // 指令回执 ok / error
    if (line.startsWith('ok') || line.startsWith('error')) {
      _onAck(line);
      if (line.startsWith('error')) _addEvent('⚠️ 指令错误: $line');
    }
    // 开发日志
    if (_devLog.length > 200) _devLog.removeAt(0);
    _devLog.add(line);
  }

  void _parseStatus(String s) {
    final inner = s.substring(1, s.length - 1);
    final parts = inner.split('|');
    String st = parts.isNotEmpty ? parts[0] : 'Idle';
    double x = _tele.x, y = _tele.y, z = _tele.z;
    int feed = 0, spindle = 0;
    for (final p in parts) {
      if (p.startsWith('MPos:') || p.startsWith('WPos:')) {
        final c = p.split(':')[1].split(',');
        if (c.length >= 3) {
          x = double.tryParse(c[0]) ?? x;
          y = double.tryParse(c[1]) ?? y;
          z = double.tryParse(c[2]) ?? z;
        }
      } else if (p.startsWith('FS:')) {
        final f = p.split(':')[1].split(',');
        feed = int.tryParse(f[0]) ?? 0;
        spindle = int.tryParse(f[1]) ?? 0;
      }
    }
    // 加工完成判定：全部发完且机器回到空闲
    bool justDone = false;
    if (_jobExecuting && _jobAllSent && !_jobPaused) {
      if (st == 'Idle' || st.startsWith('Idle')) {
        justDone = true;
      }
    }
    setState(() {
      _tele = MachineTelemetry(
        status: st, x: x, y: y, z: z, feed: feed, spindle: spindle, doorClosed: _tele.doorClosed,
      );
      if (justDone) {
        _jobExecuting = false;
        _jobProgress = 1.0;
      }
    });
    if (justDone) {
      _addEvent('✅ 加工完成：${_activeJob?.name ?? ''}');
      _showSnack('加工完成 ✅');
    }
  }

  void _onAck(String line) {
    if (!_jobExecuting || _jobPaused) return;
    if (_jobIndex < _jobLines.length - 1) {
      _jobIndex++;
      _client.send(_jobLines[_jobIndex]);
    } else {
      _jobAllSent = true;
    }
    setState(() => _jobProgress = (_jobIndex + 1) / max(1, _jobLines.length));
  }

  void _addEvent(String e) {
    setState(() {
      _events.insert(0, e);
      if (_events.length > 30) _events.removeLast();
    });
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  Future<void> _connect() async {
    final ip = _ipCtl.text.trim();
    final port = int.tryParse(_portCtl.text.trim()) ?? 23;
    setState(() => _connMsg = '连接中...');
    final res = await _client.connect(ip, port);
    if (res == 'ok') {
      setState(() => _connected = true);
      _connMsg = '已连接';
      _saveConn();
      _client.send('?');
      _addEvent('🔗 已连接机器 $ip:$port');
      _showSnack('连接成功');
    } else {
      setState(() => _connMsg = '连接失败');
      _showSnack('连接失败，请检查 IP / 端口 / 机器是否开机');
    }
  }

  void _disconnect() {
    _client.disconnect();
    setState(() => _connected = false);
    _addEvent('已断开连接');
  }

  /// ---- 真实控制指令 ----
  void _startJob(GcodeJob job) {
    if (!_connected) {
      _showSnack('请先连接机器');
      return;
    }
    setState(() {
      _activeJob = job;
      _jobLines = List.from(job.lines);
      _jobIndex = 0;
      _jobExecuting = true;
      _jobPaused = false;
      _jobAllSent = false;
      _jobProgress = 0;
    });
    _addEvent('▶️ 开始加工：${job.name}');
    _client.send(_jobLines[0]);
  }

  void _pauseJob() {
    if (!_jobExecuting) return;
    _client.send('!'); // 进给保持
    setState(() => _jobPaused = true);
    _addEvent('⏸ 已暂停');
  }

  void _resumeJob() {
    if (!_jobExecuting) return;
    _client.send('~'); // 继续
    setState(() => _jobPaused = false);
    _client.send(_jobLines[_jobIndex]); // 补发当前行
    _addEvent('▶️ 继续加工');
  }

  void _stopJob() {
    _client.sendReset(); // 软复位
    _client.send('\$X'); // 解锁
    setState(() {
      _jobExecuting = false;
      _jobPaused = false;
      _jobAllSent = false;
      _jobProgress = 0;
    });
    _addEvent('⏹ 已终止加工');
  }

  void _eStop() {
    _client.sendReset();
    setState(() => _jobExecuting = false);
    _addEvent('🚨 急停！已下发软复位');
    _showSnack('急停已触发');
  }

  void _jog(String axis, double dir, double step) {
    if (!_connected) return;
    // $J=G91 G1 X+step F1000  (相对点动)
    _client.send('\$J=G91 G1 $axis${dir * step} F1000');
  }

  void _home() {
    if (!_connected) return;
    _client.send('\$H');
    _addEvent('🏠 执行回零 (\$H)');
  }

  void _unlock() {
    if (!_connected) return;
    _client.send('\$X');
    _addEvent('🔓 解锁报警 (\$X)');
  }

  void _probeZ() {
    if (!_connected) return;
    _client.send('G38.2 Z-20 F50');
    _addEvent('🎯 自动 Z 轴对刀');
  }

  void _redDot() {
    if (!_connected) return;
    _client.send('M3 S0'); // 红光预览（视固件而定）
    _addEvent('🔦 红光预览');
  }

  void _toOrigin() {
    if (!_connected) return;
    _client.send('G0 X0 Y0');
    _addEvent('📍 移动到原点');
  }

  void _spindle(bool on) {
    if (!_connected) return;
    _client.send(on ? 'M3 S12000' : 'M5');
  }

  void _air(bool on) {
    if (!_connected) return;
    _client.send(on ? 'M8' : 'M9');
    setState(() => _airOn = on);
  }

  void _dust(bool on) {
    if (!_connected) return;
    _client.send(on ? 'M7' : 'M9');
    setState(() => _dustOn = on);
  }

  void _openConnectSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ConnectSheet(
        ipCtl: _ipCtl,
        portCtl: _portCtl,
        connected: _connected,
        connMsg: _connMsg,
        onConnect: _connect,
        onDisconnect: _disconnect,
      ),
    );
  }

  void _showEStopDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('🚨 确认急停？'),
        content: const Text('将立即向机器下发软复位指令，所有轴停止运动。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(ctx);
              _eStop();
            },
            child: const Text('确认急停', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      body: IndexedStack(
        index: _tab,
        children: [
          HomeScreen(
            connected: _connected,
            tele: _tele,
            jobExecuting: _jobExecuting,
            jobPaused: _jobPaused,
            jobProgress: _jobProgress,
            activeJob: _activeJob,
            events: _events,
            lightOn: _lightOn,
            onToggleLight: () => setState(() => _lightOn = !_lightOn),
            onConnect: _openConnectSheet,
            onHome: _home,
            onProbeZ: _probeZ,
            onRedDot: _redDot,
            onStartJob: _startJob,
            onPauseJob: _pauseJob,
            onResumeJob: _resumeJob,
            onStopJob: _stopJob,
          ),
          ControlScreen(
            connected: _connected,
            tele: _tele,
            lightOn: _lightOn,
            airOn: _airOn,
            dustOn: _dustOn,
            onToggleLight: () => setState(() => _lightOn = !_lightOn),
            onMove: _jog,
            onHome: _home,
            onUnlock: _unlock,
            onProbeZ: _probeZ,
            onRedDot: _redDot,
            onToOrigin: _toOrigin,
            onAir: _air,
            onDust: _dust,
          ),
          ProjectsScreen(
            connected: _connected,
            jobExecuting: _jobExecuting,
            jobPaused: _jobPaused,
            jobProgress: _jobProgress,
            activeJob: _activeJob,
            onStartJob: _startJob,
            onPauseJob: _pauseJob,
            onResumeJob: _resumeJob,
            onStopJob: _stopJob,
          ),
          MoreScreen(
            connected: _connected,
            tele: _tele,
            ip: _ipCtl.text,
            port: _portCtl.text,
            devLog: _devLog,
            onConnect: _openConnectSheet,
            onDisconnect: _disconnect,
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tab,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFF19B36B),
        unselectedItemColor: Colors.grey,
        onTap: (i) => setState(() => _tab = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined), activeIcon: Icon(Icons.home), label: '首页'),
          BottomNavigationBarItem(icon: Icon(Icons.gamepad_outlined), activeIcon: Icon(Icons.gamepad), label: '控制台'),
          BottomNavigationBarItem(icon: Icon(Icons.folder_outlined), activeIcon: Icon(Icons.folder), label: '作品'),
          BottomNavigationBarItem(icon: Icon(Icons.person_outline), activeIcon: Icon(Icons.person), label: '我的'),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    final color = _connected ? const Color(0xFF19B36B) : Colors.grey;
    return AppBar(
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text('SMART CNC 3020', style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: _openConnectSheet,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _connected ? Colors.green.withOpacity(0.12) : Colors.orange.withOpacity(0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  Icon(_connected ? Icons.wifi : Icons.wifi_off, size: 13, color: _connected ? Colors.green : Colors.orange),
                  const SizedBox(width: 4),
                  Text(_connected ? '已连接' : '未连接', style: TextStyle(fontSize: 11, color: _connected ? Colors.green : Colors.orange, fontWeight: FontWeight.bold)),
                  const Icon(Icons.arrow_drop_down, size: 14, color: Colors.grey),
                ],
              ),
            ),
          ),
        ],
      ),
      actions: [
        ElevatedButton.icon(
          onPressed: _showEStopDialog,
          icon: const Icon(Icons.dangerous, color: Colors.white, size: 16),
          label: const Text('急停', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
        ),
        const SizedBox(width: 10),
      ],
    );
  }
}

/// ============ 配网/连接弹窗（Wi-Fi） ============
class ConnectSheet extends StatelessWidget {
  final TextEditingController ipCtl;
  final TextEditingController portCtl;
  final bool connected;
  final String connMsg;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;

  const ConnectSheet({
    super.key,
    required this.ipCtl,
    required this.portCtl,
    required this.connected,
    required this.connMsg,
    required this.onConnect,
    required this.onDisconnect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('连接我的 CNC', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
            ],
          ),
          const Divider(),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: connected ? Colors.green.shade50 : Colors.orange.shade50, borderRadius: BorderRadius.circular(8)),
            child: Row(
              children: [
                Icon(connected ? Icons.check_circle : Icons.info, color: connected ? Colors.green : Colors.orange),
                const SizedBox(width: 8),
                Expanded(child: Text(connMsg, style: TextStyle(color: connected ? Colors.green.shade800 : Colors.orange.shade800, fontSize: 12))),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const Text('机器 IP 地址', style: TextStyle(fontSize: 12, color: Colors.grey)),
          TextField(
            controller: ipCtl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(hintText: '例如 192.168.1.100', filled: true, fillColor: Color(0xFFF5F6F8), border: OutlineInputBorder(borderSide: BorderSide.none, borderRadius: BorderRadius.all(Radius.circular(8)))),
          ),
          const SizedBox(height: 10),
          const Text('端口', style: TextStyle(fontSize: 12, color: Colors.grey)),
          TextField(
            controller: portCtl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(hintText: '默认 23', filled: true, fillColor: Color(0xFFF5F6F8), border: OutlineInputBorder(borderSide: BorderSide.none, borderRadius: BorderRadius.all(Radius.circular(8)))),
          ),
          const SizedBox(height: 8),
          const Text('提示：在机器控制屏或路由器后台找到机器 IP。ESP8266 默认端口多为 23。', style: TextStyle(fontSize: 11, color: Colors.grey)),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton(
              onPressed: connected ? onDisconnect : onConnect,
              style: ElevatedButton.styleFrom(
                backgroundColor: connected ? Colors.grey : const Color(0xFF19B36B),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text(connected ? '断开连接' : '连接', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }
}

/// ============ 工具：状态卡颜色 ============
Color _statusColor(String s) {
  if (s.startsWith('Run')) return Colors.green;
  if (s.startsWith('Hold')) return Colors.orange;
  if (s.startsWith('Alarm')) return Colors.red;
  if (s.startsWith('Idle')) return const Color(0xFF19B36B);
  return Colors.grey;
}

String _statusText(String s) {
  if (s.startsWith('Run')) return '工作中';
  if (s.startsWith('Hold')) return '已暂停';
  if (s.startsWith('Alarm')) return '报警';
  if (s.startsWith('Idle')) return '空闲';
  if (s.startsWith('Check')) return '校验中';
  if (s.startsWith('Door')) return '门保护';
  return s;
}

Widget _axisChip(String axis, double v, Color c) {
  return Expanded(
    child: Container(
      margin: const EdgeInsets.symmetric(horizontal: 3),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(color: const Color(0xFFF5F6F8), borderRadius: BorderRadius.circular(8)),
      child: Column(
        children: [
          Text(axis, style: TextStyle(color: c, fontWeight: FontWeight.bold, fontSize: 12)),
          Text(v.toStringAsFixed(2), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        ],
      ),
    ),
  );
}

/// ============ 首页 ============
class HomeScreen extends StatelessWidget {
  final bool connected;
  final MachineTelemetry tele;
  final bool jobExecuting, jobPaused;
  final double jobProgress;
  final GcodeJob? activeJob;
  final List<String> events;
  final bool lightOn;
  final VoidCallback onToggleLight, onConnect, onHome, onProbeZ, onRedDot;
  final Function(GcodeJob) onStartJob;
  final VoidCallback onPauseJob, onResumeJob, onStopJob;

  const HomeScreen({
    super.key,
    required this.connected,
    required this.tele,
    required this.jobExecuting,
    required this.jobPaused,
    required this.jobProgress,
    required this.activeJob,
    required this.events,
    required this.lightOn,
    required this.onToggleLight,
    required this.onConnect,
    required this.onHome,
    required this.onProbeZ,
    required this.onRedDot,
    required this.onStartJob,
    required this.onPauseJob,
    required this.onResumeJob,
    required this.onStopJob,
  });

  @override
  Widget build(BuildContext context) {
    if (!connected) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.wifi_off, size: 56, color: Colors.grey),
              const SizedBox(height: 16),
              const Text('还没连接机器', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              const Text('先连接你的 CNC，才能开始控制和加工', style: TextStyle(color: Colors.grey, fontSize: 13)),
              const SizedBox(height: 18),
              ElevatedButton.icon(
                onPressed: onConnect,
                icon: const Icon(Icons.wifi),
                label: const Text('连接我的 CNC'),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF19B36B), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
              ),
            ],
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        // 状态卡
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: _statusColor(tele.status), borderRadius: BorderRadius.circular(14)),
          child: Row(
            children: [
              Container(
                width: 10, height: 10,
                decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
              ),
              const SizedBox(width: 8),
              Text(_statusText(tele.status), style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
              const Spacer(),
              Text('主轴 ${tele.spindle} RPM', style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // 实时画面
        AspectRatio(
          aspectRatio: 16 / 9,
          child: Container(
            decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(12)),
            child: Stack(
              children: [
                const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.videocam_outlined, size: 40, color: Colors.cyanAccent),
                  SizedBox(height: 6),
                  Text('实时画面 (LIVE)', style: TextStyle(color: Colors.white54, fontSize: 12)),
                ])),
                Positioned(top: 10, left: 10, child: Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(4)), child: const Text('● LIVE', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)))),
                Positioned(bottom: 10, right: 10, child: ElevatedButton.icon(onPressed: onToggleLight, icon: Icon(Icons.lightbulb, size: 14, color: lightOn ? Colors.yellow : Colors.white60), label: Text(lightOn ? '舱灯开' : '舱灯关', style: const TextStyle(fontSize: 10)), style: ElevatedButton.styleFrom(backgroundColor: Colors.black87))),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        // 坐标
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)]),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('当前坐标', style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 8),
              Row(children: [_axisChip('X', tele.x, Colors.red), _axisChip('Y', tele.y, Colors.green), _axisChip('Z', tele.z, Colors.blue)]),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // 加工进度
        if (jobExecuting)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF19B36B))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('正在加工：${activeJob?.name ?? ''}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  Text('${(jobProgress * 100).toInt()}%', style: const TextStyle(color: Color(0xFF19B36B), fontWeight: FontWeight.bold, fontSize: 16)),
                ]),
                const SizedBox(height: 8),
                LinearProgressIndicator(value: jobProgress, backgroundColor: Colors.grey.shade200, color: const Color(0xFF19B36B)),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: OutlinedButton(onPressed: jobPaused ? onResumeJob : onPauseJob, child: Text(jobPaused ? '继续' : '暂停'))),
                  const SizedBox(width: 10),
                  Expanded(child: ElevatedButton(onPressed: onStopJob, style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: const Text('终止'))),
                ]),
              ],
            ),
          ),
        if (jobExecuting) const SizedBox(height: 12),
        // 快捷操作
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)]),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('快捷操作', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Row(children: [
                _quickBtn(Icons.home, '回零', onHome),
                _quickBtn(Icons.gps_fixed, '自动对刀', onProbeZ),
                _quickBtn(Icons.bolt, '红光预览', onRedDot),
                _quickBtn(Icons.folder_open, '打开作品', () {}),
              ]),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // 设备动态
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)]),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('设备动态', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ...events.take(8).map((e) => Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Text('• $e', style: const TextStyle(fontSize: 12, color: Colors.grey)))),
              if (events.isEmpty) const Text('暂无动态', style: TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _quickBtn(IconData icon, String label, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(children: [
          Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: const Color(0xFF19B36B).withOpacity(0.1), borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: const Color(0xFF19B36B))),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 11)),
        ]),
      ),
    );
  }
}

/// ============ 控制台 ============
class ControlScreen extends StatelessWidget {
  final bool connected;
  final MachineTelemetry tele;
  final bool lightOn, airOn, dustOn;
  final VoidCallback onToggleLight, onHome, onUnlock, onProbeZ, onRedDot, onToOrigin, onAir, onDust;
  final Function(String, double, double) onMove;

  const ControlScreen({
    super.key,
    required this.connected,
    required this.tele,
    required this.lightOn,
    required this.airOn,
    required this.dustOn,
    required this.onToggleLight,
    required this.onHome,
    required this.onUnlock,
    required this.onProbeZ,
    required this.onRedDot,
    required this.onToOrigin,
    required this.onAir,
    required this.onDust,
    required this.onMove,
  });

  @override
  Widget build(BuildContext context) {
    double step = 1.0;
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        if (!connected)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(10)),
            child: const Text('未连接机器，以下操作不会生效。请先到「我的」连接。', style: TextStyle(color: Colors.orange, fontSize: 12)),
          ),
        if (!connected) const SizedBox(height: 12),
        // 坐标
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)]),
          child: Row(children: [_axisChip('X', tele.x, Colors.red), _axisChip('Y', tele.y, Colors.green), _axisChip('Z', tele.z, Colors.blue)]),
        ),
        const SizedBox(height: 12),
        // 手动移动
        StatefulBuilder(
          builder: (ctx, setState) => Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)]),
            child: Column(
              children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('手动移动', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  Row(children: [0.1, 1.0, 10.0].map((s) {
                    final sel = step == s;
                    return GestureDetector(
                      onTap: () => setState(() => step = s),
                      child: Container(
                        margin: const EdgeInsets.only(left: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: sel ? const Color(0xFF19B36B) : Colors.grey.shade200, borderRadius: BorderRadius.circular(6)),
                        child: Text('$s mm', style: TextStyle(color: sel ? Colors.white : Colors.grey, fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                    );
                  }).toList()),
                ]),
                const SizedBox(height: 14),
                Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                  SizedBox(width: 150, height: 150, child: Stack(alignment: Alignment.center, children: [
                    Positioned(top: 0, child: _moveBtn('Y+', () => onMove('Y', 1, step))),
                    Positioned(bottom: 0, child: _moveBtn('Y-', () => onMove('Y', -1, step))),
                    Positioned(left: 0, child: _moveBtn('X-', () => onMove('X', -1, step))),
                    Positioned(right: 0, child: _moveBtn('X+', () => onMove('X', 1, step))),
                  ])),
                  Column(children: [
                    _moveBtn('Z+', () => onMove('Z', 1, step)),
                    const SizedBox(height: 10),
                    _moveBtn('Z-', () => onMove('Z', -1, step)),
                  ]),
                ]),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        // 常用操作
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)]),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('常用操作', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              _opBtn(Icons.home, '回零', onHome),
              _opBtn(Icons.gps_fixed, '自动对刀', onProbeZ),
              _opBtn(Icons.bolt, '红光预览', onRedDot),
              _opBtn(Icons.my_location, '移动到原点', onToOrigin),
              _opBtn(Icons.lock_open, '解锁报警', onUnlock),
            ]),
          ]),
        ),
        const SizedBox(height: 12),
        // 辅助
        Row(children: [
          Expanded(child: _auxBtn(Icons.lightbulb, '舱灯', lightOn, onToggleLight)),
          const SizedBox(width: 8),
          Expanded(child: _auxBtn(Icons.air, '切削吹气', airOn, onAir)),
          const SizedBox(width: 8),
          Expanded(child: _auxBtn(Icons.cleaning_services, '吸尘', dustOn, onDust)),
        ]),
      ],
    );
  }

  Widget _moveBtn(String label, VoidCallback onTap) {
    return SizedBox(
      width: 46, height: 46,
      child: ElevatedButton(
        onPressed: connected ? onTap : null,
        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF19B36B), padding: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
        child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
      ),
    );
  }

  Widget _opBtn(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: connected ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: const Color(0xFF19B36B).withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 16, color: const Color(0xFF19B36B)), const SizedBox(width: 6), Text(label, style: const TextStyle(color: Color(0xFF19B36B), fontSize: 12, fontWeight: FontWeight.bold))]),
      ),
    );
  }

  Widget _auxBtn(IconData icon, String label, bool on, VoidCallback onTap) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(color: on ? const Color(0xFF19B36B).withOpacity(0.12) : Colors.grey.shade100, borderRadius: BorderRadius.circular(10)),
      child: Column(children: [
        Icon(icon, color: on ? const Color(0xFF19B36B) : Colors.grey),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 11, color: on ? const Color(0xFF19B36B) : Colors.grey)),
      ]),
    );
  }
}

/// ============ 作品库 ============
class ProjectsScreen extends StatelessWidget {
  final bool connected;
  final bool jobExecuting, jobPaused;
  final double jobProgress;
  final GcodeJob? activeJob;
  final Function(GcodeJob) onStartJob;
  final VoidCallback onPauseJob, onResumeJob, onStopJob;

  const ProjectsScreen({
    super.key,
    required this.connected,
    required this.jobExecuting,
    required this.jobPaused,
    required this.jobProgress,
    required this.activeJob,
    required this.onStartJob,
    required this.onPauseJob,
    required this.onResumeJob,
    required this.onStopJob,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        if (jobExecuting)
          Container(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF19B36B))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('正在加工：${activeJob?.name ?? ''}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                Text('${(jobProgress * 100).toInt()}%', style: const TextStyle(color: Color(0xFF19B36B), fontWeight: FontWeight.bold, fontSize: 16)),
              ]),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: jobProgress, backgroundColor: Colors.grey.shade200, color: const Color(0xFF19B36B)),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: OutlinedButton(onPressed: jobPaused ? onResumeJob : onPauseJob, child: Text(jobPaused ? '继续' : '暂停'))),
                const SizedBox(width: 10),
                Expanded(child: ElevatedButton(onPressed: onStopJob, style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: const Text('终止'))),
              ]),
            ]),
          ),
        const Text('我的作品', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        ...kPresetJobs.map((job) => _jobCard(job)),
      ],
    );
  }

  Widget _jobCard(GcodeJob job) {
    final active = activeJob == job && jobExecuting;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)]),
      child: Row(children: [
        const Icon(Icons.description_outlined, color: Color(0xFF19B36B), size: 30),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(job.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          Text('尺寸: ${job.size} | ${job.tools}', style: const TextStyle(color: Colors.grey, fontSize: 11)),
        ])),
        ElevatedButton(
          onPressed: connected && !jobExecuting ? () => onStartJob(job) : null,
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF19B36B), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8)),
          child: Text(active ? '加工中' : '开始加工', style: const TextStyle(fontSize: 12)),
        ),
      ]),
    );
  }
}

/// ============ 我的 ============
class MoreScreen extends StatelessWidget {
  final bool connected;
  final MachineTelemetry tele;
  final String ip, port;
  final List<String> devLog;
  final VoidCallback onConnect, onDisconnect;

  const MoreScreen({
    super.key,
    required this.connected,
    required this.tele,
    required this.ip,
    required this.port,
    required this.devLog,
    required this.onConnect,
    required this.onDisconnect,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)]),
          child: Row(children: [
            const CircleAvatar(radius: 26, backgroundColor: Color(0xFF19B36B), child: Icon(Icons.precision_manufacturing, color: Colors.white)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('SMART CNC 3020', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              Text(connected ? '已连接：$ip:$port' : '未连接', style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ])),
            ElevatedButton(
              onPressed: connected ? onDisconnect : onConnect,
              style: ElevatedButton.styleFrom(backgroundColor: connected ? Colors.grey : const Color(0xFF19B36B), foregroundColor: Colors.white),
              child: Text(connected ? '断开' : '连接'),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        _row(Icons.wifi, '连接设置', connected ? '已连接' : '未连接', onConnect),
        _row(Icons.info_outline, '固件状态', _statusText(tele.status), null),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)]),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('开发者选项 · 实时指令日志', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Container(
              height: 180,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(8)),
              child: ListView(
                children: devLog.reversed.take(50).map((l) => Text(l, style: const TextStyle(color: Colors.greenAccent, fontSize: 10, fontFamily: 'monospace'))).toList(),
              ),
            ),
            const SizedBox(height: 6),
            const Text('这里显示机器回传的真实 GRBL 指令，用于调试。普通用户可忽略。', style: TextStyle(fontSize: 11, color: Colors.grey)),
          ]),
        ),
        const SizedBox(height: 12),
        const Text('Smart CNC v1.0 · 包覆款桌面 CNC 控制', style: TextStyle(fontSize: 11, color: Colors.grey), textAlign: TextAlign.center),
      ],
    );
  }

  Widget _row(IconData icon, String title, String sub, VoidCallback? onTap) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)]),
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF19B36B)),
        title: Text(title, style: const TextStyle(fontSize: 13)),
        subtitle: Text(sub, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        trailing: onTap != null ? const Icon(Icons.chevron_right, color: Colors.grey) : null,
        onTap: onTap,
      ),
    );
  }
}
