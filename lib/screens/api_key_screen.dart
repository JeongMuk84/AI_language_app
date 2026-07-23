import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';
import '../viewmodels/api_key_view_model.dart';
import '../viewmodels/theme_mode_view_model.dart';

/// 온보딩의 첫 단계 화면. 라우트 `/api-key`(`AppRoutes.apiKey`, 라우터의
/// `initialLocation`이기도 함)에 연결되며, AppRouter의 redirect 로직은
/// `apiKeyStorage.hasApiKey()`가 false인 동안 항상 이 화면으로 보낸다.
/// 학습자가 Gemini API 키를 입력하도록 하고 [ApiKeyViewModel]을 통해 검증 및
/// 저장하며, `themeModeProvider`도 watch해 화이트/블랙 테마 전환 버튼을
/// 보여준다.
class ApiKeyScreen extends ConsumerStatefulWidget {
  const ApiKeyScreen({super.key});

  /// 이 위젯의 상태 객체([_ApiKeyScreenState])를 생성한다.
  @override
  ConsumerState<ApiKeyScreen> createState() => _ApiKeyScreenState();
}

/// [ApiKeyScreen]의 State. API 키 입력 텍스트필드 컨트롤러와 키 가리기/보이기
/// 토글 상태를 로컬로 관리한다.
class _ApiKeyScreenState extends ConsumerState<ApiKeyScreen> {
  final _controller = TextEditingController();
  bool _obscure = true;

  /// 위젯이 트리에서 제거될 때 [_controller]를 해제해 메모리 누수를 막는다.
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// "Get a Gemini API Key" 버튼이 눌리면 호출되어, Google AI Studio의 API
  /// 키 발급 페이지를 외부 브라우저로 연다.
  Future<void> _openApiKeyPage() async {
    final uri = Uri.parse('https://aistudio.google.com/apikey');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// Submit 버튼이 눌리면 호출된다. [ApiKeyViewModel.submit]으로 입력된 키를
  /// 검증/저장하고, 성공하면(`ok == true`) `context.go('/')`로 이동해
  /// 라우터의 redirect가 다음 온보딩 단계(언어 선택)를 결정하도록 한다.
  Future<void> _submit() async {
    final ok = await ref.read(apiKeyViewModelProvider.notifier).submit(_controller.text);
    if (ok && mounted) {
      context.go('/');
    }
  }

  /// [ApiKeyViewModel]과 `themeModeProvider`를 watch해 API 키 입력 화면
  /// UI(테마 선택, 키 입력 필드, 발급 페이지 링크, Submit 버튼, 에러 메시지)를
  /// 그린다.
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(apiKeyViewModelProvider);
    final currentThemeMode = ref.watch(themeModeProvider).value ?? AppThemeMode.black;

    return Scaffold(
      appBar: AppBar(title: const Text('Enter your Gemini API Key')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: SegmentedButton<AppThemeMode>(
                  segments: const [
                    ButtonSegment(value: AppThemeMode.white, label: Text('White')),
                    ButtonSegment(value: AppThemeMode.black, label: Text('Black')),
                  ],
                  selected: {currentThemeMode},
                  onSelectionChanged: (selection) {
                    ref.read(themeModeProvider.notifier).setThemeMode(selection.first);
                  },
                ),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _controller,
                obscureText: _obscure,
                enabled: !state.isSubmitting,
                decoration: InputDecoration(
                  labelText: 'Gemini API Key',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: state.isSubmitting ? null : _openApiKeyPage,
                child: const Text('Get a Gemini API Key'),
              ),
              const SizedBox(height: 24),
              if (state.errorMessage != null) ...[
                Text(
                  state.errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                const SizedBox(height: 12),
              ],
              FilledButton(
                onPressed: state.isSubmitting ? null : _submit,
                child: state.isSubmitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Submit'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
