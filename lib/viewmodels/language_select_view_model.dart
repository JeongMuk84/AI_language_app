import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/service_providers.dart';

/// LanguageSelectScreen이 watch하는 UI 상태. 모국어/학습할 언어 선택 화면에서
/// "제출 중인지"와 "에러 메시지가 있는지"만 표현하는 단순한 State 클래스다.
class LanguageSelectState {
  const LanguageSelectState({this.isSubmitting = false, this.errorMessage});

  /// [LanguageSelectViewModel.confirm]이 언어 정보를 저장하는 동안 true가
  /// 되어, LanguageSelectScreen의 Confirm 버튼을 비활성화하고 로딩 인디케이터를
  /// 보여주게 한다.
  final bool isSubmitting;

  /// 입력값 검증에 실패했을 때 사용자에게 보여줄 에러 메시지.
  /// LanguageSelectScreen에서 이 값이 null이 아니면 에러 텍스트를 표시한다.
  final String? errorMessage;

  /// [isSubmitting]과 [errorMessage]를 갱신한 새 LanguageSelectState를
  /// 반환한다. `errorMessage`는 인자를 넘기지 않으면 항상 null로 초기화된다.
  LanguageSelectState copyWith({bool? isSubmitting, String? errorMessage}) {
    return LanguageSelectState(
      isSubmitting: isSubmitting ?? this.isSubmitting,
      errorMessage: errorMessage,
    );
  }
}

/// LanguageSelectScreen(라우트 `/language-select`, 온보딩 두 번째 단계)을
/// 지원하는 뷰모델. 모국어(native language)와 학습할 언어(target language)를
/// `configServiceProvider`를 통해 config.json에 저장한다. AppRouter의
/// redirect 로직은 `config.hasLanguages`가 false인 동안 이 화면으로 보내며,
/// 저장에 성공하면 다음 온보딩 단계(레벨 테스트)로 넘어갈 수 있게 된다.
class LanguageSelectViewModel extends Notifier<LanguageSelectState> {
  /// 초기 상태(제출 중 아님, 에러 없음)를 생성한다. Riverpod이 이 provider가
  /// 처음 watch/read될 때 자동으로 호출한다.
  @override
  LanguageSelectState build() => const LanguageSelectState();

  /// LanguageSelectScreen의 Confirm 버튼이 눌리면 호출된다. 두 입력값을
  /// trim한 뒤 하나라도 비어 있으면 에러 메시지를 세팅하고 false를 반환한다.
  /// 그렇지 않으면 `configServiceProvider.updateConfig`로 두 언어를
  /// config.json에 저장하고 true를 반환한다.
  ///
  /// 반환값이 true이면 LanguageSelectScreen은 `context.go('/')`로 이동해
  /// 라우터의 redirect가 다음 온보딩 단계를 결정하도록 한다.
  Future<bool> confirm(String nativeLanguage, String targetLanguage) async {
    final native = nativeLanguage.trim();
    final target = targetLanguage.trim();
    if (native.isEmpty || target.isEmpty) {
      state = state.copyWith(errorMessage: 'Please fill in both languages.');
      return false;
    }

    state = state.copyWith(isSubmitting: true, errorMessage: null);
    await ref.read(configServiceProvider).updateConfig(
          (current) => current.copyWith(nativeLanguage: native, targetLanguage: target),
        );
    state = state.copyWith(isSubmitting: false, errorMessage: null);
    return true;
  }
}

/// [LanguageSelectViewModel]/[LanguageSelectState]를 노출하는 provider.
/// LanguageSelectScreen에서 `ref.watch`(상태 렌더링)와
/// `ref.read(...notifier)`(confirm 호출)로 사용된다.
final languageSelectViewModelProvider =
    NotifierProvider<LanguageSelectViewModel, LanguageSelectState>(
  LanguageSelectViewModel.new,
);
