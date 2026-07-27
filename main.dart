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
        primaryColor: const Color(0xFFFF6B00),
        scaffoldBackgroundColor: const Color(0xFF0D0E12),
        cardColor: const Color(0xFF16181F),
        appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF12141B), elevation: 0),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Color(0xFF12141B),
          selectedItemColor: Color(0xFFFF6B00),
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
  
  // Machine State Telemetry
  String _machineStatus = 'IDLE'; // IDLE, RUN, ALARM, HOLD
  bool _isLanMode = true;
  bool _isDoorClosed = true;
  bool _isLightOn = true;
  bool _isAirBlastOn = false;
  bool _isDustCollectorOn = false;
  
  // Motion Telemetry
  double _xPos = 120.450, _yPos = 85.200, _zPos = -12.500, _aPos = 0.00;
  double _feedrateOverride = 100; // 10% - 200%
  double _spindleOverride = 100;  // 50% - 150%
  int _currentTool = 1;
  
  // Job Exec State
  bool _isExecutingJob = false;
  double _jobProgress = 0.42;

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
                MonitorView(
                  isLightOn: _isLightOn,
                  onToggleLight: () => setState(() => _isLightOn = !_isLightOn),
                ),
                MotionControlView(
                  x: _xPos, y: _yPos, z: _zPos, a: _aPos,
                  isLanMode: _isLanMode,
                  currentTool: _currentTool,
                  airOn: _isAirBlastOn,
                  dustOn: _isDustCollectorOn,
                  onUpdateCoords: (nx, ny, nz) => setState(() {
                    _xPos = nx; _yPos = ny; _zPos = nz;
                  }),
                  onSelectTool: (t) => setState(() => _currentTool = t),
                  onToggleAir: () => setState(() => _isAirBlastOn = !_isAirBlastOn),
                  onToggleDust: () => setState(() => _isDustCollectorOn = !_isDustCollectorOn),
                ),
                JobStudioView(
                  isExecuting: _isExecutingJob,
                  progress: _jobProgress,
                  onStartJob: () => setState(() {
                    _isExecutingJob = true;
                    _machineStatus = 'RUN';
                  }),
                  onStopJob: () => setState(() {
                    _isExecutingJob = false;
                    _machineStatus = 'IDLE';
                  }),
                ),
                const TerminalMacroView(),
              ],
            ),
          ),
          _buildOverrideControlBar(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tabIndex,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
        unselectedLabelStyle: const TextStyle(fontSize: 11),
        onTap: (i) => setState(() => _tabIndex = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.videocam_outlined), activeIcon: Icon(Icons.videocam), label: '实时监控'),
          BottomNavigationBarItem(icon: Icon(Icons.gamepad_outlined), activeIcon: Icon(Icons.gamepad), label: '轴控与刀仓'),
          BottomNavigationBarItem(icon: Icon(Icons.precision_manufacturing_outlined), activeIcon: Icon(Icons.precision_manufacturing), label: '任务与CAM'),
          BottomNavigationBarItem(icon: Icon(Icons.terminal_outlined), activeIcon: Icon(Icons.terminal), label: '终端与宏'),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildTopAppBar() {
    return AppBar(
      titleSpacing: 12,
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFFF6B00).withOpacity(0.15),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFFFF6B00)),
            ),
            child: const Text('SMART CNC 3020', style: TextStyle(color: Color(0xFFFF6B00), fontSize: 12, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: _openPairingModal,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _isLanMode ? Colors.green.withOpacity(0.15) : Colors.orange.withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: _isLanMode ? Colors.greenAccent : Colors.orangeAccent),
              ),
              child: Row(
                children: [
                  Icon(Icons.wifi, size: 12, color: _isLanMode ? Colors.greenAccent : Colors.orangeAccent),
                  const SizedBox(width: 4),
                  Text(_isLanMode ? 'LAN 直连 (1ms)' : 'WAN 远程 (45ms)', style: TextStyle(fontSize: 11, color: _isLanMode ? Colors.greenAccent : Colors.orangeAccent, fontWeight: FontWeight.bold)),
                  const Icon(Icons.arrow_drop_down, size: 12, color: Colors.white54),
                ],
              ),
            ),
          ),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: () => _showESTOPDialog(context),
            icon: const Icon(Icons.dangerous, color: Colors.white, size: 16),
            label: const Text('急停 E-STOP', style: TextStyle(fontWeight: FontWeight.black, fontSize: 11)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade800,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlobalStatusHeader() {
    Color statusBg = _machineStatus == 'RUN' ? Colors.green.shade900 : (_machineStatus == 'ALARM' ? Colors.red.shade900 : const Color(0xFF1E212B));
    return Container(
      color: statusBg,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 8, height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _machineStatus == 'RUN' ? Colors.greenAccent : (_machineStatus == 'ALARM' ? Colors.redAccent : Colors.amberAccent),
                ),
              ),
              const SizedBox(width: 6),
              Text('状态: $_machineStatus', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(width: 16),
              InkWell(
                onTap: () => setState(() => _isDoorClosed = !_isDoorClosed),
                child: Row(
                  children: [
                    Icon(_isDoorClosed ? Icons.shield : Icons.warning, size: 14, color: _isDoorClosed ? Colors.white60 : Colors.redAccent),
                    const SizedBox(width: 4),
                    Text(_isDoorClosed ? '防护罩门: 闭合' : '警告: 防护罩门已打开!', style: TextStyle(color: _isDoorClosed ? Colors.white60 : Colors.redAccent, fontSize: 11, fontWeight: _isDoorClosed ? FontWeight.normal : FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),
          Text('主轴: ${_isExecutingJob ? "12000 RPM" : "0 RPM"} | 24.5°C', style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildOverrideControlBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: const BoxDecoration(
        color: Color(0xFF12141B),
        border: Border(top: BorderSide(color: Colors.white10)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                const Text('进给倍率:', style: TextStyle(color: Colors.white60, fontSize: 10)),
                Expanded(
                  child: Slider(
                    value: _feedrateOverride,
                    min: 10, max: 200, divisions: 19,
                    activeColor: const Color(0xFFFF6B00),
                    onChanged: (v) => setState(() => _feedrateOverride = v),
                  ),
                ),
                Text('${_feedrateOverride.toInt()}%', style: const TextStyle(color: Color(0xFFFF6B00), fontSize: 10, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Row(
              children: [
                const Text('主轴倍率:', style: TextStyle(color: Colors.white60, fontSize: 10)),
                Expanded(
                  child: Slider(
                    value: _spindleOverride,
                    min: 50, max: 150, divisions: 10,
                    activeColor: Colors.cyanAccent,
                    onChanged: (v) => setState(() => _spindleOverride = v),
                  ),
                ),
                Text('${_spindleOverride.toInt()}%', style: const TextStyle(color: Colors.cyanAccent, fontSize: 10, fontWeight: FontWeight.bold)),
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
        backgroundColor: const Color(0xFF2A1212),
        title: const Text('🚨 确认下发急停指令?', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
        content: const Text('下位机驱动器将立即物理切断电源，全轴电磁锁死！'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消', style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {
                _machineStatus = 'ALARM';
                _isExecutingJob = false;
              });
            },
            child: const Text('确认紧急切断', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 配网与设备连接弹窗向导 (Connection & Pairing Wizard)
// -----------------------------------------------------------------------------
class DevicePairingModal extends StatefulWidget {
  const DevicePairingModal({Key? key}) : super(key: key);

  @override
  State<DevicePairingModal> createState() => _DevicePairingModalState();
}

class _DevicePairingModalState extends State<DevicePairingModal> {
  int _step = 0; // 0: 扫描蓝牙, 1: 配置Wi-Fi, 2: 绑定成功
  bool _isScanning = false;
  String? _selectedDevice;
  final TextEditingController _wifiSsidController = TextEditingController(text: "MyHome_WiFi_2.4G");
  final TextEditingController _wifiPassController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Color(0xFF16181F),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('设备连接与蓝牙配网向导', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: Colors.white54)),
            ],
          ),
          const Divider(color: Colors.white10),
          Expanded(
            child: _step == 0
                ? _buildBluetoothScanStep()
                : (_step == 1 ? _buildWifiConfigStep() : _buildSuccessStep()),
          ),
        ],
      ),
    );
  }

  Widget _buildBluetoothScanStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('步骤 1/3: 确保 CNC 机器已通电，开启手机蓝牙', style: TextStyle(color: Colors.white70, fontSize: 12)),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: () async {
            setState(() => _isScanning = true);
            await Future.delayed(const Duration(seconds: 2));
            setState(() {
              _isScanning = false;
              _selectedDevice = "SmartCNC-3020-A88F";
            });
          },
          icon: _isScanning
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.bluetooth_searching, size: 16),
          label: Text(_isScanning ? '正在扫描附近 BLE 广播...' : '开始扫描附近 CNC 设备'),
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF6B00), minimumSize: const Size(double.infinity, 42)),
        ),
        const SizedBox(height: 16),
        if (_selectedDevice != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.greenAccent)),
            child: Row(
              children: [
                const Icon(Icons.precision_manufacturing, color: Colors.greenAccent),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_selectedDevice!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                      const Text('信号强度: 强 (-45dBm) | 待配网', style: TextStyle(color: Colors.white54, fontSize: 10)),
                    ],
                  ),
                ),
                ElevatedButton(
                  onPressed: () => setState(() => _step = 1),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade800),
                  child: const Text('连接', style: TextStyle(fontSize: 11)),
                ),
              ],
            ),
          )
        ],
      ],
    );
  }

  Widget _buildWifiConfigStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('步骤 2/3: 选择工作区 2.4GHz Wi-Fi 下发配置', style: TextStyle(color: Colors.white70, fontSize: 12)),
        const SizedBox(height: 12),
        TextField(
          controller: _wifiSsidController,
          style: const TextStyle(color: Colors.white, fontSize: 12),
          decoration: const InputDecoration(labelText: 'Wi-Fi 名称 (SSID)', labelStyle: TextStyle(color: Colors.white54, fontSize: 12), filled: true, fillColor: Colors.black26),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _wifiPassController,
          obscureText: true,
          style: const TextStyle(color: Colors.white, fontSize: 12),
          decoration: const InputDecoration(labelText: 'Wi-Fi 密码', labelStyle: TextStyle(color: Colors.white54, fontSize: 12), filled: true, fillColor: Colors.black26),
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: () => setState(() => _step = 2),
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF6B00), minimumSize: const Size(double.infinity, 42)),
          child: const Text('发送配置并绑定账号', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Widget _buildSuccessStep() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.check_circle_outline, color: Colors.greenAccent, size: 60),
        const SizedBox(height: 12),
        const Text('设备配网与账号绑定成功！', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 6),
        const Text('当前已建立 WebSocket 局域网直连 (1ms 低延迟)', style: TextStyle(color: Colors.white54, fontSize: 11)),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF6B00), minimumSize: const Size(200, 40)),
          child: const Text('进入控制终端'),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// 1. 实时监控看板
// -----------------------------------------------------------------------------
class MonitorView extends StatelessWidget {
  final bool isLightOn;
  final VoidCallback onToggleLight;

  const MonitorView({Key? key, required this.isLightOn, required this.onToggleLight}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white12),
              ),
              child: Stack(
                children: [
                  const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.videocam_outlined, size: 40, color: Colors.cyanAccent),
                        SizedBox(height: 6),
                        Text('龙门架侧视角 1080P 高帧率实时流', style: TextStyle(color: Colors.white54, fontSize: 12)),
                      ],
                    ),
                  ),
                  Positioned(
                    top: 10, left: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: Colors.red.shade800, borderRadius: BorderRadius.circular(4)),
                      child: const Text('● LIVE', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  Positioned(
                    bottom: 10, right: 10,
                    child: ElevatedButton.icon(
                      onPressed: onToggleLight,
                      icon: Icon(Icons.lightbulb, size: 14, color: isLightOn ? Colors.yellowAccent : Colors.white60),
                      label: Text(isLightOn ? '舱灯: 开启' : '舱灯: 关闭', style: const TextStyle(fontSize: 10)),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.black87),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF16181F),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('实时串口日志 (GRBL Realtime Stream)', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
                  const Divider(color: Colors.white10, height: 12),
                  Expanded(
                    child: ListView(
                      children: const [
                        Text('[14:22:01] <Idle|MPos:120.450,85.200,-12.500|FS:0,0|WCO:0.000,0.000,0.000>', style: TextStyle(color: Colors.greenAccent, fontSize: 10, fontFamily: 'monospace')),
                        Text('[14:22:02] M3 S12000 (Spindle Target Reached)', style: TextStyle(color: Colors.white60, fontSize: 10, fontFamily: 'monospace')),
                        Text('[14:22:03] G1 X125.0 Y90.0 F1200 (Feedrate Nominal)', style: TextStyle(color: Colors.white60, fontSize: 10, fontFamily: 'monospace')),
                        Text('[14:22:05] Status Check: Door Safety Switch CLOSED [OK]', style: TextStyle(color: Colors.cyanAccent, fontSize: 10, fontFamily: 'monospace')),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 2. 轴控与刀仓视图
// -----------------------------------------------------------------------------
class MotionControlView extends StatefulWidget {
  final double x, y, z, a;
  final bool isLanMode;
  final int currentTool;
  final bool airOn, dustOn;
  final Function(double, double, double) onUpdateCoords;
  final Function(int) onSelectTool;
  final VoidCallback onToggleAir, onToggleDust;

  const MotionControlView({
    Key? key,
    required this.x, required this.y, required this.z, required this.a,
    required this.isLanMode,
    required this.currentTool,
    required this.airOn, required this.dustOn,
    required this.onUpdateCoords,
    required this.onSelectTool,
    required this.onToggleAir, required this.onToggleDust,
  }) : super(key: key);

  @override
  State<MotionControlView> createState() => _MotionControlViewState();
}

class _MotionControlViewState extends State<MotionControlView> {
  double _step = 1.0;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          _buildDROCard(),
          const SizedBox(height: 12),
          _buildJogControlPad(),
          const SizedBox(height: 12),
          _buildATCToolSection(),
          const SizedBox(height: 12),
          _buildAuxRelaySection(),
        ],
      ),
    );
  }

  Widget _buildDROCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFF16181F), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white10)),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('DRO 坐标读出 (WCS G54)', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
              ElevatedButton(
                onPressed: () => widget.onUpdateCoords(0, 0, 0),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF6B00), padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
                child: const Text('全轴清零 (Set Zero)', style: TextStyle(fontSize: 10, color: Colors.white)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildAxisItem('X', widget.x, Colors.redAccent),
              _buildAxisItem('Y', widget.y, Colors.greenAccent),
              _buildAxisItem('Z', widget.z, Colors.blueAccent),
              _buildAxisItem('A', widget.a, Colors.amberAccent),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAxisItem(String axis, double val, Color color) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(6)),
        child: Column(
          children: [
            Text(axis, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 11)),
            Text(val.toStringAsFixed(3), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
          ],
        ),
      ),
    );
  }

  Widget _buildJogControlPad() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFF16181F), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white10)),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Jog 点动控制', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
              Row(
                children: [0.01, 0.1, 1.0, 10.0].map((s) {
                  bool sel = _step == s;
                  return GestureDetector(
                    onTap: () => setState(() => _step = s),
                    child: Container(
                      margin: const EdgeInsets.only(left: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: sel ? const Color(0xFFFF6B00) : Colors.white10, borderRadius: BorderRadius.circular(4)),
                      child: Text('${s}mm', style: TextStyle(color: sel ? Colors.black : Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              SizedBox(
                width: 130, height: 130,
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
                  const SizedBox(height: 8),
                  _jogBtn('Z-', () => widget.onUpdateCoords(widget.x, widget.y, widget.z - _step)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _jogBtn(String label, VoidCallback onPressed) {
    return ElevatedButton(
      onPressed: widget.isLanMode ? onPressed : null,
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF252834),
        minimumSize: const Size(38, 38),
        padding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      child: Text(label, style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildATCToolSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFF16181F), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('ATC 气动自动换刀仓', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
            children: [
              _toolSlotItem(1, '3.175平刀'),
              _toolSlotItem(2, '60°V型刀'),
              _toolSlotItem(3, '2.0球头刀'),
              _toolSlotItem(4, '自动对刀块'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _toolSlotItem(int slot, String name) {
    bool active = widget.currentTool == slot;
    return Expanded(
      child: GestureDetector(
        onTap: () => widget.onSelectTool(slot),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            color: active ? const Color(0xFFFF6B00).withOpacity(0.2) : Colors.black26,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: active ? const Color(0xFFFF6B00) : Colors.white10),
          ),
          child: Column(
            children: [
              Text('T$slot', style: TextStyle(color: active ? const Color(0xFFFF6B00) : Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
              Text(name, style: const TextStyle(color: Colors.white54, fontSize: 9)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAuxRelaySection() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: widget.onToggleAir,
            icon: Icon(Icons.air, size: 14, color: widget.airOn ? Colors.cyanAccent : Colors.white60),
            label: Text(widget.airOn ? '切削吹气: 开' : '切削吹气: 关', style: const TextStyle(fontSize: 10)),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF16181F)),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: widget.onToggleDust,
            icon: Icon(Icons.cleaning_services, size: 14, color: widget.dustOn ? Colors.amberAccent : Colors.white60),
            label: Text(widget.dustOn ? '吸尘收集: 开' : '吸尘收集: 关', style: const TextStyle(fontSize: 10)),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF16181F)),
          ),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// 3. 任务与 CAM 视图
// -----------------------------------------------------------------------------
class JobStudioView extends StatelessWidget {
  final bool isExecuting;
  final double progress;
  final VoidCallback onStartJob, onStopJob;

  const JobStudioView({
    Key? key,
    required this.isExecuting,
    required this.progress,
    required this.onStartJob,
    required this.onStopJob,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isExecuting) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFF16181F), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFFF6B00))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('正在执行: 《铝合金散热壳加工.gcode》', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                      Text('${(progress * 100).toInt()}%', style: const TextStyle(color: Color(0xFFFF6B00), fontWeight: FontWeight.black, fontSize: 16)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(value: progress, backgroundColor: Colors.white10, color: const Color(0xFFFF6B00)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: const [
                      Text('预计剩余: 08:35', style: TextStyle(color: Colors.white54, fontSize: 10)),
                      Text('当前行: 1,420 / 3,800', style: TextStyle(color: Colors.white54, fontSize: 10)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: onStopJob,
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade900),
                      child: const Text('终止任务 (Abort Job)', style: TextStyle(fontSize: 11)),
                    ),
                  )
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          const Text('云端模型工程库', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              children: [
                _jobCard('铝合金散热壳加工.gcode', '100 × 60 × 15 mm', '刀具: T1 (3.175mm)', onStartJob),
                _jobCard('木质榫卯手机支架.nc', '150 × 80 × 12 mm', '刀具: T1, T2', onStartJob),
                _jobCard('PCB 雕刻电路板_V2.tap', '80 × 50 × 1.6 mm', '刀具: T2 (V型刀)', onStartJob),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _jobCard(String title, String size, String tools, VoidCallback onStart) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: const Color(0xFF16181F), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white10)),
      child: Row(
        children: [
          const Icon(Icons.description_outlined, color: Color(0xFFFF6B00), size: 28),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                Text('尺寸: $size | $tools', style: const TextStyle(color: Colors.white54, fontSize: 10)),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: onStart,
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF6B00), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
            child: const Text('开始加工', style: TextStyle(fontSize: 10, color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 4. 终端与宏视图
// -----------------------------------------------------------------------------
class TerminalMacroView extends StatelessWidget {
  const TerminalMacroView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('快捷加工宏 (Preset Macros)', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
            children: [
              _macroBtn(context, '🎯 自动Z轴对刀', 'G38.2 Z-20 F50; G92 Z10'),
              const SizedBox(width: 6),
              _macroBtn(context, '📐 激光红光循边', 'M3 S10; G0 X0 Y0...'),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _macroBtn(context, '扫平工作台面', 'G0 Z5; G1 F1500...'),
              const SizedBox(width: 6),
              _macroBtn(context, '🏠 机械归零 (\$H)', '\$H'),
            ],
          ),
          const SizedBox(height: 12),
          const Text('GRBL 指令控制台 Console', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.white10)),
              child: const SingleChildScrollView(
                child: Text(
                  '> \$100=250.000 (x, step/mm)\n> \$101=250.000 (y, step/mm)\n> \$102=400.000 (z, step/mm)\n> ok',
                  style: TextStyle(color: Colors.greenAccent, fontSize: 10, fontFamily: 'monospace'),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  decoration: InputDecoration(
                    hintText: '输入 G-Code 或 \$ 命令...',
                    hintStyle: const TextStyle(color: Colors.white30, fontSize: 11),
                    filled: true,
                    fillColor: const Color(0xFF16181F),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              ElevatedButton(
                onPressed: () {},
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF6B00)),
                child: const Text('发送', style: TextStyle(fontSize: 11, color: Colors.white)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _macroBtn(BuildContext context, String name, String cmd) {
    return Expanded(
      child: ElevatedButton(
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已下发宏指令: $name'), duration: const Duration(seconds: 1)));
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF16181F),
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.centerLeft,
        ),
        child: Text(name, style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }
}
