import 'dart:convert';
import 'dart:io';

import '../models/learning_summary.dart';
import '../utils/language_key.dart';
import 'config_service.dart';
import 'storage_location_service.dart';

/// 현재 target language로 지금까지 학습한 내용을 압축해 누적한 요약을
/// 읽고 쓰는 서비스. `audio_cache/<key>`, `review_history/<key>`,
/// `conversation_history/<key>`와 동일한 원칙으로 언어별로 철저히 분리되어
/// `learning_summary/<languageKey>/summary.json`([languageStorageKey] 참고)
/// 아래에 저장되며, "지금 어느 언어인지"는 매번 호출 시점의 현재
/// `config.json`에서 판단한다.
///
/// `ConversationHistoryService`(오늘/최근 세션의 직접적인 문맥)와는 역할이
/// 다르다 — 이쪽은 날짜를 넘어 계속 압축·병합되며 유지되는 장기 누적
/// 요약으로, `GeminiService.generateDailySentenceSet`이 같은 주제/어휘/
/// 상황을 반복하지 않도록 참고하는 자료다. `HistoryService.finalizeSession`
/// 이 하루치 세션이 마감될 때(`GeminiService.updateLearningSummary`로 갱신
/// 텍스트를 만든 뒤) [writeCumulativeSummary]를 호출한다.
class LearningSummaryService {
  LearningSummaryService({
    StorageLocationService? storageLocationService,
    ConfigService? configService,
  }) : _storageLocationService = storageLocationService ?? StorageLocationService(),
       _configService = configService ?? ConfigService();

  final StorageLocationService _storageLocationService;
  final ConfigService _configService;

  /// 모든 언어의 learning-summary 폴더의 상위 디렉터리 — 전체 초기화(모든
  /// 언어 대상)를 하는 [clearAllLanguages]에서만 사용된다.
  Future<Directory> _rootDir() async {
    final dir = await _storageLocationService.baseDirectory();
    return Directory('${dir.path}/learning_summary');
  }

  /// 현재 대상 언어에 해당하는 summary.json 파일 핸들을 반환한다.
  /// `config.json`에서 `targetLanguage`를 읽어 `languageStorageKey`로
  /// 저장용 키를 만들고, 필요하면 언어별 디렉터리를 생성한다. 이 클래스의
  /// 다른 메서드들이 내부적으로 사용하는 헬퍼다.
  /// 부작용: 대상 언어별 디렉터리가 없으면 새로 만든다.
  Future<File> _summaryFile() async {
    final config = await _configService.readConfig();
    final key = languageStorageKey(config.targetLanguage ?? 'unknown');
    final root = await _rootDir();
    final languageDir = Directory('${root.path}/$key');
    if (!await languageDir.exists()) {
      await languageDir.create(recursive: true);
    }
    return File('${languageDir.path}/summary.json');
  }

  /// 현재 대상 언어의 누적 학습 요약을 읽는다. 파일이 없거나, 내용이
  /// 비어있거나, 아직 요약 텍스트 자체가 빈 문자열이면 `null`을 반환한다.
  ///
  /// `TopicInputDialog`가 `GeminiService.generateDailySentenceSet` 호출
  /// 직전에, `HistoryService.finalizeSession`이 새 요약을 만들기 전 기존
  /// 값을 참고하기 위해 호출한다.
  /// 반환값: 저장된 누적 요약 텍스트, 없으면 `null`.
  Future<String?> readCumulativeSummary() async {
    final file = await _summaryFile();
    if (!await file.exists()) return null;
    final content = await file.readAsString();
    if (content.trim().isEmpty) return null;
    final summary = LearningSummary.fromJson(jsonDecode(content) as Map<String, dynamic>);
    return summary.cumulativeSummary.isEmpty ? null : summary.cumulativeSummary;
  }

  /// [cumulativeSummary]를 현재 대상 언어의 summary.json에 (갱신 시각과
  /// 함께) 덮어쓴다. `HistoryService.finalizeSession`이
  /// `GeminiService.updateLearningSummary`로 기존 요약과 그날 내용을 압축·
  /// 병합한 결과를 저장하기 위해 호출한다 — 하루 세션이 마감될 때마다
  /// 한 번씩만 호출되므로, 문장 하나하나마다 갱신되지 않는다.
  /// [cumulativeSummary]: 새로 압축·병합된 누적 요약 텍스트.
  /// 부작용: summary.json 파일을 덮어쓴다.
  Future<void> writeCumulativeSummary(String cumulativeSummary) async {
    final file = await _summaryFile();
    await file.writeAsString(
      jsonEncode(
        LearningSummary(
          cumulativeSummary: cumulativeSummary,
          lastUpdatedDate: DateTime.now(),
        ).toJson(),
      ),
    );
  }

  /// Deletes every language's cumulative learning summary. Used by the
  /// `RESET_APP` dev/test flag and Settings' "Reset All Data".
  /// (모든 언어의 누적 학습 요약을 삭제한다. `main.dart`의 `RESET_APP`
  /// 개발/테스트용 플래그와 Settings 화면의 "Reset All Data"
  /// (`SettingsViewModel`)에서 사용된다.)
  /// 부작용: `learning_summary` 디렉터리 전체를 재귀적으로 삭제한다.
  Future<void> clearAllLanguages() async {
    final dir = await _rootDir();
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }
}
