import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

class _ModelEntry {
  final OrtSession session;
  DateTime lastUsed;

  _ModelEntry(this.session) : lastUsed = DateTime.now();
}

class SmartOnnxModelManager {
  static final Map<String, _ModelEntry> _cache = {};

  /// Load model or return cached session
  static Future<OrtSession> getModel({required String key, required String modelPath, bool isAsset = true}) async {
    final existing = _cache[key];

    if (existing != null) {
      existing.lastUsed = DateTime.now();
      return existing.session;
    }

    final ort = OnnxRuntime();

    final session = isAsset ? await ort.createSessionFromAsset(modelPath) : await ort.createSession(modelPath);

    _cache[key] = _ModelEntry(session);

    return session;
  }

  /// Manually release a model
  static Future<void> unload(String key) async {
    final entry = _cache.remove(key);
    if (entry != null) {
      await entry.session.close();
    }
  }

  /// Clear everything (app shutdown or reset)
  static Future<void> clearAll() async {
    for (final entry in _cache.values) {
      await entry.session.close();
    }
    _cache.clear();
  }

  /// Auto cleanup idle models
  static void cleanup({Duration maxIdle = const Duration(minutes: 5)}) {
    final now = DateTime.now();

    final keysToRemove = <String>[];

    _cache.forEach((key, entry) {
      final idleTime = now.difference(entry.lastUsed);

      if (idleTime > maxIdle) {
        keysToRemove.add(key);
      }
    });

    for (final key in keysToRemove) {
      _cache[key]?.session.close();
      _cache.remove(key);
    }
  }

  /// Debug helper
  static List<String> getLoadedModels() {
    return _cache.keys.toList();
  }
}
