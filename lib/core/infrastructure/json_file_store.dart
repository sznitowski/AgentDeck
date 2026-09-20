import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Versioned, non-secret app data. Each mutation is serialized and flushed.
class JsonFileStore {
  JsonFileStore(this.file);

  final File file;
  Future<void> _tail = Future<void>.value();

  Future<T> _exclusive<T>(Future<T> Function() action) {
    final result = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        result.complete(await action());
      } catch (error, stack) {
        result.completeError(error, stack);
      }
    });
    return result.future;
  }

  Future<List<Map<String, dynamic>>> readAll() => _exclusive(_read);

  Future<T> update<T>(T Function(List<Map<String, dynamic>>) mutation) =>
      _exclusive(() async {
        final items = await _read();
        final result = mutation(items);
        await _write(items);
        return result;
      });

  Future<List<Map<String, dynamic>>> _read() async {
    final backup = File('${file.path}.bak');
    final source =
        await file.exists() ? file : (await backup.exists() ? backup : null);
    if (source == null) return [];
    final data = jsonDecode(await source.readAsString());
    if (data is! Map<String, dynamic> ||
        data['schema'] != 1 ||
        data['items'] is! List) {
      throw const FormatException('Unsupported or corrupt app data');
    }
    return (data['items'] as List).map((item) {
      if (item is! Map<String, dynamic>) {
        throw const FormatException('Invalid app data record');
      }
      return Map<String, dynamic>.from(item);
    }).toList();
  }

  Future<void> _write(List<Map<String, dynamic>> items) async {
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    final backup = File('${file.path}.bak');
    await temp.writeAsString(jsonEncode({'schema': 1, 'items': items}),
        flush: true);
    if (await file.exists()) {
      if (await backup.exists()) await backup.delete();
      await file.rename(backup.path);
    }
    try {
      await temp.rename(file.path);
    } catch (_) {
      if (!await file.exists() && await backup.exists()) {
        await backup.rename(file.path);
      }
      rethrow;
    }
    if (await backup.exists()) await backup.delete();
  }
}
