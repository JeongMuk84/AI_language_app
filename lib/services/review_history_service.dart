import 'dart:convert';
import 'dart:io';

import '../models/review_record.dart';
import '../utils/language_key.dart';
import 'config_service.dart';
import 'storage_location_service.dart';

/// Reads/writes `review_history.json` — every sentence the learner has
/// completed a turn on, for spaced review — kept strictly per target
/// language, under `review_history/<languageKey>/review_history.json` (see
/// [languageStorageKey]), resolved from the CURRENT `config.json` on every
/// call. Deliberately separate from `TtsCacheService`: the cache exists
/// purely for playback and can evict entries at any time, while this is the
/// durable learning record (`firstLearnedAt`/`lastReviewedAt`/
/// `reviewCount`) that review selection is based on.
/// (학습자가 한 turn을 완료한 모든 문장을 spaced review(간격 반복 복습)를
/// 위해 기록하는 `review_history.json`을 읽고 쓴다. 대상 언어별로 철저히
/// 분리되어 `review_history/<languageKey>/review_history.json`
/// ([languageStorageKey] 참고) 아래에 저장되며, "지금 어느 언어인지"는
/// 매번 호출 시점의 현재 `config.json`에서 판단한다. `TtsCacheService`와는
/// 의도적으로 분리되어 있다: 캐시는 순수하게 재생을 위한 것이라 언제든
/// entry가 evict될 수 있지만, 이쪽은 review 선정의 기준이 되는 영구적인
/// 학습 기록(`firstLearnedAt`/`lastReviewedAt`/`reviewCount`)이다.)
///
/// `reviewHistoryServiceProvider`(`service_providers.dart`)를 통해
/// 노출되며, `ReviewSessionService`와 `ListeningHistoryService`가 원본
/// 데이터로 사용하고, `ShadowingViewModel`/`WritingViewModel`이 새 문장을
/// 학습할 때 [recordIfNew]를, `ReviewViewModel`이 복습을 마쳤을 때
/// [markReviewed]를 호출한다.
class ReviewHistoryService {
  ReviewHistoryService({StorageLocationService? storageLocationService, ConfigService? configService})
    : _storageLocationService = storageLocationService ?? StorageLocationService(),
      _configService = configService ?? ConfigService();

  final StorageLocationService _storageLocationService;
  final ConfigService _configService;

  /// Parent of every language's review-history folder — used only by
  /// [clearHistory] (full reset, all languages).
  /// (모든 언어의 review-history 폴더의 상위 디렉터리 — 전체 초기화(모든
  /// 언어 대상)를 하는 [clearHistory]에서만 사용된다.)
  Future<Directory> _rootDir() async {
    final dir = await _storageLocationService.baseDirectory();
    return Directory('${dir.path}/review_history');
  }

  /// 현재 대상 언어에 해당하는 review_history.json 파일 핸들을 반환한다.
  /// `config.json`에서 `targetLanguage`를 읽어 `languageStorageKey`로
  /// 저장용 키를 만들고, 필요하면 언어별 디렉터리를 생성한다. 이 클래스의
  /// 다른 메서드들이 내부적으로 사용하는 헬퍼다.
  /// 부작용: 대상 언어별 디렉터리가 없으면 새로 만든다.
  Future<File> _historyFile() async {
    final config = await _configService.readConfig();
    final key = languageStorageKey(config.targetLanguage ?? 'unknown');
    final root = await _rootDir();
    final languageDir = Directory('${root.path}/$key');
    if (!await languageDir.exists()) {
      await languageDir.create(recursive: true);
    }
    return File('${languageDir.path}/review_history.json');
  }

  /// 현재 대상 언어의 review_history.json을 읽어 원본 JSON Map(문장 ->
  /// 레코드 JSON)으로 반환한다. 파일이 없거나 비어있으면 빈 Map을
  /// 반환한다. [readAll], [recordIfNew], [markReviewed]가 내부적으로
  /// 사용하는 헬퍼다.
  Future<Map<String, dynamic>> _readRaw() async {
    final file = await _historyFile();
    if (!await file.exists()) return {};
    final content = await file.readAsString();
    if (content.trim().isEmpty) return {};
    return jsonDecode(content) as Map<String, dynamic>;
  }

  /// [raw] Map을 JSON으로 직렬화해 현재 대상 언어의 review_history.json에
  /// 덮어쓴다. [recordIfNew]와 [markReviewed]가 변경사항을 저장할 때
  /// 호출하는 헬퍼다.
  /// 부작용: review_history.json 파일을 덮어쓴다.
  Future<void> _writeRaw(Map<String, dynamic> raw) async {
    final file = await _historyFile();
    await file.writeAsString(jsonEncode(raw));
  }

  /// 현재 대상 언어에 기록된 모든 [ReviewRecord]를 읽어온다.
  /// `ReviewSessionService.buildReviewSet`이 복습 대상을 고를 때,
  /// `ListeningHistoryService.buildHistory`가 듣기 기록 목록을 만들 때
  /// 원본 데이터로 호출한다.
  /// 반환값: 저장된 모든 [ReviewRecord] 목록(순서 무관).
  Future<List<ReviewRecord>> readAll() async {
    final raw = await _readRaw();
    return raw.values
        .map((v) => ReviewRecord.fromJson(v as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// Adds a record for [sentenceInTarget] the first time it's seen — a
  /// no-op if it's already tracked, so a sentence's `firstLearnedAt` never
  /// changes and repeated turns on the same sentence don't reset it.
  /// ([sentenceInTarget]을 처음 볼 때만 레코드를 추가한다 — 이미 기록되어
  /// 있으면 아무것도 하지 않으므로, 문장의 `firstLearnedAt`은 절대 바뀌지
  /// 않고 같은 문장에 대한 반복된 turn이 이를 리셋하지 않는다.)
  ///
  /// `ShadowingViewModel`과 `WritingViewModel`이 학습자가 새 문장으로 한
  /// turn을 완료했을 때 호출해, 그 문장을 spaced review 대상 풀에 처음
  /// 등록한다.
  /// [sentenceInTarget]: 대상 언어 원문 문장(레코드의 키).
  /// [sentenceInNative]: 해당 문장의 모국어 번역.
  /// 부작용: 처음 보는 문장이면 review_history.json에 새 레코드를 추가한다.
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
  /// ([sentenceInTarget]을 방금 복습한 것으로 표시한다 - `lastReviewedAt`을
  /// 갱신하고 `reviewCount`를 1 증가시킨다. TTS 캐시의 마지막 사용 시각은
  /// 절대 건드리지 않는다; 이 둘의 "마지막 사용" 개념은 서로 독립적이다.)
  ///
  /// `ReviewViewModel`이 복습 화면에서 한 문장에 대한 복습(번역/발음 채점
  /// 등)을 마쳤을 때 호출한다.
  /// [sentenceInTarget]: 방금 복습을 마친 대상 언어 문장(레코드 키).
  /// 부작용: 해당 레코드가 존재하면 review_history.json을 갱신한다. 레코드가
  /// 없으면 아무 일도 하지 않는다.
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

  /// Deletes every language's review history. Used by the `RESET_APP`
  /// dev/test flag and Settings' "Reset All Data" — a target-language
  /// switch must NOT call this (see `SettingsViewModel.save`); each
  /// language's history stays intact so switching back to a
  /// previously-studied language finds it (and its
  /// `ListeningHistoryScreen` entries) still there.
  /// (모든 언어의 review history를 삭제한다. `main.dart`의 `RESET_APP`
  /// 개발/테스트용 플래그와 Settings 화면의 "Reset All Data"
  /// (`SettingsViewModel`)에서 호출된다 — 대상 언어를 전환하는 것만으로는
  /// 절대 이 메서드를 호출해서는 안 된다(`SettingsViewModel.save` 참고);
  /// 각 언어의 history는 그대로 남아있어야, 예전에 공부했던 언어로 다시
  /// 돌아왔을 때 그 기록(그리고 `ListeningHistoryScreen`에 표시될 항목들)이
  /// 여전히 남아있게 된다.)
  /// 부작용: `review_history` 디렉터리 전체를 재귀적으로 삭제한다.
  Future<void> clearHistory() async {
    final dir = await _rootDir();
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }
}
