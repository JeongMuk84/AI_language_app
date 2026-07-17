import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/word_lookup_result.dart';
import '../providers/service_providers.dart';
import '../widgets/word_lookup_box.dart';

/// Standalone dictionary lookup, opened as a modal dialog (see
/// [DictionaryIconButton]) from any screen that has the Settings icon —
/// entirely independent of ReviewScreen (which used to have its own
/// inline word-lookup before this was pulled out into its own screen).
/// Reuses `GeminiService.lookupWord` and [WordLookupBox]. Local
/// StatefulWidget state only — nothing here needs to survive the dialog
/// closing (a fresh open always starts blank), and the screen behind this
/// dialog stays mounted for as long as it's open, so nothing about that
/// screen's own state is touched either way.
class DictionaryScreen extends ConsumerStatefulWidget {
  const DictionaryScreen({super.key});

  @override
  ConsumerState<DictionaryScreen> createState() => _DictionaryScreenState();
}

class _DictionaryScreenState extends ConsumerState<DictionaryScreen> {
  final _controller = TextEditingController();
  bool _isLookingUp = false;
  WordLookupResult? _result;
  String? _error;
  String? _emptyInputNotice;
  String? _nativeLanguage;
  String? _targetLanguage;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _lookup() async {
    final input = _controller.text.trim();
    if (input.isEmpty) {
      setState(() {
        _emptyInputNotice = 'Type a word or phrase to look up.';
        _error = null;
      });
      return;
    }
    setState(() {
      _isLookingUp = true;
      _error = null;
      _emptyInputNotice = null;
    });
    try {
      final config = await ref.read(configServiceProvider).readConfig();
      final nativeLanguage = config.nativeLanguage ?? 'the native language';
      final targetLanguage = config.targetLanguage ?? 'the target language';
      final result = await ref
          .read(geminiServiceProvider)
          .lookupWord(input: input, nativeLanguage: nativeLanguage, targetLanguage: targetLanguage);
      if (!mounted) return;
      setState(() {
        _isLookingUp = false;
        _result = result;
        _nativeLanguage = nativeLanguage;
        _targetLanguage = targetLanguage;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLookingUp = false;
        _error = 'Something went wrong. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Dictionary'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controller,
              enabled: !_isLookingUp,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Type a word or phrase, in either language',
              ),
              onSubmitted: (_) => _lookup(),
            ),
            const SizedBox(height: 12),
            Center(
              child: IconButton.filled(
                iconSize: 28,
                tooltip: 'Look up',
                onPressed: _isLookingUp ? null : _lookup,
                icon: _isLookingUp
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.help_outline),
              ),
            ),
            if (_emptyInputNotice != null) ...[
              const SizedBox(height: 16),
              Text(_emptyInputNotice!, style: Theme.of(context).textTheme.bodyMedium),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            if (_result != null) ...[
              const SizedBox(height: 16),
              WordLookupBox(
                result: _result!,
                nativeLanguageLabel: _nativeLanguage ?? 'native language',
                targetLanguageLabel: _targetLanguage ?? 'target language',
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
