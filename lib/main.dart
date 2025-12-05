import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  static const _channel = MethodChannel('polar_h10_sdk/methods');
  static const _ecgStream = EventChannel("polar_h10_sdk/ecg_stream");
  static const _rrStream = EventChannel("polar_h10_sdk/rr_stream");
  static const _accStream = EventChannel("polar_h10_sdk/acc_stream");

  List<double> ecgBuffer = [];
  List<int> rrBuffer = [];
  List<Map<String, double>> accBuffer = [];

  StreamSubscription? ecgSub;
  StreamSubscription? rrSub;
  StreamSubscription? accSub;

  String _status = 'Idle';
  String? _deviceId;
  int? _lastHr;

  // -----------------------------------------------------
  // DEVICE CONNECTION
  // -----------------------------------------------------
  Future<void> _searchAndConnect() async {
    if (!Platform.isAndroid) {
      setState(() => _status = 'Android only demo');
      return;
    }

    setState(() => _status = 'Searching & connecting...');

    try {
      final id = await _channel.invokeMethod<String>('searchAndConnect');
      setState(() {
        _deviceId = id;
        _status = id != null ? 'Connected to $id' : 'Connection failed';
      });
    } on PlatformException catch (e) {
      setState(() => _status = 'Error: ${e.message}');
    }
  }

  Future<void> _getOneHrSample() async {
    try {
      final hr = await _channel.invokeMethod<int>('getOneHrSample');
      setState(() {
        _lastHr = hr;
        _status = "Got HR sample: $hr bpm";
      });
    } catch (e) {
      setState(() => _status = "HR Sample Error: $e");
    }
  }

  // -----------------------------------------------------
  // STREAM STARTERS (EventChannel only — no MethodChannel!)
  // -----------------------------------------------------

  Future<void> _startEcg() async {
    ecgSub?.cancel();
    ecgSub = _ecgStream.receiveBroadcastStream().listen((sample) {
      final value = (sample as num).toDouble();
      setState(() {
        ecgBuffer.add(value);
        if (ecgBuffer.length > 600) ecgBuffer.removeAt(0);
      });
    }, onError: (e) {
      debugPrint("ECG ERROR: $e");
    });
  }

  Future<void> _startHr() async {
    rrSub?.cancel();
    rrSub = _rrStream.receiveBroadcastStream().listen((event) {
      if (event is Map) {
        final rrList = (event["rr"] as List?)?.cast<int>() ?? [];
        final hrValue = event["hr"] as int?;

        setState(() {
          if (hrValue != null) _lastHr = hrValue;
          rrBuffer.addAll(rrList);
          if (rrBuffer.length > 200) {
            rrBuffer = rrBuffer.sublist(rrBuffer.length - 200);
          }
        });
      }
    }, onError: (e) {
      debugPrint("RR ERROR: $e");
    });
  }

  Future<void> _startAcc() async {
    accSub?.cancel();
    accSub = _accStream.receiveBroadcastStream().listen((event) {
      if (event is Map) {
        setState(() {
          accBuffer.add({
            "x": (event["x"] as num?)?.toDouble() ?? 0,
            "y": (event["y"] as num?)?.toDouble() ?? 0,
            "z": (event["z"] as num?)?.toDouble() ?? 0,
          });

          if (accBuffer.length > 300) accBuffer.removeAt(0);
        });
      }
    }, onError: (e) {
      debugPrint("ACC ERROR: $e");
    });
  }

  // -----------------------------------------------------
  // UI
  // -----------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Polar H10 SDK (Android)'),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Status: $_status'),
              const SizedBox(height: 8),
              Text('Device ID: ${_deviceId ?? "-"}'),
              const SizedBox(height: 8),
              Text('Last HR: ${_lastHr?.toString() ?? "-"} bpm'),

              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _searchAndConnect,
                child: const Text('Search & Connect'),
              ),
              ElevatedButton(
                onPressed: _getOneHrSample,
                child: const Text('Get 1 HR Sample'),
              ),

              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _startEcg,
                child: const Text('Start ECG Stream'),
              ),
              ElevatedButton(
                onPressed: _startHr,
                child: const Text('Start RR/HR Stream'),
              ),
              ElevatedButton(
                onPressed: _startAcc,
                child: const Text('Start Accelerometer Stream'),
              ),

              const SizedBox(height: 24),

              // Simple previews for debugging streams
              Text("ECG Samples: ${ecgBuffer.take(10).toList()}"),
              const SizedBox(height: 8),
              Text("RR Buffer: ${rrBuffer.take(10).toList()}"),
              const SizedBox(height: 8),
              Text("ACC Last: ${accBuffer.isNotEmpty ? accBuffer.last : '-'}"),
            ],
          ),
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
