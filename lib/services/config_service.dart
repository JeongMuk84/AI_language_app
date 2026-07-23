import 'dart:convert';
import 'dart:io';

import '../models/app_config.dart';
import 'storage_location_service.dart';

/// 앱의 저장 디렉터리(`StorageLocationService` 참고) 안에 있는 `config.json`을
/// 읽고 쓰는 서비스.
///
/// Gemini API 키는 절대 여기에 저장하지 않는다 — 그것은 secure storage
/// (`ApiKeyStorageService` 참고)의 몫이다.
///
/// `configServiceProvider`(`service_providers.dart`)를 통해 Riverpod
/// provider로 노출되며, `SettingsViewModel`, `ThemeModeViewModel`,
/// `LevelTestViewModel`, `ReviewViewModel`, `LanguageSelectViewModel`,
/// `GeminiService`, `ConversationHistoryService`, `ListeningHistoryService`,
/// `ReviewSessionService`, `ReviewHistoryService`, `StorageLocationService`
/// 등 앱 전반의 화면/뷰모델/서비스에서 현재 설정(대상 언어, 난이도, 테마 등)을
/// 읽거나 갱신하기 위해 사용한다.
class ConfigService {
  ConfigService({StorageLocationService? storageLocationService})
      : _storageLocationService = storageLocationService ?? StorageLocationService();

  final StorageLocationService _storageLocationService;

  /// `config.json`이 위치할 `File` 핸들을 만든다. 파일이 실제로 존재하는지는
  /// 확인하지 않으며, 저장 디렉터리(`StorageLocationService.baseDirectory`)
  /// 아래의 경로만 계산한다. 이 클래스의 다른 모든 메서드가 내부적으로
  /// 사용하는 헬퍼다.
  Future<File> _configFile() async {
    final dir = await _storageLocationService.baseDirectory();
    return File('${dir.path}/config.json');
  }

  /// config.json의 전체 경로 문자열을 반환한다. 진단/로깅 용도로,
  /// `main.dart` 시작 시 디버그 로그에 현재 config.json 위치를 출력할 때
  /// 호출된다.
  Future<String> configFilePath() async => (await _configFile()).path;

  /// config.json 파일이 있으면 삭제한다. `main.dart`의 `RESET_APP`
  /// 개발/테스트용 플래그와 Settings 화면의 "Reset All Data"
  /// (`SettingsViewModel`)에서 호출된다.
  /// 부작용: 파일 시스템에서 config.json을 삭제한다.
  Future<void> clearConfig() async {
    final file = await _configFile();
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// config.json을 읽어 [AppConfig]로 파싱해 반환한다. 파일이 없으면 빈
  /// `{}` 내용으로 새로 만들고 기본값의 `AppConfig`를 반환하며, 내용이
  /// 비어있어도 마찬가지로 기본값을 반환한다. 앱 전반에서 현재 설정값
  /// (대상 언어, 난이도, 테마, 세션 상태 등)을 조회할 때 가장 많이 호출되는
  /// 메서드로, 예를 들어 `app_router.dart`의 라우팅 판단, `GeminiService`의
  /// 프롬프트 구성, 각 뷰모델의 초기 로드 등에서 쓰인다.
  /// 부작용: 파일이 없을 경우 새로 생성한다.
  /// 반환값: 파싱된 [AppConfig] 인스턴스.
  Future<AppConfig> readConfig() async {
    final file = await _configFile();
    if (!await file.exists()) {
      await file.writeAsString('{}');
      return AppConfig.fromJson(const {});
    }
    final content = await file.readAsString();
    if (content.trim().isEmpty) {
      return AppConfig.fromJson(const {});
    }
    final decoded = jsonDecode(content) as Map<String, dynamic>;
    return AppConfig.fromJson(decoded);
  }

  /// [config]를 JSON으로 직렬화해 config.json에 그대로 덮어쓴다.
  /// `SettingsViewModel.save` 등에서 설정 전체를 새 값으로 교체할 때
  /// 호출된다.
  /// 부작용: config.json 파일 내용을 [config]로 덮어쓴다.
  Future<void> writeConfig(AppConfig config) async {
    final file = await _configFile();
    await file.writeAsString(jsonEncode(config.toJson()));
  }

  /// 현재 설정을 읽어 [update] 콜백으로 변형한 뒤 다시 저장하는 read-modify-write
  /// 헬퍼. 설정의 일부 필드만 바꾸고 싶은 대부분의 호출부(예:
  /// `ThemeModeViewModel`의 테마 변경, `LevelTestViewModel`의 난이도 저장,
  /// `LanguageSelectViewModel`의 언어 전환, `app_router.dart`의 리다이렉트
  /// 처리)가 [readConfig]+[writeConfig]를 직접 조합하는 대신 이 메서드를
  /// 사용한다.
  /// [update]: 현재 [AppConfig]를 받아 새 [AppConfig]를 반환하는 변경 함수.
  /// 부작용: config.json을 갱신된 값으로 덮어쓴다.
  Future<void> updateConfig(AppConfig Function(AppConfig current) update) async {
    final current = await readConfig();
    await writeConfig(update(current));
  }
}
