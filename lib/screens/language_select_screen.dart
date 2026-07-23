import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../viewmodels/language_select_view_model.dart';
import '../widgets/app_bar_with_settings.dart';

/// 온보딩의 두 번째 단계 화면. 라우트 `/language-select`(`AppRoutes.languageSelect`)에
/// 연결되며, AppRouter의 redirect 로직은 API 키는 있지만
/// `config.hasLanguages`가 false인 동안 이 화면으로 보낸다. 학습자가
/// 모국어와 학습할 언어를 입력하도록 하고 [LanguageSelectViewModel]을 통해
/// config.json에 저장한다.
class LanguageSelectScreen extends ConsumerStatefulWidget {
  const LanguageSelectScreen({super.key});

  /// 이 위젯의 상태 객체([_LanguageSelectScreenState])를 생성한다.
  @override
  ConsumerState<LanguageSelectScreen> createState() => _LanguageSelectScreenState();
}

/// [LanguageSelectScreen]의 State. 모국어/학습 언어 입력 텍스트필드
/// 컨트롤러 두 개를 로컬로 관리한다.
class _LanguageSelectScreenState extends ConsumerState<LanguageSelectScreen> {
  final _nativeController = TextEditingController();
  final _targetController = TextEditingController();

  /// 위젯이 트리에서 제거될 때 두 컨트롤러를 해제해 메모리 누수를 막는다.
  @override
  void dispose() {
    _nativeController.dispose();
    _targetController.dispose();
    super.dispose();
  }

  /// Confirm 버튼이 눌리면 호출된다. [LanguageSelectViewModel.confirm]으로
  /// 두 언어를 저장하고, 성공하면(`ok == true`) `context.go('/')`로 이동해
  /// 라우터의 redirect가 다음 온보딩 단계(레벨 테스트)를 결정하도록 한다.
  Future<void> _confirm() async {
    final ok = await ref
        .read(languageSelectViewModelProvider.notifier)
        .confirm(_nativeController.text, _targetController.text);
    if (ok && mounted) {
      context.go('/');
    }
  }

  /// [LanguageSelectViewModel]을 watch해 언어 선택 화면 UI(모국어/학습 언어
  /// 입력 필드, Confirm 버튼, 에러 메시지)를 그린다.
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(languageSelectViewModelProvider);

    return Scaffold(
      appBar: buildAppBarWithSettings(context, 'Select Languages'),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Native language'),
              const SizedBox(height: 8),
              TextField(
                controller: _nativeController,
                enabled: !state.isSubmitting,
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
              const SizedBox(height: 24),
              const Text('Language to learn'),
              const SizedBox(height: 8),
              TextField(
                controller: _targetController,
                enabled: !state.isSubmitting,
                decoration: const InputDecoration(border: OutlineInputBorder()),
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
                onPressed: state.isSubmitting ? null : _confirm,
                child: state.isSubmitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Confirm'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
