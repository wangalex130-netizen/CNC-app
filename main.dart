import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:vector_math/vector_math.dart' as vm;

// ─────────────────────────────────────────────────────────────
//   Smart CNC · 手机端 App（仅控制 + 监控）
//
//  设计原则：
//   · 手机【不】生成刀路 / G-code。所有模型由“电脑端软件”生成并发布到模型库。
//   · 手机只做三件事：浏览并选择模型 → 准备（确定原点 / 自动找平 / 激光预览 / 刀路预览）
//     → 确认雕刻（之后仅监控进度与实时画面）。
//   · 通信全部走 HTTP 到电脑端软件：
//       GET  /state       取机器遥测（坐标/状态/进度/门/报警）
//       POST /cmd         发指令（select/set_origin/preview/start/auto_level 或 GRBL 行）
//       GET  /gcode/list  模型库（区分 public 公用 / account 我的）
//       GET  /gcode/get   取某个模型的 G-code 文本（用于手机画刀路预览）
//       GET  /snapshot    单张机床实时画面 JPEG
// ─────────────────────────────────────────────────────────────

void main() => runApp(const SmartCncApp());

final AppState appState = AppState();

// ── 模型库条目 ───────────────────────────────────────────────
class ModelItem {
  final String name;
  final String title;
  final bool public;
  final String desc;
  final String size;
  final String tool;
  final int lines;
  final List<List<double>> outline; // 2D 轮廓（mm，居中于原点），用于 3D 拉伸
  final double height;              // 材料厚度 / 雕刻高度（mm）
  final Map<String, double> minMaterial; // 最小耗材尺寸 {w,d,h} mm
  final List<String> materials;      // 后台设定的建议材料
  final String toolId;              // 建议刀具（对应刀仓 T1..T4）
  const ModelItem({
    required this.name,
    required this.title,
    required this.public,
    required this.desc,
    required this.size,
    required this.tool,
    required this.lines,
    this.outline = const [],
    this.height = 0,
    this.minMaterial = const {},
    this.materials = const [],
    this.toolId = '',
  });
  factory ModelItem.fromJson(Map<String, dynamic> j) {
    final ol = <List<double>>[];
    if (j['outline'] is List) {
      for (final p in j['outline']) {
        if (p is List && p.length >= 2) {
          ol.add([(p[0] ?? 0).toDouble(), (p[1] ?? 0).toDouble()]);
        }
      }
    }
    final mm = <String, double>{};
    if (j['min_material'] is Map) {
      final m = j['min_material'] as Map;
      mm['w'] = (m['w'] ?? 0).toDouble();
      mm['d'] = (m['d'] ?? 0).toDouble();
      mm['h'] = (m['h'] ?? 0).toDouble();
    }
    final mats = <String>[];
    if (j['materials'] is List) {
      for (final x in j['materials']) mats.add(x.toString());
    }
    return ModelItem(
      name: j['name'] ?? '',
      title: j['title'] ?? j['name'] ?? '',
      public: j['public'] ?? true,
      desc: j['desc'] ?? '',
      size: j['size'] ?? '',
      tool: j['tool'] ?? '',
      lines: j['lines'] ?? 0,
      outline: ol,
      height: (j['height'] ?? 0).toDouble(),
      minMaterial: mm,
      materials: mats,
      toolId: j['tool_id'] ?? '',
    );
  }
}

// ── 刀仓刀位 ─────────────────────────────────────────────────
class ToolSlot {
  final String id;
  final String name;
  final double diameter;
  final String type;
  final bool installed; // 人工是否装入
  final bool sensor;    // 刀仓传感器是否检测到（与 installed 同步）
  const ToolSlot({
    required this.id,
    required this.name,
    required this.diameter,
    required this.type,
    required this.installed,
    required this.sensor,
  });
  factory ToolSlot.fromJson(Map<String, dynamic> j) => ToolSlot(
        id: j['id'] ?? '',
        name: j['name'] ?? '',
        diameter: (j['diameter'] ?? 0).toDouble(),
        type: j['type'] ?? '',
        installed: j['installed'] ?? false,
        sensor: j['sensor'] ?? false,
      );
}

// ── 机器遥测（来自 /state）────────────────────────────────────
class Telemetry {
  final String status;
  final bool doorOpen;
  final String alarmCode;
  final String alarmMsg;
  final List<double> mpos;
  final List<double> wpos;
  final bool originSet;
  final int feed;
  final int spindle;
  final bool spindleOn;
  final bool previewMode;
  final bool laserOn;
  final bool leveling;
  final bool leveled;
  final double levelProgress;
  final bool jobRunning;
  final double progress;
  final String jobName;
  final List<ToolSlot> tools;
  const Telemetry({
    this.status = 'Idle',
    this.doorOpen = false,
    this.alarmCode = '',
    this.alarmMsg = '',
    this.mpos = const [0, 0, 0],
    this.wpos = const [0, 0, 0],
    this.originSet = false,
    this.feed = 0,
    this.spindle = 0,
    this.spindleOn = false,
    this.previewMode = false,
    this.laserOn = false,
    this.leveling = false,
    this.leveled = false,
    this.levelProgress = 0,
    this.jobRunning = false,
    this.progress = 0,
    this.jobName = '',
    this.tools = const [],
  });
  factory Telemetry.fromJson(Map<String, dynamic> j) {
    final tl = <ToolSlot>[];
    if (j['tools'] is List) {
      for (final s in j['tools']) tl.add(ToolSlot.fromJson(s));
    }
    return Telemetry(
      status: j['status'] ?? 'Idle',
      doorOpen: j['door_open'] ?? false,
      alarmCode: j['alarm_code'] ?? '',
      alarmMsg: j['alarm_msg'] ?? '',
      mpos: _toDoubles(j['mpos']),
      wpos: _toDoubles(j['wpos']),
      originSet: j['origin_set'] ?? false,
      feed: j['feed'] ?? 0,
      spindle: j['spindle'] ?? 0,
      spindleOn: j['spindle_on'] ?? false,
      previewMode: j['preview_mode'] ?? false,
      laserOn: j['laser_on'] ?? false,
      leveling: j['leveling'] ?? false,
      leveled: j['leveled'] ?? false,
      levelProgress: (j['level_progress'] ?? 0).toDouble(),
      jobRunning: j['job_running'] ?? false,
      progress: (j['progress'] ?? 0).toDouble(),
      jobName: j['job_name'] ?? '',
      tools: tl,
    );
  }
  static List<double> _toDoubles(dynamic v) {
    if (v is List) {
      return v.map<double>((e) => (e ?? 0).toDouble()).toList();
    }
    return const [0, 0, 0];
  }
}

// ── 全局状态 ─────────────────────────────────────────────────
class AppState extends ChangeNotifier {
  String ip = '192.168.1.100';
  int port = 5000; // 电脑端软件 HTTP 端口
  String videoUrl = '';
  bool connected = false;
  Telemetry telem = const Telemetry();
  List<ModelItem> models = [];
  ModelItem? selected;
  List<Offset> pathPoints = []; // 选中模型的规划刀路（工件坐标）
  bool autoLevel = false;
  String lastError = '';
  Timer? _poll;
  // —— 机器型号 / 平台尺寸（决定 3D 标尺）——
  String machineType = '3020';
  String machineLabel = 'SmartCNC 3020';
  double bedX = 300;
  double bedY = 200;
  // —— 虚拟刀仓（4 刀位）——
  List<ToolSlot> tools = [];

  String get base => 'http://$ip:$port';

  Future<bool> connect() async {
    lastError = '';
    try {
      final r = await http
          .get(Uri.parse('$base/info'))
          .timeout(const Duration(seconds: 3));
      if (r.statusCode != 200) {
        lastError = '电脑端软件返回异常（HTTP ${r.statusCode}）';
        connected = false;
        notifyListeners();
        return false;
      }
      try {
        final info = jsonDecode(r.body);
        if (info is Map && info['machine'] is Map) {
          final m = info['machine'];
          machineType = m['type'] ?? machineType;
          machineLabel = m['label'] ?? machineLabel;
          bedX = (m['bed_x'] ?? bedX).toDouble();
          bedY = (m['bed_y'] ?? bedY).toDouble();
        }
      } catch (e) {
        // 老版本模拟器无 machine 字段时忽略，使用默认 3020
      }
    } catch (e) {
      lastError =
          '无法连接 $base\n请检查：① IP/端口是否正确（端口默认 5000）② 手机与电脑是否同一 Wi-Fi ③ 电脑防火墙是否放行 5000 端口\n$e';
      connected = false;
      notifyListeners();
      return false;
    }
    connected = true;
    videoUrl = '$base/snapshot';
    notifyListeners();
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(milliseconds: 300), (_) => _pollState());
    await refreshModels();
    await fetchTools();
    await _pollState();
    return true;
  }

  void disconnect() {
    _poll?.cancel();
    connected = false;
    models = [];
    lastError = '';
    notifyListeners();
  }

  Future<void> _pollState() async {
    try {
      final r = await http
          .get(Uri.parse('$base/state'))
          .timeout(const Duration(seconds: 2));
      if (r.statusCode == 200) {
        telem = Telemetry.fromJson(jsonDecode(r.body));
        lastError = '';
        notifyListeners();
      }
    } catch (e) {
      lastError = e.toString();
    }
  }

  Future<void> refreshModels() async {
    try {
      final r = await http
          .get(Uri.parse('$base/gcode/list'))
          .timeout(const Duration(seconds: 3));
      if (r.statusCode == 200) {
        final list = jsonDecode(r.body) as List;
        models = list.map((e) => ModelItem.fromJson(e)).toList();
        lastError = '';
      } else {
        lastError = '模型库接口返回 HTTP ${r.statusCode}';
      }
    } catch (e) {
      lastError = '加载模型库失败：$e';
    }
    notifyListeners();
  }

  Future<void> fetchTools() async {
    try {
      final r = await http
          .get(Uri.parse('$base/tools'))
          .timeout(const Duration(seconds: 3));
      if (r.statusCode == 200) {
        final d = jsonDecode(r.body);
        if (d['slots'] is List) {
          tools = (d['slots'] as List).map((e) => ToolSlot.fromJson(e)).toList();
          notifyListeners();
        }
      }
    } catch (e) {
      // 忽略
    }
  }

  Future<bool> sendCmd(String cmd,
      {String name = '', bool autoLevel = false}) async {
    try {
      final r = await http
          .post(Uri.parse('$base/cmd'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(
                  {'cmd': cmd, 'name': name, 'auto_level': autoLevel}))
          .timeout(const Duration(seconds: 3));
      return r.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<void> selectModel(ModelItem m) async {
    selected = m;
    pathPoints = [];
    notifyListeners();
    await sendCmd('select', name: m.name);
    try {
      final r = await http
          .get(Uri.parse(
              '$base/gcode/get?name=${Uri.encodeComponent(m.name)}'))
          .timeout(const Duration(seconds: 3));
      if (r.statusCode == 200) {
        pathPoints = _parsePath(r.body);
        notifyListeners();
      }
    } catch (e) {
      // 忽略
    }
  }

  // 解析 G-code 的切削刀路（仅 G1 的 X/Y），用于手机刀路预览
  List<Offset> _parsePath(String gcode) {
    final pts = <Offset>[];
    var x = 0.0;
    var y = 0.0;
    for (final raw in gcode.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('(') || line.startsWith(';')) {
        continue;
      }
      if (!(line.startsWith('G0') || line.startsWith('G1'))) continue;
      final xm = RegExp(r'X([+-]?\d+(?:\.\d+)?)').firstMatch(line);
      final ym = RegExp(r'Y([+-]?\d+(?:\.\d+)?)').firstMatch(line);
      if (xm != null) x = double.parse(xm.group(1)!);
      if (ym != null) y = double.parse(ym.group(1)!);
      if (!line.startsWith('G0')) pts.add(Offset(x, y));
    }
    return pts;
  }

  void setVideoUrl(String url) {
    videoUrl = url;
    notifyListeners();
  }
}

// ── 应用根 ───────────────────────────────────────────────────
class SmartCncApp extends StatefulWidget {
  const SmartCncApp({super.key});
  @override
  State<SmartCncApp> createState() => _SmartCncAppState();
}

class _SmartCncAppState extends State<SmartCncApp> {
  int _tab = 0;
  final _pages = const [HomeScreen(), LibraryScreen(), ControlScreen(), MoreScreen()];

  void goTo(int i) => setState(() => _tab = i);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart CNC',
      theme: ThemeData(
        useMaterial3: true,
        primaryColor: const Color(0xFF19B36B),
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF19B36B)),
        scaffoldBackgroundColor: const Color(0xFFF5F6F8),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF19B36B),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
      ),
      home: AnimatedBuilder(
        animation: appState,
        builder: (_, __) => Scaffold(
          appBar: AppBar(
            title: const Text('Smart CNC 桌面雕刻机'),
            actions: [
              Container(
                margin: const EdgeInsets.only(right: 12),
                child: Center(
                  child: Chip(
                    label: Text(appState.connected ? '已连接' : '未连接',
                        style: const TextStyle(color: Colors.white, fontSize: 12)),
                    backgroundColor:
                        appState.connected ? const Color(0xFF0E8C53) : Colors.grey,
                  ),
                ),
              ),
            ],
          ),
          body: _pages[_tab],
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: _tab,
            selectedItemColor: const Color(0xFF19B36B),
            unselectedItemColor: Colors.grey,
            onTap: (i) => setState(() => _tab = i),
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.home), label: '首页'),
              BottomNavigationBarItem(icon: Icon(Icons.library_books), label: '模型库'),
              BottomNavigationBarItem(icon: Icon(Icons.gamepad), label: '控制台'),
              BottomNavigationBarItem(icon: Icon(Icons.person), label: '我的'),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 公共小组件 ───────────────────────────────────────────────
Color statusColor(String s) {
  switch (s) {
    case 'Run':
      return const Color(0xFF2D7FF9);
    case 'Hold':
      return const Color(0xFFE08A00);
    case 'Alarm':
      return const Color(0xFFE23B3B);
    case 'Door':
      return const Color(0xFFE08A00);
    case 'Level':
      return const Color(0xFF8A5CF6);
    case 'Preview':
      return const Color(0xFFE23B3B);
    default:
      return const Color(0xFF19B36B);
  }
}

String statusLabel(String s) {
  switch (s) {
    case 'Run':
      return '加工中';
    case 'Hold':
      return '已暂停';
    case 'Alarm':
      return '报警';
    case 'Door':
      return '门保护';
    case 'Level':
      return '自动找平';
    case 'Preview':
      return '激光预览';
    case 'Home':
      return '回零中';
    default:
      return '空闲';
  }
}

class StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;
  const StatusChip(this.label, this.color, {this.icon, super.key});
  @override
  Widget build(BuildContext c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) Icon(icon, size: 14, color: color),
            if (icon != null) const SizedBox(width: 4),
            Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700)),
          ],
        ),
      );
}

// 实时画面（轮询 /snapshot）
class LiveView extends StatefulWidget {
  final String url;
  final double height;
  const LiveView({required this.url, this.height = 200, super.key});
  @override
  State<LiveView> createState() => _LiveViewState();
}

class _LiveViewState extends State<LiveView> {
  Uint8List? bytes;
  Timer? _t;
  @override
  void initState() {
    super.initState();
    _tick();
    _t = Timer.periodic(const Duration(milliseconds: 500), (_) => _tick());
  }

  void _tick() async {
    if (widget.url.isEmpty) return;
    try {
      final r = await http.get(Uri.parse(widget.url)).timeout(const Duration(seconds: 2));
      if (r.statusCode == 200 && mounted) setState(() => bytes = r.bodyBytes);
    } catch (e) {
      // 忽略单帧失败
    }
  }

  @override
  void didUpdateWidget(covariant LiveView old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) _tick();
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => Container(
        height: widget.height,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(10),
        ),
        child: bytes == null
            ? const Center(child: CircularProgressIndicator(color: Colors.white))
            : ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.memory(bytes!, gaplessPlayback: true, fit: BoxFit.cover),
              ),
      );
}

// 刀路预览（规划刀路 + 实时刀头位置）
class ToolpathPreview extends StatelessWidget {
  final List<Offset> points;
  final Offset? head;
  final bool live;
  const ToolpathPreview({required this.points, this.head, this.live = false, super.key});
  @override
  Widget build(BuildContext c) => Container(
        height: 220,
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: double.infinity,
            height: 220,
            child: CustomPaint(
              painter: _PathPainter(points, head, live),
            ),
          ),
        ),
      );
}

class _PathPainter extends CustomPainter {
  final List<Offset> points;
  final Offset? head;
  final bool live;
  _PathPainter(this.points, this.head, this.live);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = const Color(0xFF12161C));
    final grid = Paint()..color = const Color(0xFF2A3340)..strokeWidth = 1;
    for (double g = 0; g <= size.width; g += 36) {
      canvas.drawLine(Offset(g, 0), Offset(g, size.height), grid);
    }
    for (double g = 0; g <= size.height; g += 36) {
      canvas.drawLine(Offset(0, g), Offset(size.width, g), grid);
    }
    if (points.length < 2) return;
    var minX = 1e9, minY = 1e9, maxX = -1e9, maxY = -1e9;
    for (final p in points) {
      minX = min(minX, p.dx);
      minY = min(minY, p.dy);
      maxX = max(maxX, p.dx);
      maxY = max(maxY, p.dy);
    }
    const pad = 16.0;
    final w = max(maxX - minX, 1.0);
    final h = max(maxY - minY, 1.0);
    final scale = min((size.width - 2 * pad) / w, (size.height - 2 * pad) / h);
    Offset toPix(Offset p) =>
        Offset(pad + (p.dx - minX) * scale, size.height - pad - (p.dy - minY) * scale);
    final pathPaint = Paint()
      ..color = live ? const Color(0xFFFF3C3C) : const Color(0xFF19B36B)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final path = Path();
    for (int i = 0; i < points.length; i++) {
      final px = toPix(points[i]);
      if (i == 0) {
        path.moveTo(px.dx, px.dy);
      } else {
        path.lineTo(px.dx, px.dy);
      }
    }
    canvas.drawPath(path, pathPaint);
    if (head != null) {
      final hp = toPix(head!);
      canvas.drawCircle(hp, 7, Paint()..color = const Color(0xFFFFFF00));
      canvas.drawCircle(hp, 13,
          Paint()..color = const Color(0xFFFFFF00)..style = PaintingStyle.stroke..strokeWidth = 2);
    }
  }

  @override
  bool shouldRepaint(covariant _PathPainter o) => true;
}

// 点动面板（用于“确定原点”前的手动对刀移动）
class JogPad extends StatelessWidget {
  final double step;
  final void Function(String axis, double dir) onJog;
  const JogPad({required this.step, required this.onJog, super.key});
  Widget _b(String label, String axis, double dir) => ElevatedButton(
        onPressed: () => onJog(axis, dir),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        child: Text(label, style: const TextStyle(fontSize: 16)),
      );
  @override
  Widget build(BuildContext c) => Column(
        children: [
          Row(children: [Expanded(child: _b('X -', 'X', -1)), const SizedBox(width: 8), Expanded(child: _b('X +', 'X', 1))]),
          const SizedBox(height: 8),
          Row(children: [Expanded(child: _b('Y -', 'Y', -1)), const SizedBox(width: 8), Expanded(child: _b('Y +', 'Y', 1))]),
          const SizedBox(height: 8),
          Row(children: [Expanded(child: _b('Z -', 'Z', -1)), const SizedBox(width: 8), Expanded(child: _b('Z +', 'Z', 1))]),
        ],
      );
}

// 报警 / 门 / 暂停 横幅
Widget buildBanners() {
  final t = appState.telem;
  if (t.alarmCode.isNotEmpty) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFDECEC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE23B3B)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning, color: Color(0xFFE23B3B)),
          const SizedBox(width: 8),
          Expanded(
            child: Text('⚠ 报警 Alarm:${t.alarmCode} — ${t.alarmMsg}',
                style: const TextStyle(color: Color(0xFFE23B3B), fontWeight: FontWeight.w600)),
          ),
          TextButton(
            onPressed: () => appState.sendCmd('\$X'),
            child: const Text('解锁', style: TextStyle(color: Color(0xFFE23B3B))),
          ),
        ],
      ),
    );
  }
  if (t.doorOpen) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4E5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE08A00)),
      ),
      child: const Row(
        children: [
          Icon(Icons.door_front_door, color: Color(0xFFE08A00)),
          SizedBox(width: 8),
          Expanded(
            child: Text('防护门已打开，运动已锁定，请关闭防护门后再操作',
                style: TextStyle(color: Color(0xFFA35A00), fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
  if (t.status == 'Hold') {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4E5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE08A00)),
      ),
      child: const Row(
        children: [
          Icon(Icons.pause_circle, color: Color(0xFFE08A00)),
          SizedBox(width: 8),
          Expanded(
            child: Text('已暂停（点控制台“继续”恢复）',
                style: TextStyle(color: Color(0xFFA35A00), fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
  return const SizedBox.shrink();
}

// ── 首页 ─────────────────────────────────────────────────────
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext c) {
    final t = appState.telem;
    if (!appState.connected) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_off, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('尚未连接到电脑端软件', style: TextStyle(fontSize: 16, color: Colors.grey)),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: const Icon(Icons.link),
              label: const Text('去连接'),
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
              onPressed: () => showConnectSheet(c),
            ),
          ],
        ),
      );
    }
    final active = t.status == 'Run' || t.status == 'Level' || t.status == 'Preview';
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        buildBanners(),
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  StatusChip(statusLabel(t.status), statusColor(t.status), icon: Icons.circle),
                  const Spacer(),
                  StatusChip('进给 ${t.feed}', Colors.blueGrey),
                ]),
                const SizedBox(height: 12),
                LiveView(url: appState.videoUrl, height: 200),
                const SizedBox(height: 10),
                Text('工件坐标  X ${t.wpos[0].toStringAsFixed(2)}  Y ${t.wpos[1].toStringAsFixed(2)}  Z ${t.wpos[2].toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 13, color: Colors.black87)),
                const SizedBox(height: 4),
                Text('机械坐标  X ${t.mpos[0].toStringAsFixed(2)}  Y ${t.mpos[1].toStringAsFixed(2)}  Z ${t.mpos[2].toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
                if (t.originSet) const SizedBox(height: 4),
                if (t.originSet)
                  const Text('✓ 已确定工件原点', style: TextStyle(fontSize: 12, color: Color(0xFF19B36B))),
              ],
            ),
          ),
        ),
        if (active) ...[
          const SizedBox(height: 12),
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('当前任务：${t.jobName.isEmpty ? "—" : t.jobName}',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: t.progress,
                    minHeight: 10,
                    color: statusColor(t.status),
                  ),
                  const SizedBox(height: 6),
                  Text('进度 ${(t.progress * 100).round()}%',
                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: _HomeBtn(Icons.library_books, '模型库', () {
              c.findAncestorStateOfType<_SmartCncAppState>()?.goTo(1);
            }),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _HomeBtn(Icons.gamepad, '控制台', () {
              c.findAncestorStateOfType<_SmartCncAppState>()?.goTo(2);
            }),
          ),
        ]),
        const SizedBox(height: 10),
        if (appState.selected != null)
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: ListTile(
              leading: const Icon(Icons.check_circle, color: Color(0xFF19B36B)),
              title: Text('已选模型：${appState.selected!.title}'),
              subtitle: const Text('前往“模型库”可重新准备雕刻'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () {
                Navigator.of(c).push(MaterialPageRoute(
                    builder: (_) => PrepareScreen(model: appState.selected!)));
              },
            ),
          ),
      ],
    );
  }
}

class _HomeBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _HomeBtn(this.icon, this.label, this.onTap);
  @override
  Widget build(BuildContext c) => Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Column(children: [
              Icon(icon, size: 30, color: const Color(0xFF19B36B)),
              const SizedBox(height: 6),
              Text(label),
            ]),
          ),
        ),
      );
}

// ── 模型库 ───────────────────────────────────────────────────
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> with SingleTickerProviderStateMixin {
  late TabController _tc;
  bool _wasConnected = false;

  @override
  void initState() {
    super.initState();
    _tc = TabController(length: 2, vsync: this);
    appState.addListener(_onAppState);
    if (appState.connected) appState.refreshModels();
  }

  void _onAppState() {
    // 连接一旦建立，自动拉一次模型库（覆盖“先连后看”的场景）
    if (appState.connected && !_wasConnected) {
      appState.refreshModels();
    }
    _wasConnected = appState.connected;
  }

  @override
  void dispose() {
    appState.removeListener(_onAppState);
    _tc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    if (!appState.connected) {
      return const Center(child: Text('请先在“我的”中连接电脑端软件', style: TextStyle(color: Colors.grey)));
    }
    if (appState.models.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('模型库暂时为空', style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 8),
              if (appState.lastError.isNotEmpty)
                Text(appState.lastError,
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                    textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('重新加载'),
                onPressed: () => appState.refreshModels(),
              ),
            ],
          ),
        ),
      );
    }
    final public = appState.models.where((m) => m.public).toList();
    final mine = appState.models.where((m) => !m.public).toList();
    return Column(
      children: [
        TabBar(
          controller: _tc,
          labelColor: const Color(0xFF19B36B),
          unselectedLabelColor: Colors.grey,
          tabs: [Tab(text: '公用模型 (${public.length})'), Tab(text: '我的模型 (${mine.length})')],
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: appState.refreshModels,
            child: TabBarView(
              controller: _tc,
              children: [
                _ModelList(items: public),
                _ModelList(items: mine),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ModelList extends StatelessWidget {
  final List<ModelItem> items;
  const _ModelList({required this.items});
  @override
  Widget build(BuildContext c) {
    if (items.isEmpty) {
      return const Center(child: Text('暂无模型', style: TextStyle(color: Colors.grey)));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(14),
      itemCount: items.length,
      itemBuilder: (_, i) {
        final m = items[i];
        return Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(child: Text(m.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: m.public ? Colors.blue.shade50 : const Color(0xFF19B36B).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(m.public ? '公用' : '我的',
                        style: TextStyle(fontSize: 11, color: m.public ? Colors.blue : const Color(0xFF19B36B))),
                  ),
                ]),
                const SizedBox(height: 6),
                if (m.desc.isNotEmpty) Text(m.desc, style: const TextStyle(fontSize: 13, color: Colors.black54)),
                const SizedBox(height: 6),
                Wrap(spacing: 8, runSpacing: 4, children: [
                  if (m.size.isNotEmpty) _Tag('尺寸 $m.size'),
                  if (m.tool.isNotEmpty) _Tag('刀具 $m.tool'),
                  _Tag('$m.lines 行 G-code'),
                ]),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      appState.selectModel(m);
                      Navigator.of(c).push(MaterialPageRoute(builder: (_) => PrepareScreen(model: m)));
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF19B36B),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('选择并准备雕刻'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Tag extends StatelessWidget {
  final String text;
  const _Tag(this.text);
  @override
  Widget build(BuildContext c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(6)),
        child: Text(text, style: const TextStyle(fontSize: 11, color: Colors.black54)),
      );
}

// ── 准备雕刻（确定原点 / 自动找平 / 激光预览 / 刀路预览 / 确认）──
class PrepareScreen extends StatefulWidget {
  final ModelItem model;
  const PrepareScreen({required this.model, super.key});
  @override
  State<PrepareScreen> createState() => _PrepareScreenState();
}

class _PrepareScreenState extends State<PrepareScreen> {
  double _step = 1.0;
  bool _autoLevel = false;
  bool _busy = false;
  String _material = '';
  bool _showDims = false;
  final _wC = TextEditingController();
  final _dC = TextEditingController();
  final _hC = TextEditingController();
  bool _toolConfirmed = false;

  @override
  void initState() {
    super.initState();
    _autoLevel = appState.autoLevel;
    _material = widget.model.materials.isNotEmpty ? widget.model.materials.first : '';
    final mm = widget.model.minMaterial;
    _wC.text = ((mm['w'] ?? 0)).toStringAsFixed(0);
    _dC.text = ((mm['d'] ?? 0)).toStringAsFixed(0);
    _hC.text = ((mm['h'] ?? 0)).toStringAsFixed(0);
    appState.selectModel(widget.model);
    appState.fetchTools();
  }

  bool get _dimsOk {
    if (!_showDims) return true;
    final w = double.tryParse(_wC.text) ?? 0;
    final d = double.tryParse(_dC.text) ?? 0;
    final h = double.tryParse(_hC.text) ?? 0;
    final mm = widget.model.minMaterial;
    return w >= (mm['w'] ?? 0) - 0.01 &&
        d >= (mm['d'] ?? 0) - 0.01 &&
        h >= (mm['h'] ?? 0) - 0.01;
  }

  List<ToolSlot> get _slots =>
      appState.tools.isNotEmpty ? appState.tools : appState.telem.tools;

  ToolSlot? get _reqSlot {
    if (widget.model.toolId.isEmpty) return null;
    for (final s in _slots) {
      if (s.id == widget.model.toolId) return s;
    }
    return null;
  }

  bool get _reqPresent {
    final r = _reqSlot;
    return r != null && r.installed && r.sensor;
  }

  @override
  void dispose() {
    _wC.dispose();
    _dC.dispose();
    _hC.dispose();
    super.dispose();
  }

  Widget _numField(String label, TextEditingController c) => TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
            labelText: label, border: const OutlineInputBorder(), isDense: true),
      );

  List<Widget> _toolSlotWidgets() {
    final slots = _slots;
    if (slots.isEmpty) {
      return [const Text('正在读取刀仓…', style: TextStyle(color: Colors.grey))];
    }
    return slots.map((s) {
      final required = s.id == widget.model.toolId;
      final present = s.installed && s.sensor;
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: required
              ? const Color(0xFF19B36B).withOpacity(0.08)
              : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: required
                  ? const Color(0xFF19B36B).withOpacity(0.4)
                  : Colors.grey.shade300),
        ),
        child: Row(children: [
          Icon(present ? Icons.check_circle : Icons.radio_button_unchecked,
              color: present ? const Color(0xFF19B36B) : Colors.grey),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${s.id}  ${s.name}${required ? "（建议刀具）" : ""}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(present ? '刀仓传感器：检测到有刀' : '刀仓传感器：空 / 未检测',
                    style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          ),
          if (required)
            Checkbox(
              value: _toolConfirmed,
              onChanged: present ? (v) => setState(() => _toolConfirmed = v ?? false) : null,
            ),
        ]),
      );
    }).toList();
  }

  void _jog(String axis, double dir) {
    if (appState.telem.jobRunning || appState.telem.previewMode) return;
    appState.sendCmd('\$J=$axis${(dir * _step).toString()}');
  }

  Future<void> _setOrigin() async {
    setState(() => _busy = true);
    await appState.sendCmd('set_origin');
    await appState._pollState();
    setState(() => _busy = false);
  }

  Future<void> _preview() async {
    setState(() => _busy = true);
    await appState.sendCmd('preview', name: widget.model.name);
    setState(() => _busy = false);
  }

  Future<void> _start() async {
    appState.autoLevel = _autoLevel;
    setState(() => _busy = true);
    await appState.sendCmd('start', name: widget.model.name, autoLevel: _autoLevel);
    setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext c) {
    final t = appState.telem;
    final active = t.status == 'Run' || t.status == 'Level' || t.status == 'Preview';
    final done = !active && t.progress >= 1 && t.jobName == widget.model.name;
    final head = Offset(t.wpos[0], t.wpos[1]);
    return Scaffold(
      appBar: AppBar(title: Text('准备：${widget.model.title}')),
      body: AnimatedBuilder(
        animation: appState,
        builder: (_, __) => ListView(
          padding: const EdgeInsets.all(14),
          children: [
            buildBanners(),
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.model.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    if (widget.model.desc.isNotEmpty)
                      Padding(padding: const EdgeInsets.only(top: 4), child: Text(widget.model.desc, style: const TextStyle(color: Colors.black54))),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, children: [
                      if (widget.model.size.isNotEmpty) _Tag('尺寸 ${widget.model.size}'),
                      if (widget.model.tool.isNotEmpty) _Tag('刀具 ${widget.model.tool}'),
                    ]),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.view_in_ar),
                        label: const Text('3D 预览（旋转 / 缩放查看模型与平台）'),
                        onPressed: () => Navigator.of(c).push(MaterialPageRoute(
                            builder: (_) => Model3DScreen(
                                  title: widget.model.title,
                                  bedX: appState.bedX,
                                  bedY: appState.bedY,
                                  outline: widget.model.outline,
                                  height: widget.model.height,
                                ))),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (active || done) ...[
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        StatusChip(statusLabel(t.status), statusColor(t.status), icon: Icons.circle),
                        const Spacer(),
                        if (t.leveled) const StatusChip('已找平', Colors.purple),
                      ]),
                      const SizedBox(height: 10),
                      if (t.leveling) ...[
                        LinearProgressIndicator(value: t.levelProgress, minHeight: 10, color: statusColor('Level')),
                        const SizedBox(height: 6),
                        Text('找平进度 ${(t.levelProgress * 100).round()}%', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                      ] else ...[
                        LinearProgressIndicator(value: t.progress, minHeight: 10, color: statusColor(t.status)),
                        const SizedBox(height: 6),
                        Text('进度 ${(t.progress * 100).round()}%', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                      ],
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(child: OutlinedButton.icon(icon: const Icon(Icons.pause), label: const Text('暂停'), onPressed: t.status == 'Hold' ? null : () => appState.sendCmd('!'))),
                        const SizedBox(width: 8),
                        Expanded(child: OutlinedButton.icon(icon: const Icon(Icons.play_arrow), label: const Text('继续'), onPressed: t.status == 'Hold' ? () => appState.sendCmd('~') : null)),
                        const SizedBox(width: 8),
                        Expanded(child: OutlinedButton.icon(icon: const Icon(Icons.stop), label: const Text('急停'), style: OutlinedButton.styleFrom(foregroundColor: Colors.red), onPressed: () => appState.sendCmd('\x18'))),
                      ]),
                      if (done)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: SizedBox(width: double.infinity, child: ElevatedButton(onPressed: () => Navigator.of(c).pop(), child: const Text('完成，返回'))),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (!active) ...[
              // —— 第 1 步：确定原点 ——
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('① 确定原点', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                      const SizedBox(height: 4),
                      const Text('手动移动刀具到材料角点，然后“设为原点”（WPos 归零）。', style: TextStyle(color: Colors.black54, fontSize: 12)),
                      const SizedBox(height: 10),
                      Row(children: [
                        const Text('步长', style: TextStyle(fontSize: 13)),
                        const SizedBox(width: 8),
                        ChoiceChip(label: const Text('1 mm'), selected: _step == 1, onSelected: (_) => setState(() => _step = 1)),
                        const SizedBox(width: 8),
                        ChoiceChip(label: const Text('0.1 mm'), selected: _step == 0.1, onSelected: (_) => setState(() => _step = 0.1)),
                      ]),
                      const SizedBox(height: 10),
                      JogPad(step: _step, onJog: _jog),
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: Icon(t.originSet ? Icons.check_circle : Icons.gps_fixed),
                            label: Text(t.originSet ? '已设原点（重设）' : '设为原点'),
                            style: ElevatedButton.styleFrom(backgroundColor: t.originSet ? Colors.grey : const Color(0xFF19B36B), foregroundColor: Colors.white),
                            onPressed: _busy ? null : _setOrigin,
                          ),
                        ),
                      ]),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // —— 第 2 步：自动找平 ——
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('② 自动找平', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                        SizedBox(height: 4),
                        Text('开启后，雕刻前机器先用探针探测台面，自动补偿不平整。', style: TextStyle(color: Colors.black54, fontSize: 12)),
                      ])),
                      Switch(value: _autoLevel, onChanged: (v) => setState(() => _autoLevel = v)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // —— 第 3 步：激光预览 + 刀路预览 ——
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('③ 激光预览 / 刀路预览', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                      const SizedBox(height: 4),
                      const Text('“激光预览”会用红光沿刀路快速走一遍（不开主轴）。下方为手机刀路预览，黄点为实时刀头位置。', style: TextStyle(color: Colors.black54, fontSize: 12)),
                      const SizedBox(height: 10),
                      ToolpathPreview(points: appState.pathPoints, head: head, live: t.laserOn),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.lightbulb_outline),
                          label: const Text('激光预览'),
                          onPressed: _busy || t.previewMode ? null : _preview,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // —— 第 3 步：耗材与刀具确认 ——
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('③ 耗材与刀具确认', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                      const SizedBox(height: 4),
                      const Text('选择你实际放入的耗材材质；默认无需填写尺寸（请放入≥最小要求的耗材，激光预览时确认实际雕刻区域）。若已知材料尺寸可填写以校验。', style: TextStyle(color: Colors.black54, fontSize: 12)),
                      const SizedBox(height: 10),
                      const Text('实际耗材材质', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      Wrap(spacing: 8, runSpacing: 6, children: [
                        ...widget.model.materials.map((m) => ChoiceChip(
                              label: Text(m),
                              selected: _material == m,
                              onSelected: (_) => setState(() => _material = m),
                            )),
                        ChoiceChip(
                          label: const Text('自定义'),
                          selected: _material == '自定义',
                          onSelected: (_) => setState(() => _material = '自定义'),
                        ),
                      ]),
                      if (_material == '自定义')
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: TextField(
                            onChanged: (v) => setState(() => _material = v),
                            decoration: const InputDecoration(labelText: '自定义材料名称', border: OutlineInputBorder()),
                          ),
                        ),
                      const SizedBox(height: 10),
                      Row(children: [
                        Checkbox(value: _showDims, onChanged: (v) => setState(() => _showDims = v ?? false)),
                        const Expanded(child: Text('我已知实际耗材尺寸（用于校验是否≥最小要求）')),
                      ]),
                      if (_showDims) ...[
                        const SizedBox(height: 8),
                        Row(children: [
                          Expanded(child: _numField('宽 W (mm)', _wC)),
                          const SizedBox(width: 8),
                          Expanded(child: _numField('深 D (mm)', _dC)),
                          const SizedBox(width: 8),
                          Expanded(child: _numField('高 H (mm)', _hC)),
                        ]),
                        const SizedBox(height: 6),
                        Text('最小要求：${(widget.model.minMaterial['w'] ?? 0).toStringAsFixed(0)}×${(widget.model.minMaterial['d'] ?? 0).toStringAsFixed(0)}×${(widget.model.minMaterial['h'] ?? 0).toStringAsFixed(0)} mm',
                            style: TextStyle(color: _dimsOk ? const Color(0xFF19B36B) : Colors.red, fontWeight: FontWeight.w600)),
                        if (!_dimsOk)
                          const Text('⚠ 实际耗材小于最小要求，可能无法完整雕刻', style: TextStyle(color: Colors.red)),
                        const SizedBox(height: 6),
                        const Text('提示：激光预览时可在机器上确认实际雕刻区域是否落在耗材内。', style: TextStyle(color: Colors.black54, fontSize: 12)),
                      ],
                      const SizedBox(height: 12),
                      const Text('刀仓确认（类拓竹 AMS）', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      const Text('请按刀仓实际状态逐项确认：建议刀具所在的刀位必须已装入并被传感器检测到。', style: TextStyle(color: Colors.black54, fontSize: 12)),
                      const SizedBox(height: 8),
                      ..._toolSlotWidgets(),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // —— 第 4 步：确认雕刻 ——
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('④ 确认雕刻', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                      const SizedBox(height: 8),
                      if (!t.originSet)
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: const Color(0xFFFFF4E5), borderRadius: BorderRadius.circular(8)),
                          child: const Text('请先“确定原点”再开始雕刻。', style: TextStyle(color: Color(0xFFA35A00))),
                        ),
                      if (_material.isEmpty)
                        Container(
                          margin: const EdgeInsets.only(top: 8),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: const Color(0xFFFFF4E5), borderRadius: BorderRadius.circular(8)),
                          child: const Text('请选择实际耗材材质。', style: TextStyle(color: Color(0xFFA35A00))),
                        ),
                      if (!_reqPresent)
                        Container(
                          margin: const EdgeInsets.only(top: 8),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: const Color(0xFFFFF4E5), borderRadius: BorderRadius.circular(8)),
                          child: Text('建议刀具 ${widget.model.toolId} 未装入刀仓（传感器未检测到）。请在机器上装入后再确认。', style: const TextStyle(color: Color(0xFFA35A00))),
                        )
                      else if (!_toolConfirmed)
                        Container(
                          margin: const EdgeInsets.only(top: 8),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: const Color(0xFFFFF4E5), borderRadius: BorderRadius.circular(8)),
                          child: const Text('请勾选确认建议刀具所在的刀位已就位。', style: TextStyle(color: Color(0xFFA35A00))),
                        ),
                      if (_showDims && !_dimsOk)
                        Container(
                          margin: const EdgeInsets.only(top: 8),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: const Color(0xFFFDECEC), borderRadius: BorderRadius.circular(8)),
                          child: const Text('实际耗材小于最小要求，请更换更大耗材或关闭“已知尺寸”。', style: TextStyle(color: Color(0xFFE23B3B))),
                        ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.play_circle_fill),
                          label: const Text('确认雕刻'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: (t.originSet && _material.isNotEmpty && _reqPresent && _toolConfirmed && _dimsOk && !_busy)
                                ? const Color(0xFF19B36B)
                                : Colors.grey,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          onPressed: (t.originSet && _material.isNotEmpty && _reqPresent && _toolConfirmed && _dimsOk && !_busy)
                              ? _start
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── 控制台（手动操作）────────────────────────────────────────
class ControlScreen extends StatefulWidget {
  const ControlScreen({super.key});
  @override
  State<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends State<ControlScreen> {
  double _step = 1.0;
  void _jog(String axis, double dir) {
    if (appState.telem.jobRunning || appState.telem.previewMode) return;
    appState.sendCmd('\$J=$axis${(dir * _step).toString()}');
  }

  @override
  Widget build(BuildContext c) {
    if (!appState.connected) {
      return const Center(child: Text('请先在“我的”中连接电脑端软件', style: TextStyle(color: Colors.grey)));
    }
    final t = appState.telem;
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        buildBanners(),
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  StatusChip(statusLabel(t.status), statusColor(t.status), icon: Icons.circle),
                  const Spacer(),
                  StatusChip('进给 ${t.feed}', Colors.blueGrey),
                  const SizedBox(width: 6),
                  StatusChip('主轴 ${t.spindle}', Colors.blueGrey),
                ]),
                const SizedBox(height: 10),
                Text('工件坐标  X ${t.wpos[0].toStringAsFixed(2)}  Y ${t.wpos[1].toStringAsFixed(2)}  Z ${t.wpos[2].toStringAsFixed(2)}'),
                const SizedBox(height: 4),
                Text('机械坐标  X ${t.mpos[0].toStringAsFixed(2)}  Y ${t.mpos[1].toStringAsFixed(2)}  Z ${t.mpos[2].toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('手动移动（点动）', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 8),
                Row(children: [
                  const Text('步长', style: TextStyle(fontSize: 13)),
                  const SizedBox(width: 8),
                  ChoiceChip(label: const Text('1 mm'), selected: _step == 1, onSelected: (_) => setState(() => _step = 1)),
                  const SizedBox(width: 8),
                  ChoiceChip(label: const Text('0.1 mm'), selected: _step == 0.1, onSelected: (_) => setState(() => _step = 0.1)),
                ]),
                const SizedBox(height: 10),
                JogPad(step: _step, onJog: _jog),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('机器操作', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  _OpBtn('回零', Icons.home, () => appState.sendCmd('\$H')),
                  _OpBtn('主轴开', Icons.bolt, () => appState.sendCmd('M3 S12000')),
                  _OpBtn('主轴关', Icons.bolt, () => appState.sendCmd('M5')),
                  _OpBtn('吹气开', Icons.air, () => appState.sendCmd('M8')),
                  _OpBtn('吹气关', Icons.air, () => appState.sendCmd('M9')),
                  _OpBtn('暂停', Icons.pause, () => appState.sendCmd('!')),
                  _OpBtn('继续', Icons.play_arrow, () => appState.sendCmd('~')),
                  _OpBtn('急停', Icons.stop_circle, () => appState.sendCmd('\x18'), danger: true),
                ]),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _OpBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool danger;
  const _OpBtn(this.label, this.icon, this.onTap, {this.danger = false});
  @override
  Widget build(BuildContext c) => ElevatedButton.icon(
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          foregroundColor: danger ? Colors.white : const Color(0xFF19B36B),
          backgroundColor: danger ? const Color(0xFFE23B3B) : Colors.white,
          side: danger ? null : const BorderSide(color: Color(0xFF19B36B)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        onPressed: onTap,
      );
}

// ── 我的（连接设置 / 实时画面地址）────────────────────────────
class MoreScreen extends StatefulWidget {
  const MoreScreen({super.key});
  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<MoreScreen> {
  late TextEditingController _ip;
  late TextEditingController _port;
  late TextEditingController _video;

  @override
  void initState() {
    super.initState();
    _ip = TextEditingController(text: appState.ip);
    _port = TextEditingController(text: appState.port.toString());
    _video = TextEditingController(text: appState.videoUrl);
  }

  @override
  void dispose() {
    _ip.dispose();
    _port.dispose();
    _video.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('连接电脑端软件', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 6),
                const Text('手机与电脑需在同一 Wi-Fi。IP 填电脑局域网地址（模拟器启动时会显示），端口默认 5000。',
                    style: TextStyle(color: Colors.black54, fontSize: 12)),
                const SizedBox(height: 10),
                TextField(controller: _ip, decoration: const InputDecoration(labelText: '电脑 IP', border: OutlineInputBorder())),
                const SizedBox(height: 10),
                TextField(controller: _port, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '端口', border: OutlineInputBorder())),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.link),
                      label: Text(appState.connected ? '重新连接' : '连接'),
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF19B36B), foregroundColor: Colors.white),
                      onPressed: () async {
                        appState.ip = _ip.text.trim();
                        appState.port = int.tryParse(_port.text.trim()) ?? 5000;
                        final ok = await appState.connect();
                        if (!ok && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('连接失败：${appState.lastError}')),
                          );
                        }
                        setState(() {});
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (appState.connected)
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.link_off),
                        label: const Text('断开'),
                        onPressed: () {
                          appState.disconnect();
                          setState(() {});
                        },
                      ),
                    ),
                ]),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: const Text('刷新模型库'),
                  style: ElevatedButton.styleFrom(foregroundColor: const Color(0xFF19B36B)),
                  onPressed: () => appState.refreshModels(),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('实时画面地址', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 6),
                const Text('连接后会自动指向电脑实时画面；也可手动修改。', style: TextStyle(color: Colors.black54, fontSize: 12)),
                const SizedBox(height: 10),
                TextField(controller: _video, decoration: const InputDecoration(labelText: 'URL', border: OutlineInputBorder())),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      appState.setVideoUrl(_video.text.trim());
                      ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content: Text('已更新实时画面地址')));
                    },
                    style: ElevatedButton.styleFrom(foregroundColor: const Color(0xFF19B36B)),
                    child: const Text('保存地址'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text('关于', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                SizedBox(height: 6),
                Text('Smart CNC 桌面雕刻机 · 手机端', style: TextStyle(color: Colors.black54)),
                SizedBox(height: 4),
                Text('手机仅用于：从模型库选择模型、确定原点、自动找平、激光预览、确认雕刻，以及监控实时画面与进度。刀路由电脑端软件生成，不在手机上生成。',
                    style: TextStyle(color: Colors.black54, fontSize: 12)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── 3D 模型预览（旋转 / 缩放 / 平台标尺）──────────────────────
class Model3DScreen extends StatefulWidget {
  final String title;
  final double bedX;
  final double bedY;
  final List<List<double>> outline;
  final double height;
  const Model3DScreen(
      {required this.title,
      required this.bedX,
      required this.bedY,
      required this.outline,
      required this.height,
      super.key});
  @override
  State<Model3DScreen> createState() => _Model3DScreenState();
}

class _Model3DScreenState extends State<Model3DScreen> {
  double _az = -0.7;
  double _el = 0.5;
  late double _dist;
  double _lastScale = 1.0;
  final double _minDist = 60.0;
  final double _maxDist = 1400.0;

  @override
  void initState() {
    super.initState();
    _dist = max(widget.bedX, widget.bedY) * 1.9;
  }

  void _reset() => setState(() {
        _az = -0.7;
        _el = 0.5;
        _dist = max(widget.bedX, widget.bedY) * 1.9;
      });

  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(title: Text('3D 预览 · ${widget.title}')),
        body: Column(
          children: [
            Expanded(
              child: Container(
                color: const Color(0xFF0E1116),
                child: GestureDetector(
                  onScaleStart: (_) => _lastScale = 1.0,
                  onScaleUpdate: (d) {
                    setState(() {
                      _az -= d.focalPointDelta.dx * 0.01;
                      _el = (_el - d.focalPointDelta.dy * 0.01).clamp(-1.35, 1.35);
                      final f = d.scale / max(_lastScale, 1e-3);
                      _dist = (_dist / f).clamp(_minDist, _maxDist);
                      _lastScale = d.scale;
                    });
                  },
                  child: CustomPaint(
                    painter: _Model3DPainter(widget.bedX, widget.bedY,
                        widget.outline, widget.height, _az, _el, _dist),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text('单指拖动旋转 · 双指捏合缩放',
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                  ),
                  TextButton.icon(
                      onPressed: _reset,
                      icon: const Icon(Icons.refresh),
                      label: const Text('复位')),
                ],
              ),
            ),
          ],
        ),
      );
}

class _Model3DPainter extends CustomPainter {
  final double bedX, bedY;
  final List<List<double>> outline;
  final double height;
  final double az, el, dist;
  _Model3DPainter(this.bedX, this.bedY, this.outline, this.height, this.az,
      this.el, this.dist);

  vm.Vector3 _project(vm.Vector3 p, vm.Matrix4 vp, double w, double h) {
    final clip = vp * vm.Vector4(p.x, p.y, p.z, 1.0);
    if (clip.w <= 1e-6) return vm.Vector3(double.nan, double.nan, double.nan);
    final ndcx = clip.x / clip.w;
    final ndcy = clip.y / clip.w;
    return vm.Vector3((ndcx * 0.5 + 0.5) * w, (1 - (ndcy * 0.5 + 0.5)) * h, clip.w);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final target = vm.Vector3(bedX / 2, bedY / 2, height * 0.5);
    final eye = vm.Vector3(
      target.x + dist * cos(el) * sin(az),
      target.y + dist * cos(el) * cos(az),
      target.z + dist * sin(el),
    );
    // 视图矩阵 lookAt（右手系，相机看向 -z）—— 手动构造，避免依赖 vector_math 顶层导出
    final up = vm.Vector3(0, 0, 1);
    final zaxis = (eye - target).normalized();
    final xaxis = vm.Vector3.cross(up, zaxis).normalized();
    final yaxis = vm.Vector3.cross(zaxis, xaxis);
    final view = vm.Matrix4.zero();
    view.setEntry(0, 0, xaxis.x); view.setEntry(1, 0, yaxis.x); view.setEntry(2, 0, zaxis.x);
    view.setEntry(0, 1, xaxis.y); view.setEntry(1, 1, yaxis.y); view.setEntry(2, 1, zaxis.y);
    view.setEntry(0, 2, xaxis.z); view.setEntry(1, 2, yaxis.z); view.setEntry(2, 2, zaxis.z);
    view.setEntry(0, 3, -xaxis.dot(eye)); view.setEntry(1, 3, -yaxis.dot(eye)); view.setEntry(2, 3, -zaxis.dot(eye));
    view.setEntry(3, 3, 1.0);
    // 透视投影矩阵（OpenGL 风格，clip.w = -z_view）
    final f = 1.0 / tan(0.7853 / 2);
    final aspect = w / h;
    final near = 1.0, far = dist * 6 + 1000;
    final proj = vm.Matrix4.zero();
    proj.setEntry(0, 0, f / aspect);
    proj.setEntry(1, 1, f);
    proj.setEntry(2, 2, (far + near) / (near - far));
    proj.setEntry(2, 3, (2 * far * near) / (near - far));
    proj.setEntry(3, 2, -1.0);
    final vp = proj * view;

    // 平台网格
    final grid = Paint()..color = const Color(0x333A4554)..strokeWidth = 1;
    const step = 20.0;
    for (double x = 0; x <= bedX + 0.1; x += step) {
      final a = _project(vm.Vector3(x, 0, 0), vp, w, h);
      final b = _project(vm.Vector3(x, bedY, 0), vp, w, h);
      if (a.z > 0 && b.z > 0) canvas.drawLine(Offset(a.x, a.y), Offset(b.x, b.y), grid);
    }
    for (double y = 0; y <= bedY + 0.1; y += step) {
      final a = _project(vm.Vector3(0, y, 0), vp, w, h);
      final b = _project(vm.Vector3(bedX, y, 0), vp, w, h);
      if (a.z > 0 && b.z > 0) canvas.drawLine(Offset(a.x, a.y), Offset(b.x, b.y), grid);
    }
    // 平台边框
    final borderPts = [
      vm.Vector3(0, 0, 0),
      vm.Vector3(bedX, 0, 0),
      vm.Vector3(bedX, bedY, 0),
      vm.Vector3(0, bedY, 0)
    ];
    _drawPoly(canvas, borderPts, vp, w, h,
        Paint()..color = const Color(0xFF6FA8FF)..strokeWidth = 2);

    // 标尺刻度（前边 y=0 与左边 x=0）
    final tick = Paint()..color = const Color(0xFF8FB6FF)..strokeWidth = 1.5;
    for (double x = 0; x <= bedX + 0.1; x += 10) {
      final major = (x % 50).abs() < 0.1;
      final a = _project(vm.Vector3(x, 0, 0), vp, w, h);
      final b = _project(vm.Vector3(x, major ? 6 : 3, 0), vp, w, h);
      if (a.z > 0 && b.z > 0) {
        canvas.drawLine(Offset(a.x, a.y), Offset(b.x, b.y), tick);
        if (major) _label(canvas, '${x.toInt()}', a.x, a.y + 10);
      }
    }
    for (double y = 0; y <= bedY + 0.1; y += 10) {
      final major = (y % 50).abs() < 0.1;
      final a = _project(vm.Vector3(0, y, 0), vp, w, h);
      final b = _project(vm.Vector3(major ? 6 : 3, y, 0), vp, w, h);
      if (a.z > 0 && b.z > 0) {
        canvas.drawLine(Offset(a.x, a.y), Offset(b.x, b.y), tick);
        if (major) _label(canvas, '${y.toInt()}', a.x - 18, a.y + 4);
      }
    }

    // 模型（拉伸轮廓到 height，置于平台中央）
    if (outline.length >= 3) {
      final cx = bedX / 2, cy = bedY / 2;
      final bottom = outline.map((p) => vm.Vector3(cx + p[0], cy + p[1], 0)).toList();
      final top = outline.map((p) => vm.Vector3(cx + p[0], cy + p[1], height)).toList();
      _fillPoly(canvas, bottom, vp, w, h, const Color(0x5519B36B));
      for (int i = 0; i < outline.length; i++) {
        final j = (i + 1) % outline.length;
        _fillQuad(canvas, bottom[i], bottom[j], top[j], top[i], vp, w, h,
            const Color(0x3319B36B));
      }
      _fillPoly(canvas, top, vp, w, h, const Color(0x8819B36B));
      final line = Paint()..color = const Color(0xFF19B36B)..strokeWidth = 2;
      _drawPoly(canvas, bottom, vp, w, h, line);
      _drawPoly(canvas, top, vp, w, h, line);
      for (int i = 0; i < outline.length; i++) {
        final b = _project(bottom[i], vp, w, h);
        final t = _project(top[i], vp, w, h);
        if (b.z > 0 && t.z > 0) canvas.drawLine(Offset(b.x, b.y), Offset(t.x, t.y), line);
      }
      double minX = 1e9, maxX = -1e9, minY = 1e9, maxY = -1e9;
      for (final p in outline) {
        minX = min(minX, p[0]);
        maxX = max(maxX, p[0]);
        minY = min(minY, p[1]);
        maxY = max(maxY, p[1]);
      }
      final Wd = (maxX - minX).abs(), Dd = (maxY - minY).abs();
      final tp = _project(vm.Vector3(cx, cy, height + 4), vp, w, h);
      if (tp.z > 0) {
        _labelBig(canvas,
            '模型 ${Wd.toStringAsFixed(0)}×${Dd.toStringAsFixed(0)}×${height.toStringAsFixed(0)} mm', tp.x, tp.y - 4);
      }
    }

    final bp = _project(vm.Vector3(bedX / 2, bedY + 10, 0), vp, w, h);
    if (bp.z > 0) {
      _labelBig(canvas, '平台 ${bedX.toInt()}×${bedY.toInt()} mm', bp.x, bp.y);
    }
  }

  void _label(Canvas c, String s, double x, double y) {
    final tp = TextPainter(
        text: TextSpan(
            text: s, style: const TextStyle(color: Color(0xFF8FB6FF), fontSize: 10)),
        textDirection: TextDirection.ltr);
    tp.layout();
    tp.paint(c, Offset(x - tp.width / 2, y));
  }

  void _labelBig(Canvas c, String s, double x, double y) {
    final tp = TextPainter(
        text: TextSpan(
            text: s,
            style: const TextStyle(
                color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
        textDirection: TextDirection.ltr);
    tp.layout();
    tp.paint(c, Offset(x - tp.width / 2, y - tp.height));
  }

  void _drawPoly(Canvas c, List<vm.Vector3> pts, vm.Matrix4 vp, double w, double h, Paint p) {
    if (pts.length < 2) return;
    final proj = pts.map((v) => _project(v, vp, w, h)).toList();
    if (proj.any((v) => v.z <= 0)) return;
    final path = Path();
    path.moveTo(proj[0].x, proj[0].y);
    for (int i = 1; i < proj.length; i++) path.lineTo(proj[i].x, proj[i].y);
    path.close();
    c.drawPath(path, p);
  }

  void _fillPoly(Canvas c, List<vm.Vector3> pts, vm.Matrix4 vp, double w, double h, Color col) {
    if (pts.length < 3) return;
    final proj = pts.map((v) => _project(v, vp, w, h)).toList();
    if (proj.any((v) => v.z <= 0)) return;
    final path = Path();
    path.moveTo(proj[0].x, proj[0].y);
    for (int i = 1; i < proj.length; i++) path.lineTo(proj[i].x, proj[i].y);
    path.close();
    c.drawPath(path, Paint()..color = col..style = PaintingStyle.fill);
  }

  void _fillQuad(Canvas c, vm.Vector3 a, vm.Vector3 b, vm.Vector3 d2, vm.Vector3 e,
      vm.Matrix4 vp, double w, double h, Color col) {
    _fillPoly(c, [a, b, d2, e], vp, w, h, col);
  }

  @override
  bool shouldRepaint(covariant _Model3DPainter o) => true;
}

// ── 连接弹窗 ─────────────────────────────────────────────────
void showConnectSheet(BuildContext c) {
  final ip = TextEditingController(text: appState.ip);
  final port = TextEditingController(text: appState.port.toString());
  showModalBottomSheet(
    context: c,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (_) => Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('连接电脑端软件', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          TextField(controller: ip, decoration: const InputDecoration(labelText: '电脑 IP', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          TextField(controller: port, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '端口（默认 5000）', border: OutlineInputBorder())),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF19B36B), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
              onPressed: () {
                appState.ip = ip.text.trim();
                appState.port = int.tryParse(port.text.trim()) ?? 5000;
                appState.connect();
                Navigator.of(c).pop();
              },
              child: const Text('连接'),
            ),
          ),
        ],
      ),
    ),
  );
}
