import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/service_providers.dart';
import '../services/gemini_service.dart';

class ApiKeyState {
  const ApiKeyState({this.isSubmitting = false, this.errorMessage});

  final bool isSubmitting;
  final String? errorMessage;

  ApiKeyState copyWith({bool? isSubmitting, String? errorMessage}) {
    return ApiKeyState(
      isSubmitting: isSubmitting ?? this.isSubmitting,
      errorMessage: errorMessage,
    );
  }
}

class ApiKeyViewModel extends Notifier<ApiKeyState> {
  @override
  ApiKeyState build() => const ApiKeyState();

  /// Returns true if the key was validated and saved successfully.
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

final apiKeyViewModelProvider = NotifierProvider<ApiKeyViewModel, ApiKeyState>(
  ApiKeyViewModel.new,
);
