import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const InfantMonitorApp());
}

// ── App entry ──────────────────────────────────────────────────────────────
class InfantMonitorApp extends StatelessWidget {
  const InfantMonitorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Infant Monitor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4A90D9)),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      home: const MonitorScreen(),
    );
  }
}

// ── Data model ─────────────────────────────────────────────────────────────
class SensorData {
  final int raw;
  final int percentage;
  final String status;
  final bool isWet;
  final bool buzzerEnabled;
  final int wetEvents;
  final String lastChanged;
  final int wetDuration;
  final int uptime;

  SensorData({
    required this.raw,
    required this.percentage,
    required this.status,
    required this.isWet,
    required this.buzzerEnabled,
    required this.wetEvents,
    required this.lastChanged,
    required this.wetDuration,
    required this.uptime,
  });

  factory SensorData.fromJson(Map<String, dynamic> json) {
    return SensorData(
      raw:           json['raw']          ?? 0,
      percentage:    json['percentage']   ?? 0,
      status:        json['status']       ?? 'UNKNOWN',
      isWet:         json['isWet']        ?? false,
      buzzerEnabled: json['buzzerEnabled']?? true,
      wetEvents:     json['wetEvents']    ?? 0,
      lastChanged:   json['lastChanged']  ?? 'Never',
      wetDuration:   json['wetDuration']  ?? 0,
      uptime:        json['uptime']       ?? 0,
    );
  }
}

// ── History log entry ──────────────────────────────────────────────────────
class LogEntry {
  final String time;
  final String event;
  final String value;
  LogEntry(this.time, this.event, this.value);
}

// ── Main screen ────────────────────────────────────────────────────────────
class MonitorScreen extends StatefulWidget {
  const MonitorScreen({super.key});

  @override
  State<MonitorScreen> createState() => _MonitorScreenState();
}

class _MonitorScreenState extends State<MonitorScreen>
    with TickerProviderStateMixin {
  // Config
  static const String _baseUrl = 'http://192.168.4.1';
  static const Duration _pollInterval = Duration(seconds: 2);

  // State
  SensorData? _data;
  String _connectionStatus = 'Connecting...';
  bool _connected = false;
  bool _loading = true;
  final List<LogEntry> _log = [];
  String? _lastKnownStatus;
  Timer? _pollTimer;

  // Animation
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _startPolling();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  // ── Polling ──────────────────────────────────────────────────────────────
  void _startPolling() {
    _fetchData();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _fetchData());
  }

  Future<void> _fetchData() async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/data'))
          .timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final newData = SensorData.fromJson(json);

        // Log state transitions
        if (_lastKnownStatus != null && _lastKnownStatus != newData.status) {
          _addLog(
            newData.status == 'WET' ? 'WET detected' : 'Back to DRY',
            'Raw: ${newData.raw}',
          );
        }
        _lastKnownStatus = newData.status;

        setState(() {
          _data = newData;
          _connected = true;
          _loading = false;
          _connectionStatus = 'Connected · 192.168.4.1';
        });
      } else {
        _setDisconnected();
      }
    } catch (_) {
      _setDisconnected();
    }
  }

  void _setDisconnected() {
    setState(() {
      _connected = false;
      _loading = false;
      _connectionStatus = 'No connection — join "InfantMonitor" WiFi';
    });
  }

  void _addLog(String event, String value) {
    final now = TimeOfDay.now();
    final time = '${now.hour.toString().padLeft(2, '0')}:'
                 '${now.minute.toString().padLeft(2, '0')}';
    setState(() {
      _log.insert(0, LogEntry(time, event, value));
      if (_log.length > 50) _log.removeLast();
    });
  }

  // ── Toggle buzzer ─────────────────────────────────────────────────────────
  Future<void> _toggleBuzzer() async {
    if (_data == null) return;
    final enable = !_data!.buzzerEnabled;
    try {
      await http
          .get(Uri.parse('$_baseUrl/buzzer?enable=$enable'))
          .timeout(const Duration(seconds: 3));
      await _fetchData();
    } catch (_) {}
  }

  // ── Reset counters ────────────────────────────────────────────────────────
  Future<void> _resetCounters() async {
    try {
      await http
          .get(Uri.parse('$_baseUrl/reset'))
          .timeout(const Duration(seconds: 3));
      _log.clear();
      await _fetchData();
    } catch (_) {}
  }

  // ── UI helpers ────────────────────────────────────────────────────────────
  String _formatUptime(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    return '${h}h ${m}m ${s}s';
  }

  Color get _statusColor =>
      (_data?.isWet ?? false) ? const Color(0xFFE53935) : const Color(0xFF43A047);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Infant Monitor',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchData,
            tooltip: 'Refresh now',
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'reset') _resetCounters();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'reset', child: Text('Reset counters')),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetchData,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildConnectionBadge(),
                  const SizedBox(height: 16),
                  if (_data != null) ...[
                    _buildStatusCard(),
                    const SizedBox(height: 12),
                    _buildMetricsRow(),
                    const SizedBox(height: 12),
                    _buildSensorBar(),
                    const SizedBox(height: 12),
                    _buildControlsCard(),
                    const SizedBox(height: 12),
                    _buildLogCard(),
                  ],
                ],
              ),
            ),
    );
  }

  // ── Connection badge ──────────────────────────────────────────────────────
  Widget _buildConnectionBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _connected
            ? const Color(0xFFE8F5E9)
            : const Color(0xFFFFEBEE),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            _connected ? Icons.wifi : Icons.wifi_off,
            size: 16,
            color: _connected
                ? const Color(0xFF2E7D32)
                : const Color(0xFFC62828),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _connectionStatus,
              style: TextStyle(
                fontSize: 13,
                color: _connected
                    ? const Color(0xFF2E7D32)
                    : const Color(0xFFC62828),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Big status card ───────────────────────────────────────────────────────
  Widget _buildStatusCard() {
    final wet = _data!.isWet;
    return ScaleTransition(
      scale: wet ? _pulseAnim : const AlwaysStoppedAnimation(1.0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 32),
        decoration: BoxDecoration(
          color: wet ? const Color(0xFFFFEBEE) : const Color(0xFFE8F5E9),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: wet ? const Color(0xFFEF9A9A) : const Color(0xFFA5D6A7),
            width: 1.5,
          ),
        ),
        child: Column(
          children: [
            Icon(
              wet ? Icons.water_drop : Icons.check_circle,
              size: 64,
              color: _statusColor,
            ),
            const SizedBox(height: 12),
            Text(
              wet ? 'WET — Change diaper now!' : 'DRY — All good',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: _statusColor,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              wet
                  ? 'Wet for ${_data!.wetDuration}s · Event #${_data!.wetEvents}'
                  : 'Last changed: ${_data!.lastChanged}',
              style: const TextStyle(fontSize: 13, color: Color(0xFF757575)),
            ),
          ],
        ),
      ),
    );
  }

  // ── Metrics row ───────────────────────────────────────────────────────────
  Widget _buildMetricsRow() {
    return Row(
      children: [
        _metricCard('Raw value', '${_data!.raw}', Icons.sensors),
        const SizedBox(width: 10),
        _metricCard('Moisture', '${_data!.percentage}%', Icons.water),
        const SizedBox(width: 10),
        _metricCard('Wet events', '${_data!.wetEvents}', Icons.history),
        const SizedBox(width: 10),
        _metricCard('Uptime', _formatUptime(_data!.uptime), Icons.timer),
      ],
    );
  }

  Widget _metricCard(String label, String value, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE0E0E0)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: const Color(0xFF4A90D9)),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(fontSize: 10, color: Color(0xFF9E9E9E)),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ── Sensor bar ────────────────────────────────────────────────────────────
  Widget _buildSensorBar() {
    final pct = (_data!.percentage / 100).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Moisture level',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 14,
              backgroundColor: const Color(0xFFE0E0E0),
              valueColor: AlwaysStoppedAnimation<Color>(_statusColor),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('0', style: TextStyle(fontSize: 11, color: Color(0xFF9E9E9E))),
              Text(
                '${_data!.percentage}%',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _statusColor,
                ),
              ),
              const Text('100', style: TextStyle(fontSize: 11, color: Color(0xFF9E9E9E))),
            ],
          ),
        ],
      ),
    );
  }

  // ── Controls card ─────────────────────────────────────────────────────────
  Widget _buildControlsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Controls',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _toggleBuzzer,
                  icon: Icon(
                    _data!.buzzerEnabled ? Icons.volume_up : Icons.volume_off,
                  ),
                  label: Text(
                    _data!.buzzerEnabled ? 'Buzzer ON' : 'Buzzer OFF',
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _data!.buzzerEnabled
                        ? const Color(0xFF4A90D9)
                        : const Color(0xFF9E9E9E),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _resetCounters,
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('Reset log'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF757575),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Event log card ────────────────────────────────────────────────────────
  Widget _buildLogCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Event log',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          if (_log.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text(
                  'No events yet — monitoring active',
                  style: TextStyle(fontSize: 13, color: Color(0xFF9E9E9E)),
                ),
              ),
            )
          else
            ..._log.take(10).map(
              (entry) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Text(
                      entry.time,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF9E9E9E),
                        fontFamily: 'monospace',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: entry.event.contains('WET')
                            ? const Color(0xFFE53935)
                            : const Color(0xFF43A047),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        entry.event,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    Text(
                      entry.value,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF9E9E9E),
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
