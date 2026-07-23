import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Gemini API key를 `flutter_secure_storage`에 저장/조회하는 서비스.
/// "키가 설정되어 있는가"를 판단하는 유일한 기준(single source of truth)이며,
/// `config.json`(`ConfigService`)에는 절대 이 값을 복사해 넣지 않는다.
class ApiKeyStorageService {
  static const _apiKeyStorageKey = 'gemini_api_key';

  final _storage = const FlutterSecureStorage();

  /// secure storage에서 저장된 Gemini API 키를 읽어온다.
  ///
  /// [hasApiKey]가 내부적으로 호출하며, `GeminiService`가 실제 Gemini API를
  /// 호출하기 직전 요청 헤더/쿼리에 넣을 키를 얻기 위해 호출한다
  /// (`gemini_service.dart`의 API 호출 준비 로직).
  /// 반환값: 저장된 키 문자열, 없으면 `null`.
  Future<String?> readApiKey() => _storage.read(key: _apiKeyStorageKey);

  /// 입력받은 [apiKey]를 secure storage에 저장(덮어쓰기)한다.
  ///
  /// `ApiKeyViewModel`(`api_key_view_model.dart`)에서 사용자가 최초 API 키
  /// 입력 화면에서 키를 제출했을 때 호출된다.
  Future<void> saveApiKey(String apiKey) =>
      _storage.write(key: _apiKeyStorageKey, value: apiKey);

  /// API 키가 저장되어 있고 비어있지 않은지 확인한다.
  ///
  /// `app_router.dart`의 라우터 redirect 로직에서 호출되어, 키가 없으면
  /// API 키 입력 화면으로 보내고 있으면 다음 화면으로 진행시키는 판단 기준으로
  /// 쓰인다.
  /// 반환값: 유효한(공백이 아닌) 키가 저장되어 있으면 `true`.
  Future<bool> hasApiKey() async {
    final value = await readApiKey();
    return value != null && value.trim().isNotEmpty;
  }

  /// 이 앱이 secure storage에 기록한 모든 값(현재는 API 키 하나뿐)을 지운다.
  /// `main.dart`의 `RESET_APP`/`RESET_KEY` 개발·테스트용 플래그, 그리고
  /// Settings 화면의 "Reset All Data"(`reset_api_key_button.dart`,
  /// `settings_view_model.dart`)에서 호출된다.
  /// 부작용: secure storage 전체를 삭제한다(`deleteAll`).
  Future<void> clearApiKey() => _storage.deleteAll();
}
