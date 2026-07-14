import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/service_providers.dart';

class LanguageSelectState {
  const LanguageSelectState({this.isSubmitting = false, this.errorMessage});

  final bool isSubmitting;
  final String? errorMessage;

  LanguageSelectState copyWith({bool? isSubmitting, String? errorMessage}) {
    return LanguageSelectState(
      isSubmitting: isSubmitting ?? this.isSubmitting,
      errorMessage: errorMessage,
    );
  }
}

class LanguageSelectViewModel extends Notifier<LanguageSelectState> {
  @override
  LanguageSelectState build() => const LanguageSelectState();

  /// Returns true if both languages were saved successfully.
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

final languageSelectViewModelProvider =
    NotifierProvider<LanguageSelectViewModel, LanguageSelectState>(
  LanguageSelectViewModel.new,
);
