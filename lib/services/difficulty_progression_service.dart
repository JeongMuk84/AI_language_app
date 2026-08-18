import 'dart:convert';
import 'dart:io';

import '../models/difficulty_progression.dart';
import '../utils/language_key.dart';
import 'config_service.dart';
import 'day_boundary_service.dart';
import 'storage_location_service.dart';

/// 하루 10문장씩, 1년(365일)에 걸쳐 아주 천천히 초급에서 마스터 수준까지
/// 오르는 "점진적 난이도 상승" 진행 상태를 언어별로 읽고 쓰는 서비스.
/// `audio_cache/<key>`, `review_history/<key>`와 동일한 원칙으로 언어별로
/// 철저히 분리되어 `difficulty_progression/<languageKey>/progression.json`
/// ([languageStorageKey] 참고) 아래에 저장된다.
///
/// 레벨 테스트로 산정되는 `config.difficultyLevel`(CEFR 등급)은 그대로
/// 두고 바뀌지 않는다 — 이 서비스는 그 위에 얹혀서, 레벨 테스트 결과를
/// 0~100 연속 점수의 *시작값*으로만 사용하고 이후로는 매일 그 점수를 아주
/// 조금씩 끌어올리는 별도의 계층이다. 언어를 전환하면 각 언어가 독립적인
/// `startDate`/진행 상태를 가지므로, 베트남어를 6개월 진행하다가 스페인어로
/// 바꾸면 스페인어는 0일차부터 새로 시작하고, 나중에 베트남어로 돌아오면
/// 베트남어의 진행 상태는 그대로 이어져 있다.
///
/// `GeminiService.generateDailySentenceSet`이 문장 길이/문법 복잡도를
/// 계산하기 위해 [readTodayScore]를 호출한다(`TopicInputDialog`를 통해).
class DifficultyProgressionService {
  DifficultyProgressionService({
    StorageLocationService? storageLocationService,
    ConfigService? configService,
    DayBoundaryService? dayBoundaryService,
  }) : _storageLocationService = storageLocationService ?? StorageLocationService(),
       _configService = configService ?? ConfigService(),
       _dayBoundaryService = dayBoundaryService ?? DayBoundaryService();

  final StorageLocationService _storageLocationService;
  final ConfigService _configService;
  final DayBoundaryService _dayBoundaryService;

  /// 목표(마스터) 난이도 점수 — 진행률 100%에서 도달하는 상한.
  static const double kMasterScore = 100.0;

  /// 시작 점수에서 [kMasterScore]까지 도달하는 데 걸리는 일수(하루 약
  /// 0.27점 상승하는 선형 기준의 근거 — 체감상 거의 못 느낄 정도로
  /// 미세해야 한다는 요구에 맞춘 값).
  static const int kProgressionDays = 365;

  /// 모든 언어의 difficulty-progression 폴더의 상위 디렉터리 — 전체
  /// 초기화(모든 언어 대상)를 하는 [clearAllLanguages]에서만 사용된다.
  Future<Directory> _rootDir() async {
    final dir = await _storageLocationService.baseDirectory();
    return Directory('${dir.path}/difficulty_progression');
  }

  /// 현재 대상 언어에 해당하는 progression.json 파일 핸들을 반환한다.
  /// `config.json`에서 `targetLanguage`를 읽어 `languageStorageKey`로
  /// 저장용 키를 만들고, 필요하면 언어별 디렉터리를 생성한다. 이 클래스의
  /// 다른 메서드들이 내부적으로 사용하는 헬퍼다.
  /// 부작용: 대상 언어별 디렉터리가 없으면 새로 만든다.
  Future<File> _progressionFile() async {
    final config = await _configService.readConfig();
    final key = languageStorageKey(config.targetLanguage ?? 'unknown');
    final root = await _rootDir();
    final languageDir = Directory('${root.path}/$key');
    if (!await languageDir.exists()) {
      await languageDir.create(recursive: true);
    }
    return File('${languageDir.path}/progression.json');
  }

  /// 현재 대상 언어의 저장된 진행 기록을 읽는다. 파일이 없거나 비어있으면
  /// `null`을 반환한다. [readTodayScore]가 내부적으로 사용하는 헬퍼다.
  Future<DifficultyProgression?> _read() async {
    final file = await _progressionFile();
    if (!await file.exists()) return null;
    final content = await file.readAsString();
    if (content.trim().isEmpty) return null;
    return DifficultyProgression.fromJson(jsonDecode(content) as Map<String, dynamic>);
  }

  /// [progression]을 현재 대상 언어의 progression.json에 덮어쓴다.
  /// [readTodayScore]가 진행 기록을 처음 만들 때 호출하는 헬퍼다.
  Future<void> _write(DifficultyProgression progression) async {
    final file = await _progressionFile();
    await file.writeAsString(jsonEncode(progression.toJson()));
  }

  /// CEFR 토큰을 0~100 시작 점수로 매핑한다. 6개 CEFR 레벨을 0~100 구간에
  /// 균등 배치한다: A1=0, A2=20, B1=40, B2=60, C1=80, C2=100 — 이미 C2
  /// (거의 원어민 수준)로 시작한 학습자는 더 올라갈 여지가 거의 없다는
  /// 뜻이고, A1부터 시작한 학습자는 1년에 걸쳐 딱 그 지점(마스터,
  /// 100점=C2 상한)까지 올라간다는 뜻이다. 인식하지 못하는 값(레벨
  /// 테스트를 거치지 않은 등)은 `GeminiService`의 다른 폴백과 동일하게
  /// 중급(B1=40)으로 취급한다.
  /// [cefr]: `config.difficultyLevel`에 저장된 CEFR 토큰(또는 `null`).
  /// 반환값: 0~100 사이의 시작 난이도 점수.
  double _initialScoreForCefr(String? cefr) {
    switch (cefr) {
      case 'A1':
        return 0;
      case 'A2':
        return 20;
      case 'B1':
        return 40;
      case 'B2':
        return 60;
      case 'C1':
        return 80;
      case 'C2':
        return 100;
      default:
        return 40;
    }
  }

  /// 오늘의 연속(0~100) 난이도 점수를 계산해 반환한다.
  ///
  /// 현재 대상 언어에 대한 진행 기록이 아직 없으면(그 언어를 처음
  /// 시작하는 시점 — 사실상 항상 레벨 테스트 직후 첫 학습 세트 생성
  /// 시점과 일치한다) 그 자리에서 `config.difficultyLevel`을
  /// [_initialScoreForCefr]로 시작 점수로 매핑하고 오늘 날짜(태평양
  /// 기준)를 `startDate`로 기록해 새로 만든다. 이미 기록이 있으면(재개나
  /// 반복 방문) 그 `startDate`/`initialScore`를 그대로 유지한다 — 언어를
  /// 바꿨다가 돌아와도 진행률이 끊기지 않는다는 뜻이다.
  ///
  /// 계산식:
  /// ```
  /// 경과일수 = 오늘(태평양 날짜) - startDate(태평양 날짜)
  /// 진행률 = min(경과일수 / 365, 1.0)
  /// 오늘의난이도점수 = initialScore + (100 - initialScore) * 진행률
  /// ```
  /// 365일(1년)이 지나면 진행률이 1.0에 고정되어, 그 이후로는 항상
  /// [kMasterScore](100점)를 반환한다.
  ///
  /// `TopicInputDialog`가 `GeminiService.generateDailySentenceSet`을
  /// 호출하기 직전에 호출한다.
  /// 반환값: 0~100 범위의 오늘의 연속 난이도 점수.
  /// 부작용: 이 언어의 진행 기록이 처음이면 progression.json을 새로
  /// 만든다.
  Future<double> readTodayScore() async {
    var progression = await _read();
    if (progression == null) {
      final config = await _configService.readConfig();
      progression = DifficultyProgression(
        startDate: DateTime.now(),
        initialScore: _initialScoreForCefr(config.difficultyLevel),
      );
      await _write(progression);
    }

    final elapsedDays = _dayBoundaryService
        .pacificDateOf(DateTime.now())
        .difference(_dayBoundaryService.pacificDateOf(progression.startDate))
        .inDays;
    final progressRatio = (elapsedDays / kProgressionDays).clamp(0.0, 1.0);
    return progression.initialScore + (kMasterScore - progression.initialScore) * progressRatio;
  }

  /// Deletes every language's progression record. Used by the `RESET_APP`
  /// dev/test flag and Settings' "Reset All Data".
  /// (모든 언어의 진행 기록을 삭제한다. `main.dart`의 `RESET_APP`
  /// 개발/테스트용 플래그와 Settings 화면의 "Reset All Data"
  /// (`SettingsViewModel`)에서 사용된다.)
  /// 부작용: `difficulty_progression` 디렉터리 전체를 재귀적으로 삭제한다.
  Future<void> clearAllLanguages() async {
    final dir = await _rootDir();
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }
}
