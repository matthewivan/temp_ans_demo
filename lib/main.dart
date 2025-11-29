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

  String _status = 'Idle';
  String? _deviceId;
  int? _lastHr;

  Future<void> _searchAndConnect() async {
    if (!Platform.isAndroid) {
      setState(() {
        _status = 'Android only demo';
      });
      return;
    }

    setState(() => _status = 'Searching & connecting...');

    try {
      final id = await _channel.invokeMethod<String>('searchAndConnect');
      setState(() {
        _deviceId = id;
        _status = id != null
            ? 'Connected to $id'
            : 'searchAndConnect returned null';
      });
    } on PlatformException catch (e) {
      setState(() {
        _status = 'Error: ${e.code} – ${e.message}';
      });
    }
  }

  Future<void> _getOneHrSample() async {
    if (!Platform.isAndroid) {
      setState(() {
        _status = 'Android only demo';
      });
      return;
    }

    setState(() => _status = 'Getting one HR sample...');

    try {
      final hr = await _channel.invokeMethod<int>('getOneHrSample');
      setState(() {
        _lastHr = hr;
        _status = 'Got HR sample: $hr bpm';
      });
    } on PlatformException catch (e) {
      setState(() {
        _status = 'Error: ${e.code} – ${e.message}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Polar H10 SDK (Android)'),
      ),
      body: Padding(
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
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _getOneHrSample,
              child: const Text('Get 1 HR Sample'),
            ),
          ],
        ),
      ),
    );
  }
}
