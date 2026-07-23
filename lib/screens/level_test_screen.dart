import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/level_test_question.dart';
import '../viewmodels/level_test_view_model.dart';
import '../widgets/app_bar_with_settings.dart';
import '../widgets/reset_api_key_button.dart';

/// 온보딩의 세 번째 단계 화면. 라우트 `/level-test`(`AppRoutes.levelTest`)에
/// 연결되며, AppRouter의 redirect 로직은 언어는 선택했지만
/// `config.hasDifficultyLevel`이 false이고(그리고 이어서 학습할 만한 handoff
/// 데이터도 없을 때) 이 화면으로 보낸다. [LevelTestViewModel]을 통해 Gemini가
/// 생성한 레벨 테스트 문제를 보여주고 답안을 채점해 난이도 레벨을 저장한다.
class LevelTestScreen extends ConsumerStatefulWidget {
  const LevelTestScreen({super.key});

  /// 이 위젯의 상태 객체([_LevelTestScreenState])를 생성한다.
  @override
  ConsumerState<LevelTestScreen> createState() => _LevelTestScreenState();
}

/// [LevelTestScreen]의 State. 문항 수만큼의 답안 입력 텍스트필드
/// 컨트롤러 목록을 로컬로 관리한다.
class _LevelTestScreenState extends ConsumerState<LevelTestScreen> {
  List<TextEditingController> _controllers = [];

  /// 화면이 처음 마운트될 때 [LevelTestViewModel.loadQuestions]를 호출해
  /// 레벨 테스트 문제를 불러오기 시작한다.
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(levelTestViewModelProvider.notifier).loadQuestions());
  }

  /// 위젯이 트리에서 제거될 때 [_controllers]에 남아있는 모든 컨트롤러를
  /// 해제해 메모리 누수를 막는다.
  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  /// [questions] 개수에 맞춰 [_controllers] 목록 길이를 맞춘다. 이미 개수가
  /// 같으면 아무 것도 하지 않고, 다르면(문제가 새로 로드된 경우) 기존
  /// 컨트롤러를 모두 해제하고 새로 생성한다. `build()`가 매번 호출한다.
  void _syncControllers(List<LevelTestQuestion> questions) {
    if (_controllers.length == questions.length) return;
    for (final c in _controllers) {
      c.dispose();
    }
    _controllers = List.generate(questions.length, (_) => TextEditingController());
  }

  /// Submit 버튼이 눌리면 호출된다. 각 텍스트필드의 최신 값을
  /// [LevelTestViewModel.updateAnswer]로 반영한 뒤 `submit()`으로 채점을
  /// 요청한다. 성공하면(`ok == true`) `context.go('/')`로 이동해 라우터의
  /// redirect가 다음 단계(학습 화면)를 결정하도록 한다.
  Future<void> _submit() async {
    final notifier = ref.read(levelTestViewModelProvider.notifier);
    for (var i = 0; i < _controllers.length; i++) {
      notifier.updateAnswer(i, _controllers[i].text);
    }
    final ok = await notifier.submit();
    if (ok && mounted) {
      context.go('/');
    }
  }

  /// [LevelTestViewModel]을 watch해 현재 단계([LevelTestStage])에 맞는
  /// UI(로딩, 로드 에러+재시도, 또는 실제 문제 목록과 Submit 버튼)를 그린다.
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(levelTestViewModelProvider);

    if (state.stage == LevelTestStage.loading) {
      return Scaffold(
        appBar: buildAppBarWithSettings(context, 'Level Test'),
        body: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Preparing your level test...'),
            ],
          ),
        ),
      );
    }

    if (state.stage == LevelTestStage.loadError) {
      return Scaffold(
        appBar: buildAppBarWithSettings(context, 'Level Test'),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  state.loadErrorMessage ?? 'Failed to load the level test.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => ref.read(levelTestViewModelProvider.notifier).loadQuestions(),
                  child: const Text('Retry'),
                ),
                const SizedBox(height: 12),
                const ResetApiKeyButton(),
              ],
            ),
          ),
        ),
      );
    }

    _syncControllers(state.questions);

    return Scaffold(
      appBar: buildAppBarWithSettings(context, 'Level Test'),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(24),
                itemCount: state.questions.length,
                separatorBuilder: (_, _) => const SizedBox(height: 20),
                itemBuilder: (context, index) {
                  final question = state.questions[index];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        question.direction,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(question.prompt, style: Theme.of(context).textTheme.bodyLarge),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _controllers[index],
                        enabled: !state.isSubmitting,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          hintText: 'Your translation',
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            if (state.submitErrorMessage != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  state.submitErrorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: FilledButton(
                onPressed: state.isSubmitting ? null : _submit,
                child: state.isSubmitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Submit'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
