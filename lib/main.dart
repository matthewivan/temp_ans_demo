import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';

void main() {
  runApp(const PolarH10DemoApp());
}

class PolarH10DemoApp extends StatelessWidget {
  const PolarH10DemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Polar H10 Demo',
      theme: ThemeData.dark(),
      home: const PolarHomePage(),
    );
  }
}

class PolarHomePage extends StatefulWidget {
  const PolarHomePage({super.key});

  @override
  State<PolarHomePage> createState() => _PolarHomePageState();
}

class _PolarHomePageState extends State<PolarHomePage> {
  // NATIVE CHANNELS
  static const MethodChannel _channel =
  MethodChannel('polar_h10_sdk/methods');

  static const EventChannel _ecgStream =
  EventChannel("polar_h10_sdk/ecg_stream");

  static const EventChannel _rrStream =
  EventChannel("polar_h10_sdk/rr_stream");

  static const EventChannel _accStream =
  EventChannel("polar_h10_sdk/acc_stream");

  // BUFFERS
  List<double> ecgBuffer = [];
  List<int> rrBuffer = [];
  List<Map<String, double>> accBuffer = [];

  StreamSubscription? ecgSub;
  StreamSubscription? rrSub;
  StreamSubscription? accSub;

  String _status = 'Idle';
  String? _deviceId;
  int? _lastHr;

  // -------------------------------------------------------------------------
  // DEVICE CONNECTION
  // -------------------------------------------------------------------------
  Future<void> _searchAndConnect() async {
    if (!Platform.isAndroid) {
      setState(() => _status = 'Android only');
      return;
    }

    setState(() => _status = 'Searching...');

    try {
      final id = await _channel.invokeMethod<String>('searchAndConnect');
      setState(() {
        _deviceId = id;
        _status = id != null ? "Connected to $id" : "Failed";
      });
    } catch (e) {
      setState(() => _status = "Connection Error: $e");
    }
  }

  Future<void> _getOneHrSample() async {
    try {
      final hr = await _channel.invokeMethod<int>('getOneHrSample');
      setState(() {
        _lastHr = hr;
        _status = "One HR sample: $hr bpm";
      });
    } catch (e) {
      setState(() => _status = "HR Sample Error: $e");
    }
  }

  // -------------------------------------------------------------------------
  // STREAMS
  // -------------------------------------------------------------------------

  Future<void> _startEcg() async {
    ecgSub?.cancel();
    ecgSub = _ecgStream.receiveBroadcastStream().listen((value) {
      final v = (value as num).toDouble();

      setState(() {
        ecgBuffer.add(v);
        if (ecgBuffer.length > 600) ecgBuffer.removeAt(0);
      });
    });
  }

  Future<void> _startHr() async {
    rrSub?.cancel();
    rrSub = _rrStream.receiveBroadcastStream().listen((event) {
      if (event is Map) {
        final rrList =
            (event["rr"] as List?)?.cast<int>() ?? [];
        final hrVal = event["hr"] as int?;

        setState(() {
          if (hrVal != null) _lastHr = hrVal;
          rrBuffer.addAll(rrList);
          if (rrBuffer.length > 200) {
            rrBuffer = rrBuffer.sublist(rrBuffer.length - 200);
          }
        });
      }
    });
  }

  Future<void> _startAcc() async {
    accSub?.cancel();
    accSub = _accStream.receiveBroadcastStream().listen((event) {
      if (event is Map) {
        setState(() {
          accBuffer.add({
            "x": (event["x"] as num).toDouble(),
            "y": (event["y"] as num).toDouble(),
            "z": (event["z"] as num).toDouble(),
          });

          if (accBuffer.length > 300) accBuffer.removeAt(0);
        });
      }
    });
  }

  // -------------------------------------------------------------------------
  // UI + GRAPHS
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Polar H10 SDK (Android)"),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Status: $_status"),
            Text("Device ID: ${_deviceId ?? "-"}"),
            Text("Last HR: ${_lastHr ?? "-"} bpm"),

            const SizedBox(height: 20),

            ElevatedButton(
              onPressed: _searchAndConnect,
              child: const Text("Search & Connect"),
            ),
            ElevatedButton(
              onPressed: _getOneHrSample,
              child: const Text("Get 1 HR Sample"),
            ),

            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _startEcg,
              child: const Text("Start ECG Stream"),
            ),
            ElevatedButton(
              onPressed: _startHr,
              child: const Text("Start RR/HR Stream"),
            ),
            ElevatedButton(
              onPressed: _startAcc,
              child: const Text("Start Accelerometer Stream"),
            ),

            const SizedBox(height: 25),

            // ECG Graph
            const Text("ECG Signal"),
            SizedBox(height: 180, child: EcgGraph(data: ecgBuffer)),
            const SizedBox(height: 20),

            // HR Graph
            const Text("Heart Rate"),
            SizedBox(height: 150, child: HrGraph(hr: _lastHr)),
            const SizedBox(height: 20),

            // RR Graph
            const Text("RR Intervals (Tachogram)"),
            SizedBox(height: 180, child: RrGraph(rr: rrBuffer)),
            const SizedBox(height: 20),

            // ACC Graph
            const Text("Accelerometer (XYZ)"),
            SizedBox(height: 180, child: AccGraph(data: accBuffer)),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    ecgSub?.cancel();
    rrSub?.cancel();
    accSub?.cancel();
    super.dispose();
  }
}

////////////////////////////////////////////////////////////////////////////////
// GRAPH WIDGETS
////////////////////////////////////////////////////////////////////////////////

// ---------------------------- ECG GRAPH ----------------------------
class EcgGraph extends StatelessWidget {
  final List<double> data;

  const EcgGraph({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return LineChart(
      LineChartData(
        minY: -4000,
        maxY: 4000,
        gridData: FlGridData(show: false),
        borderData: FlBorderData(show: true),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (int i = 0; i < data.length; i++)
                FlSpot(i.toDouble(), data[i])
            ],
            isCurved: false,
            color: Colors.red,
            barWidth: 1,
            dotData: FlDotData(show: false),
          ),
        ],
      ),
    );
  }
}

// ---------------------------- HEART RATE ----------------------------
class HrGraph extends StatelessWidget {
  final int? hr;

  const HrGraph({super.key, required this.hr});

  @override
  Widget build(BuildContext context) {
    final double v = (hr ?? 0).toDouble();

    return LineChart(
      LineChartData(
        minY: 40,
        maxY: 200,
        borderData: FlBorderData(show: true),
        gridData: FlGridData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: [FlSpot(0, v)],
            isCurved: false,
            barWidth: 6,
            color: Colors.orange,
            dotData: FlDotData(show: true),
          ),
        ],
      ),
    );
  }
}

// ---------------------------- RR INTERVAL GRAPH ----------------------------
class RrGraph extends StatelessWidget {
  final List<int> rr;

  const RrGraph({super.key, required this.rr});

  @override
  Widget build(BuildContext context) {
    return LineChart(
      LineChartData(
        minY: 300,
        maxY: 2000,
        borderData: FlBorderData(show: true),
        gridData: FlGridData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (int i = 0; i < rr.length; i++)
                FlSpot(i.toDouble(), rr[i].toDouble())
            ],
            color: Colors.blue,
            barWidth: 2,
            isCurved: false,
            dotData: FlDotData(show: false),
          ),
        ],
      ),
    );
  }
}

// ---------------------------- ACC GRAPH ----------------------------
class AccGraph extends StatelessWidget {
  final List<Map<String, double>> data;

  const AccGraph({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    List<FlSpot> x = [];
    List<FlSpot> y = [];
    List<FlSpot> z = [];

    for (int i = 0; i < data.length; i++) {
      x.add(FlSpot(i.toDouble(), data[i]["x"]!));
      y.add(FlSpot(i.toDouble(), data[i]["y"]!));
      z.add(FlSpot(i.toDouble(), data[i]["z"]!));
    }

    return LineChart(
      LineChartData(
        minY: -5000,
        maxY: 5000,
        borderData: FlBorderData(show: true),
        gridData: FlGridData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: x,
            color: Colors.red,
            barWidth: 2,
            dotData: FlDotData(show: false),
          ),
          LineChartBarData(
            spots: y,
            color: Colors.green,
            barWidth: 2,
            dotData: FlDotData(show: false),
          ),
          LineChartBarData(
            spots: z,
            color: Colors.blue,
            barWidth: 2,
            dotData: FlDotData(show: false),
          ),
        ],
      ),
    );
  }
}
