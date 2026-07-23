import 'dart:convert';
import 'dart:io';

import '../models/handoff_data.dart';
import 'storage_location_service.dart';

/// 앱의 저장 디렉터리(`StorageLocationService` 참고) 안에 언어별
/// 핸드오프(handoff) 파일(`handoff_<language>.json`)을 읽고 쓰는 서비스.
/// 이전에 공부했던 언어로 돌아왔을 때 레벨 테스트를 다시 치르지 않고 재개할
/// 수 있도록 요약/난이도 정보를 저장해둔다.
///
/// `handoffServiceProvider`(`service_providers.dart`)를 통해 Riverpod
/// provider로 노출되며, `app_router.dart`의 라우팅 redirect 로직과
/// `SettingsViewModel`이 사용한다.
class HandoffService {
  HandoffService({StorageLocationService? storageLocationService})
      : _storageLocationService = storageLocationService ?? StorageLocationService();

  final StorageLocationService _storageLocationService;

  /// [language]에 해당하는 핸드오프 파일의 `File` 핸들을 만든다. 실제 존재
  /// 여부는 확인하지 않으며, 슬러그화된 파일명 경로만 계산한다. 이 클래스의
  /// 다른 메서드들이 내부적으로 사용하는 헬퍼다.
  Future<File> _fileFor(String language) async {
    final dir = await _storageLocationService.baseDirectory();
    return File('${dir.path}/handoff_${_slug(language)}.json');
  }

  /// [language] 이름을 파일명에 안전하게 쓸 수 있는 형태로 변환한다(소문자화,
  /// 앞뒤 공백 제거, 내부 공백은 `_`로 치환). [_fileFor]가 파일 경로를 만들
  /// 때 호출한다.
  /// 반환값: 슬러그화된 문자열(예: `"north korean"` -> `"north_korean"`).
  String _slug(String language) =>
      language.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '_');

  /// [language]에 대한 핸드오프 파일이 존재하는지 확인한다.
  /// [language]: 확인할 언어 이름.
  /// 반환값: 해당 언어의 핸드오프 파일이 있으면 `true`.
  Future<bool> exists(String language) async => (await _fileFor(language)).exists();

  /// [language]의 핸드오프 데이터를 읽어온다. 파일이 없거나 내용이 비어있으면
  /// `null`을 반환한다. `app_router.dart`의 라우팅 redirect 로직이, 대상
  /// 언어에 아직 난이도 레벨이 없을 때 이전에 저장된 핸드오프(요약/난이도)가
  /// 있는지 확인해 레벨 테스트를 건너뛸 수 있는지 판단하기 위해 호출한다.
  /// [language]: 조회할 언어 이름.
  /// 반환값: 저장된 [HandoffData], 없으면 `null`.
  Future<HandoffData?> read(String language) async {
    final file = await _fileFor(language);
    if (!await file.exists()) return null;
    final content = await file.readAsString();
    if (content.trim().isEmpty) return null;
    return HandoffData.fromJson(jsonDecode(content) as Map<String, dynamic>);
  }

  /// [language]에 대한 핸드오프 데이터를 파일에 저장(덮어쓰기)한다.
  /// `SettingsViewModel`이 세션을 마무리/전환할 때, `GeminiService`로 생성한
  /// 요약과 현재 난이도를 [HandoffData]로 묶어 저장할 때 호출한다.
  /// [language]: 저장 대상 언어 이름.
  /// [data]: 저장할 핸드오프 데이터(요약, 난이도 등).
  /// 부작용: 파일 시스템에 `handoff_<language>.json`을 쓴다.
  Future<void> write(String language, HandoffData data) async {
    final file = await _fileFor(language);
    await file.writeAsString(jsonEncode(data.toJson()));
  }

  /// Deletes every language's handoff file. Used by the `RESET_APP` dev/
  /// test flag and Settings' "Reset All Data".
  /// (모든 언어의 핸드오프 파일을 삭제한다. `main.dart`의 `RESET_APP`
  /// 개발/테스트용 플래그와 Settings 화면의 "Reset All Data"
  /// (`SettingsViewModel`)에서 호출된다.)
  /// 부작용: 저장 디렉터리에서 `handoff_`로 시작하고 `.json`으로 끝나는
  /// 모든 파일을 삭제한다.
  Future<void> clearHandoffFiles() async {
    final dir = await _storageLocationService.baseDirectory();
    final entries = await dir.list().toList();
    for (final entry in entries) {
      if (entry is! File) continue;
      final name = _basename(entry.path);
      if (name.startsWith('handoff_') && name.endsWith('.json')) {
        await entry.delete();
      }
    }
  }

  /// 전체 경로 문자열에서 파일명만 추출한다(윈도우/유닉스 구분자 모두
  /// 처리). [clearHandoffFiles]가 디렉터리 안의 각 엔트리가 핸드오프
  /// 파일인지 판단할 때 호출하는 헬퍼다.
  /// [path]: 전체 파일 경로.
  /// 반환값: 경로의 마지막 구성요소(파일명)만 남긴 문자열.
  String _basename(String path) {
    final normalized = path.replaceAll('\\', '/');
    return normalized.substring(normalized.lastIndexOf('/') + 1);
  }
}
