import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../viewmodels/language_select_view_model.dart';
import '../widgets/settings_icon_button.dart';

class LanguageSelectScreen extends ConsumerStatefulWidget {
  const LanguageSelectScreen({super.key});

  @override
  ConsumerState<LanguageSelectScreen> createState() => _LanguageSelectScreenState();
}

class _LanguageSelectScreenState extends ConsumerState<LanguageSelectScreen> {
  final _nativeController = TextEditingController();
  final _targetController = TextEditingController();

  @override
  void dispose() {
    _nativeController.dispose();
    _targetController.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final ok = await ref
        .read(languageSelectViewModelProvider.notifier)
        .confirm(_nativeController.text, _targetController.text);
    if (ok && mounted) {
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(languageSelectViewModelProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Languages'),
        actions: const [SettingsIconButton()],
      ),
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
