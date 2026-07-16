import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/review_record.dart';

/// Reads/writes `review_history.json` — every sentence the learner has
/// completed a turn on, for spaced review. Deliberately separate from
/// `TtsCacheService`: the cache exists purely for playback and can evict
/// entries at any time, while this is the durable learning record
/// (`firstLearnedAt`/`lastReviewedAt`/`reviewCount`) that review selection
/// is based on.
class ReviewHistoryService {
  Future<File> _historyFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/review_history.json');
  }

  Future<Map<String, dynamic>> _readRaw() async {
    final file = await _historyFile();
    if (!await file.exists()) return {};
    final content = await file.readAsString();
    if (content.trim().isEmpty) return {};
    return jsonDecode(content) as Map<String, dynamic>;
  }

  Future<void> _writeRaw(Map<String, dynamic> raw) async {
    final file = await _historyFile();
    await file.writeAsString(jsonEncode(raw));
  }

  Future<List<ReviewRecord>> readAll() async {
    final raw = await _readRaw();
    return raw.values
        .map((v) => ReviewRecord.fromJson(v as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// Adds a record for [sentenceInTarget] the first time it's seen — a
  /// no-op if it's already tracked, so a sentence's `firstLearnedAt` never
  /// changes and repeated turns on the same sentence don't reset it.
  Future<void> recordIfNew({
    required String sentenceInTarget,
    required String sentenceInNative,
  }) async {
    final raw = await _readRaw();
    if (raw.containsKey(sentenceInTarget)) return;
    raw[sentenceInTarget] = ReviewRecord(
      sentenceInTarget: sentenceInTarget,
      sentenceInNative: sentenceInNative,
      firstLearnedAt: DateTime.now(),
    ).toJson();
    await _writeRaw(raw);
  }

  /// Marks [sentenceInTarget] as reviewed just now — sets `lastReviewedAt`
  /// and increments `reviewCount`. Never touches the TTS cache's
  /// last-used time; those two "last used" concepts are independent.
  Future<void> markReviewed(String sentenceInTarget) async {
    final raw = await _readRaw();
    final entry = raw[sentenceInTarget] as Map<String, dynamic>?;
    if (entry == null) return;
    final record = ReviewRecord.fromJson(entry);
    raw[sentenceInTarget] = record
        .copyWith(lastReviewedAt: DateTime.now(), reviewCount: record.reviewCount + 1)
        .toJson();
    await _writeRaw(raw);
  }

  /// Deletes the entire review history. Used by the `RESET_APP` dev/test
  /// flag and Settings' "Reset All Data".
  Future<void> clearHistory() async {
    final file = await _historyFile();
    if (await file.exists()) {
      await file.delete();
    }
  }
}
