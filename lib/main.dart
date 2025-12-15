import 'recording_manager.dart';

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
  final recorder = RecordingManager();
  bool recording = false;

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
  List<int> hrBuffer = []; // <-- FIX: continuous HR history

  StreamSubscription? ecgSub;
  StreamSubscription? rrSub;
  StreamSubscription? accSub;

  String _status = 'Idle';
  String? _deviceId;

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

      if (recording) recorder.writeEcg(v.toInt());

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
        final rrList = (event["rr"] as List?)?.cast<int>() ?? [];
        final hrVal = event["hr"] as int?;

        if (recording) {
          recorder.writeRr(rrList, hrVal ?? 0);
          if (hrVal != null) recorder.writeHr(hrVal);
        }

        setState(() {
          rrBuffer.addAll(rrList);
          if (rrBuffer.length > 200) {
            rrBuffer = rrBuffer.sublist(rrBuffer.length - 200);
          }

          if (hrVal != null) {
            hrBuffer.add(hrVal);
            if (hrBuffer.length > 200) {
              hrBuffer = hrBuffer.sublist(hrBuffer.length - 200);
            }
          }
        });
      }
    });
  }

  Future<void> _startAcc() async {
    accSub?.cancel();
    accSub = _accStream.receiveBroadcastStream().listen((event) {
      if (event is Map) {
        final x = (event["x"] as num?)?.toDouble();
        final y = (event["y"] as num?)?.toDouble();
        final z = (event["z"] as num?)?.toDouble();

        if (recording && x != null && y != null && z != null) {
          recorder.writeAcc(x, y, z);
        }

        setState(() {
          accBuffer.add({
            "x": x ?? 0.0,
            "y": y ?? 0.0,
            "z": z ?? 0.0,
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
      appBar: AppBar(title: const Text("Polar H10 SDK (Android)")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Status: $_status"),
            Text("Device ID: ${_deviceId ?? "-"}"),

            const SizedBox(height: 20),

            ElevatedButton(
              onPressed: _searchAndConnect,
              child: const Text("Search & Connect"),
            ),
            ElevatedButton(
              onPressed: _getOneHrSample,
              child: const Text("Get 1 HR Sample"),
            ),

            ElevatedButton(
              onPressed: () async {
                await recorder.startRecording({
                  "patient_id": "P01",
                  "notes": "Test recording",
                  "device_id": _deviceId,
                  "start_time": DateTime.now().toIso8601String(),
                });
                setState(() => recording = true);
              },
              child: const Text("Start Recording"),
            ),

            ElevatedButton(
              onPressed: () async {
                await recorder.stopRecording();
                setState(() => recording = false);
              },
              child: const Text("Stop Recording"),
            ),

            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const RecordingListPage()),
                );
              },
              child: const Text("View Saved Recordings"),
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

            const SizedBox(height: 30),

            const Text("ECG Signal"),
            SizedBox(height: 180, child: EcgGraph(data: ecgBuffer)),
            const SizedBox(height: 20),

            const Text("Heart Rate (Continuous)"),
            SizedBox(height: 180, child: HrGraph(hrList: hrBuffer)),
            const SizedBox(height: 20),

            const Text("RR Intervals"),
            SizedBox(height: 180, child: RrGraph(rr: rrBuffer)),
            const SizedBox(height: 20),

            const Text("Accelerometer"),
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

// ---------------------------- HEART RATE GRAPH ----------------------------
class HrGraph extends StatelessWidget {
  final List<int> hrList;

  const HrGraph({super.key, required this.hrList});

  @override
  Widget build(BuildContext context) {
    if (hrList.isEmpty) {
      return const Center(child: Text("No HR data"));
    }

    return LineChart(
      LineChartData(
        minY: 40,
        maxY: 200,
        borderData: FlBorderData(show: true),
        gridData: FlGridData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (int i = 0; i < hrList.length; i++)
                FlSpot(i.toDouble(), hrList[i].toDouble())
            ],
            isCurved: true,
            barWidth: 2,
            color: Colors.orange,
            dotData: FlDotData(show: false),
          ),
        ],
      ),
    );
  }
}

// ---------------------------- RR GRAPH ----------------------------
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

////////////////////////////////////////////////////////////////////////////////
// RECORDING LIST + REPLAY PAGES
////////////////////////////////////////////////////////////////////////////////

class RecordingListPage extends StatefulWidget {
  const RecordingListPage({super.key});

  @override
  State<RecordingListPage> createState() => _RecordingListPageState();
}

class _RecordingListPageState extends State<RecordingListPage> {
  final recorder = RecordingManager();
  List<Directory> sessions = [];

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    sessions = await recorder.listRecordings();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Saved Recordings")),
      body: ListView(
        children: [
          for (final dir in sessions)
            ListTile(
              title: Text(dir.path.split("/").last),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ReplayPage(folder: dir.path),
                  ),
                );
              },
            )
        ],
      ),
    );
  }
}

class ReplayPage extends StatefulWidget {
  final String folder;
  const ReplayPage({super.key, required this.folder});

  @override
  State<ReplayPage> createState() => _ReplayPageState();
}

class _ReplayPageState extends State<ReplayPage> {
  final recorder = RecordingManager();

  List<double> ecg = [];
  List<int> rr = [];
  List<int> hr = [];
  List<Map<String, double>> acc = [];
  Map<String, dynamic>? metadata;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final data = await recorder.loadRecording(widget.folder);

    metadata = data["metadata"];

    ecg = data["ecg"]
        .map<double>((line) => double.parse(line.split(",")[1]))
        .toList();

    rr = data["rr"]
        .map<int>((line) => int.parse(line.split(",")[1]))
        .toList();

    acc = data["acc"].map<Map<String, double>>((line) {
      final parts = line.split(",");
      return {
        "x": double.parse(parts[1]),
        "y": double.parse(parts[2]),
        "z": double.parse(parts[3]),
      };
    }).toList();

    hr = data["hr"]
        .map<int>((line) => int.parse(line.split(",")[1]))
        .toList();

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (metadata == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Replay Recording")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text("Metadata:"),
          Text(metadata.toString()),

          const SizedBox(height: 20),

          const Text("ECG"),
          SizedBox(height: 180, child: EcgGraph(data: ecg)),

          const SizedBox(height: 20),

          const Text("RR Intervals"),
          SizedBox(height: 180, child: RrGraph(rr: rr)),

          const SizedBox(height: 20),

          const Text("Heart Rate"),
          SizedBox(height: 180, child: HrGraph(hrList: hr)),

          const SizedBox(height: 20),

          const Text("ACC"),
          SizedBox(height: 180, child: AccGraph(data: acc)),
        ],
      ),
    );
  }
}
