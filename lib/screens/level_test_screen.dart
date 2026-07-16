import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/level_test_question.dart';
import '../viewmodels/level_test_view_model.dart';
import '../widgets/app_bar_with_settings.dart';

class LevelTestScreen extends ConsumerStatefulWidget {
  const LevelTestScreen({super.key});

  @override
  ConsumerState<LevelTestScreen> createState() => _LevelTestScreenState();
}

class _LevelTestScreenState extends ConsumerState<LevelTestScreen> {
  List<TextEditingController> _controllers = [];

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(levelTestViewModelProvider.notifier).loadQuestions());
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _syncControllers(List<LevelTestQuestion> questions) {
    if (_controllers.length == questions.length) return;
    for (final c in _controllers) {
      c.dispose();
    }
    _controllers = List.generate(questions.length, (_) => TextEditingController());
  }

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
