import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class RecordingManager {
  late Directory sessionDir;
  IOSink? ecgFile;
  IOSink? rrFile;
  IOSink? accFile;
  IOSink? hrFile;

  bool isRecording = false;

  // --------------------------- CREATE NEW SESSION ---------------------------
  Future<void> startRecording(Map<String, dynamic> metadata) async {
    final root = await _recordingsRoot();

    final now = DateTime.now();
    final folderName =
        "session_${now.year}-${now.month}-${now.day}_${now.hour}-${now.minute}-${now.second}";

    sessionDir = Directory("${root.path}/$folderName");
    await sessionDir.create(recursive: true);

    // Write metadata.json
    final metaFile = File("${sessionDir.path}/metadata.json");
    await metaFile.writeAsString(
      const JsonEncoder.withIndent("  ").convert(metadata),
    );

    // Open CSV sinks
    ecgFile = File("${sessionDir.path}/ecg.csv").openWrite();
    rrFile = File("${sessionDir.path}/rr.csv").openWrite();
    accFile = File("${sessionDir.path}/acc.csv").openWrite();
    hrFile = File("${sessionDir.path}/hr.csv").openWrite();

    ecgFile!.writeln("timestamp_us,value_uV");
    rrFile!.writeln("timestamp_us,rr_ms,hr_bpm");
    accFile!.writeln("timestamp_us,x,y,z");
    hrFile!.writeln("timestamp_us,hr_bpm");

    isRecording = true;
  }

  // ---------------------------- APPEND DATA ----------------------------

  void writeEcg(int microVolts) {
    if (!isRecording) return;
    final t = DateTime.now().microsecondsSinceEpoch;
    ecgFile?.writeln("$t,$microVolts");
  }

  void writeRr(List<int> rrs, int hr) {
    if (!isRecording) return;
    final t = DateTime.now().microsecondsSinceEpoch;

    for (final rr in rrs) {
      rrFile?.writeln("$t,$rr,$hr");
    }
  }

  void writeAcc(double x, double y, double z) {
    if (!isRecording) return;
    final t = DateTime.now().microsecondsSinceEpoch;

    accFile?.writeln("$t,$x,$y,$z");
  }

  void writeHr(int hr) {
    if (!isRecording) return;
    final t = DateTime.now().microsecondsSinceEpoch;

    hrFile?.writeln("$t,$hr");
  }

  // ------------------------------ STOP ------------------------------

  Future<void> stopRecording() async {
    isRecording = false;

    await ecgFile?.close();
    await rrFile?.close();
    await accFile?.close();
    await hrFile?.close();
  }

  // ------------------------------ LOAD ------------------------------

  Future<Map<String, dynamic>> loadRecording(String folderPath) async {
    final metadata = jsonDecode(
        await File("$folderPath/metadata.json").readAsString());

    final ecg = await File("$folderPath/ecg.csv").readAsLines();
    final rr = await File("$folderPath/rr.csv").readAsLines();
    final acc = await File("$folderPath/acc.csv").readAsLines();
    final hr = await File("$folderPath/hr.csv").readAsLines();

    return {
      "metadata": metadata,
      "ecg": ecg.skip(1).toList(),
      "rr": rr.skip(1).toList(),
      "acc": acc.skip(1).toList(),
      "hr": hr.skip(1).toList(),
    };
  }

  // -------------------------- List all recordings -------------------------

  Future<List<Directory>> listRecordings() async {
    final root = await _recordingsRoot();
    final dirs = root
        .listSync()
        .whereType<Directory>()
        .toList()
      ..sort((a, b) => b.path.compareTo(a.path)); // latest first
    return dirs;
  }

  // ---------------------------- Helpers ----------------------------

  Future<Directory> _recordingsRoot() async {
    final appDir = await getApplicationDocumentsDirectory();
    final recDir = Directory("${appDir.path}/recordings");
    await recDir.create(recursive: true);
    return recDir;
  }
}
