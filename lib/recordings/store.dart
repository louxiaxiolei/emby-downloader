import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class RecordingFile {
  const RecordingFile({
    required this.path,
    required this.name,
    required this.bytes,
    required this.modified,
  });

  final String path;
  final String name;
  final int bytes;
  final DateTime modified;

  bool get canOfferPhotos {
    final lower = name.toLowerCase();
    return lower.endsWith('.mp4') || lower.endsWith('.m4v') || lower.endsWith('.mov');
  }
}

Future<Directory> recordingsDirectory() async {
  final docs = await getApplicationDocumentsDirectory();
  final directory = Directory(p.join(docs.path, 'Recordings'));
  if (!await directory.exists()) {
    await directory.create(recursive: true);
  }
  return directory;
}

Future<List<RecordingFile>> listRecordings() async {
  final directory = await recordingsDirectory();
  final files = <RecordingFile>[];
  await for (final entity in directory.list()) {
    if (entity is! File) continue;
    final name = p.basename(entity.path);
    if (name.startsWith('.')) continue;
    final stat = await entity.stat();
    if (stat.size <= 0) continue;
    files.add(
      RecordingFile(
        path: entity.path,
        name: name,
        bytes: stat.size,
        modified: stat.modified,
      ),
    );
  }
  files.sort((a, b) => b.modified.compareTo(a.modified));
  return files;
}

Future<void> deleteRecording(String path) async {
  final file = File(path);
  if (await file.exists()) await file.delete();
}
