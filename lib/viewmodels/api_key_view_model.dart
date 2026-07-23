import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/service_providers.dart';
import '../services/gemini_service.dart';

/// ApiKeyScreen이 watch하는 UI 상태. Gemini API 키 제출 화면에서 "제출 중인지"와
/// "에러 메시지가 있는지"만 표현하는 단순한 State 클래스다.
class ApiKeyState {
  const ApiKeyState({this.isSubmitting = false, this.errorMessage});

  /// [ApiKeyViewModel.submit]이 API 키 검증을 진행하는 동안 true가 되어,
  /// ApiKeyScreen의 Submit 버튼을 비활성화하고 로딩 인디케이터를 보여주게 한다.
  final bool isSubmitting;

  /// 키 검증/저장이 실패했을 때 사용자에게 보여줄 에러 메시지. ApiKeyScreen에서
  /// 이 값이 null이 아니면 에러 텍스트를 표시한다.
  final String? errorMessage;

  /// [isSubmitting]과 [errorMessage]를 갱신한 새 ApiKeyState를 반환한다.
  /// `errorMessage`는 인자를 넘기지 않으면 항상 null로 초기화된다(이전 값을
  /// 유지하지 않음) — 새 시도를 시작할 때 이전 에러가 남아있지 않도록 하기 위함이다.
  ApiKeyState copyWith({bool? isSubmitting, String? errorMessage}) {
    return ApiKeyState(
      isSubmitting: isSubmitting ?? this.isSubmitting,
      errorMessage: errorMessage,
    );
  }
}

/// ApiKeyScreen(라우트 `/api-key`, 온보딩의 첫 단계)을 지원하는 뷰모델.
/// Gemini API 키를 검증하고 `flutter_secure_storage` 기반 저장소에 저장하는
/// 역할을 한다. AppRouter의 redirect 로직은 `apiKeyStorage.hasApiKey()`가
/// false인 동안 항상 이 화면으로 보내며, 이 뷰모델이 저장에 성공하면 그
/// 게이트가 풀려 다음 온보딩 단계(언어 선택)로 넘어갈 수 있게 된다.
class ApiKeyViewModel extends Notifier<ApiKeyState> {
  /// 초기 상태(제출 중 아님, 에러 없음)를 생성한다. Riverpod이 이 provider가
  /// 처음 watch/read될 때 자동으로 호출한다.
  @override
  ApiKeyState build() => const ApiKeyState();

  /// ApiKeyScreen의 Submit 버튼이 눌리면 호출된다. 입력값을 trim한 뒤
  /// 비어 있으면 즉시 에러 메시지를 세팅하고 false를 반환한다. 그렇지 않으면
  /// `GeminiService.validateApiKey`로 실제 Gemini API를 호출해 키가 유효한지
  /// 확인하고, 성공 시 `apiKeyStorageServiceProvider`(flutter_secure_storage)에
  /// 키를 저장한 뒤 true를 반환한다. 실패 시에는 실패 사유를 사용자용 메시지로
  /// 변환해 [ApiKeyState.errorMessage]에 담고 false를 반환한다.
  ///
  /// 반환값이 true이면 ApiKeyScreen은 `context.go('/')`로 이동해 라우터의
  /// redirect가 다음 온보딩 단계를 결정하도록 한다.
  Future<bool> submit(String apiKey) async {
    final trimmed = apiKey.trim();
    if (trimmed.isEmpty) {
      state = state.copyWith(errorMessage: 'Please enter an API key.');
      return false;
    }

    state = state.copyWith(isSubmitting: true, errorMessage: null);
    final result = await ref.read(geminiServiceProvider).validateApiKey(trimmed);

    if (result.success) {
      await ref.read(apiKeyStorageServiceProvider).saveApiKey(trimmed);
      state = state.copyWith(isSubmitting: false, errorMessage: null);
      return true;
    }

    state = state.copyWith(
      isSubmitting: false,
      errorMessage: userMessageForFailure(result.reason!, result.rawError),
    );
    return false;
  }
}

/// [ApiKeyViewModel]/[ApiKeyState]를 노출하는 provider. ApiKeyScreen에서
/// `ref.watch`(상태 렌더링)와 `ref.read(...notifier)`(submit 호출)로 사용된다.
final apiKeyViewModelProvider = NotifierProvider<ApiKeyViewModel, ApiKeyState>(
  ApiKeyViewModel.new,
);
