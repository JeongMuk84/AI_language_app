import 'dart:convert';
import 'dart:io';

import '../models/conversation_turn.dart';
import '../utils/language_key.dart';
import 'config_service.dart';
import 'storage_location_service.dart';

/// 현재 진행 중인 대화 맥락(`GeminiService.generateNextSentence`가 받는
/// `history` 인자)을 읽고 쓰는 서비스.
///
/// 대상 언어(target language)별로 철저히 분리되어
/// `conversation_history/<languageKey>/history.json` 아래에 저장되므로,
/// 대상 언어를 전환해도 한 언어의 turn이 다른 언어의 프롬프트 맥락에
/// 절대 섞이지 않는다. "지금 어느 언어인지"는 호출부가 명시적으로
/// 알려주는 대신 매번 현재 `config.json`에서 읽어 판단하는데, 이는 turn을
/// 기록/조회하는 시점에는 항상 그 언어가 활성 언어이기 때문이다(언어
/// 전환은 재시작 과정을 거친 뒤에야 이 서비스를 다시 읽고 쓰게 된다).
///
/// `SessionStateService`와는 의도적으로 분리되어 있다: 그쪽은 언어와
/// 무관한 단일 상태인 "지금 당장 무엇을 하고 있는가"(현재 문장/turn/하위
/// 단계)를 소유하며, 언어를 전환하면 명시적으로 지워진다
/// (`SettingsViewModel.save` 참고) — turn 도중 상태를 언어 전환 너머로
/// 이어받는 것은 의미가 없기 때문이다. 반면 이 대화 history는 같은 언어
/// 안에서 다른 화면으로 갔다가 돌아와도 살아남도록 만들어졌다.
class ConversationHistoryService {
  ConversationHistoryService({StorageLocationService? storageLocationService, ConfigService? configService})
    : _storageLocationService = storageLocationService ?? StorageLocationService(),
      _configService = configService ?? ConfigService();

  final StorageLocationService _storageLocationService;
  final ConfigService _configService;

  /// 현재 대상 언어에 해당하는 history.json 파일 핸들을 반환한다.
  /// `config.json`에서 `targetLanguage`를 읽어 `languageStorageKey`로
  /// 저장용 키를 만들고, 필요하면 `conversation_history/<key>` 디렉터리를
  /// 생성한다. 이 클래스의 다른 모든 메서드가 내부적으로 사용하는 헬퍼다.
  /// 부작용: 대상 언어별 디렉터리가 없으면 새로 만든다.
  Future<File> _historyFile() async {
    final config = await _configService.readConfig();
    final key = languageStorageKey(config.targetLanguage ?? 'unknown');
    final base = await _storageLocationService.baseDirectory();
    final dir = Directory('${base.path}/conversation_history/$key');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File('${dir.path}/history.json');
  }

  /// 현재 대상 언어의 대화 history 전체를 읽어온다. 파일이 없거나
  /// 비어있으면 빈 리스트를 반환한다. `GeminiService`가 다음 문장을
  /// 생성하기 위한 프롬프트를 구성할 때(`snapshot.conversationHistory`)와,
  /// `HistoryService`가 세션을 마무리할 때 등에서 호출된다.
  /// 반환값: [ConversationTurn] 목록(최신순이 아닌 기록된 순서).
  Future<List<ConversationTurn>> readAll() async {
    final file = await _historyFile();
    if (!await file.exists()) return const [];
    final content = await file.readAsString();
    if (content.trim().isEmpty) return const [];
    final list = jsonDecode(content) as List;
    return list.map((t) => ConversationTurn.fromJson(t as Map<String, dynamic>)).toList();
  }

  /// Appends [turn] to the current target language's history.
  /// (현재 대상 언어의 history 끝에 [turn]을 추가한다.)
  /// 사용자가 응답을 제출하고 채점을 받는 등 대화가 한 turn 진행될 때마다
  /// 호출되어, 다음 문장 생성 시 프롬프트 맥락으로 쓰일 기록을 남긴다.
  /// 부작용: history.json 파일 내용을 갱신한다.
  Future<void> append(ConversationTurn turn) async {
    final existing = await readAll();
    await _writeAll([...existing, turn]);
  }

  /// [turns] 전체를 JSON으로 직렬화해 현재 대상 언어의 history.json에
  /// 덮어쓴다. [append]가 내부적으로 사용하는 헬퍼다.
  /// 부작용: history.json 파일을 덮어쓴다.
  Future<void> _writeAll(List<ConversationTurn> turns) async {
    final file = await _historyFile();
    await file.writeAsString(jsonEncode(turns.map((t) => t.toJson()).toList()));
  }

  /// Clears the current target language's history only — used when
  /// finalizing a session (see `HistoryService.finalizeSession`), same as
  /// the old single-file behavior. Does NOT touch any other language's
  /// history; use [clearAllLanguages] for a full reset.
  /// (현재 대상 언어의 history만 지운다 — 세션을 마무리할 때
  /// [HistoryService.finalizeSession]에서 호출되며, 예전의 단일 파일
  /// 방식과 동일한 동작이다. 다른 언어의 history는 건드리지 않으며,
  /// 전체 초기화가 필요하면 [clearAllLanguages]를 사용한다.)
  /// 부작용: 현재 대상 언어의 history.json 파일을 삭제한다.
  Future<void> clear() async {
    final file = await _historyFile();
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// Deletes every language's conversation history. Used by the
  /// `RESET_APP` dev/test flag and Settings' "Reset All Data" — distinct
  /// from [clear], which only affects the current language.
  /// (모든 언어의 대화 history를 삭제한다. `main.dart`의 `RESET_APP`
  /// 개발/테스트용 플래그와 Settings의 "Reset All Data"에서 사용되며,
  /// 현재 언어만 지우는 [clear]와는 구분된다.)
  /// 부작용: `conversation_history` 디렉터리 전체를 재귀적으로 삭제한다.
  Future<void> clearAllLanguages() async {
    final base = await _storageLocationService.baseDirectory();
    final dir = Directory('${base.path}/conversation_history');
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }
}
