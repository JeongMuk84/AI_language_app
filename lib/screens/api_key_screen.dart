import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';
import '../viewmodels/api_key_view_model.dart';
import '../viewmodels/theme_mode_view_model.dart';

class ApiKeyScreen extends ConsumerStatefulWidget {
  const ApiKeyScreen({super.key});

  @override
  ConsumerState<ApiKeyScreen> createState() => _ApiKeyScreenState();
}

class _ApiKeyScreenState extends ConsumerState<ApiKeyScreen> {
  final _controller = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _openApiKeyPage() async {
    final uri = Uri.parse('https://aistudio.google.com/apikey');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _submit() async {
    final ok = await ref.read(apiKeyViewModelProvider.notifier).submit(_controller.text);
    if (ok && mounted) {
      context.go('/');
    }
  }

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
