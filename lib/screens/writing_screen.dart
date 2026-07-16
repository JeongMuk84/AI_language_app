import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../viewmodels/writing_view_model.dart';
import '../widgets/app_bar_with_settings.dart';
import '../widgets/feedback_box.dart';

class WritingScreen extends ConsumerStatefulWidget {
  const WritingScreen({super.key});

  @override
  ConsumerState<WritingScreen> createState() => _WritingScreenState();
}

class _WritingScreenState extends ConsumerState<WritingScreen> {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(writingViewModelProvider.notifier).loadSentence());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() {
    return ref.read(writingViewModelProvider.notifier).submitTranslation(_controller.text);
  }

  void _retry() {
    _controller.clear();
    ref.read(writingViewModelProvider.notifier).resetTranslationAttempt();
  }

  void _goToListening() {
    context.go('/learning/writing/listening');
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(writingViewModelProvider);

    if (state.isLoadingSentence) {
      return Scaffold(
        appBar: buildAppBarWithSettings(context, 'Writing: Translate'),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (state.loadError != null) {
      return Scaffold(
        appBar: buildAppBarWithSettings(context, 'Writing: Translate'),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(state.loadError!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => ref.read(writingViewModelProvider.notifier).loadSentence(),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: buildAppBarWithSettings(context, 'Writing: Translate'),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                state.nativeSentence ?? '',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _controller,
                enabled: !state.isSubmittingTranslation,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Write your translation',
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: state.isSubmittingTranslation ? null : _submit,
                child: state.isSubmittingTranslation
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Submit'),
              ),
              if (state.translationError != null) ...[
                const SizedBox(height: 16),
                Text(
                  state.translationError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              if (state.translationResult != null) ...[
                const SizedBox(height: 16),
                FeedbackBox(
                  feedback: state.translationResult!.feedback,
                  isCorrect: state.translationResult!.isCorrect,
                ),
              ],
              const SizedBox(height: 24),
              OutlinedButton(onPressed: _retry, child: const Text('Try Again')),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: state.canProceedToListening ? _goToListening : null,
                child: const Text('Continue to Listening Practice'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
