import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/word_lookup_result.dart';
import '../providers/service_providers.dart';
import '../widgets/word_lookup_box.dart';

/// 독립적인 사전 검색 화면. Settings 아이콘이 있는 어느 화면에서든
/// ([DictionaryIconButton] 참고) 모달 다이얼로그로 열리며, ReviewScreen과는
/// 완전히 별개다(예전에는 ReviewScreen 안에 인라인 단어 검색 기능이 있었으나
/// 이 화면으로 분리되어 나왔다). `GeminiService.lookupWord`와
/// [WordLookupBox]를 재사용한다. 오직 로컬 StatefulWidget 상태만 사용한다 —
/// 다이얼로그가 닫힌 뒤에도 유지되어야 할 값이 없고(다시 열면 항상 빈
/// 상태로 시작), 이 다이얼로그가 열려있는 동안 뒤쪽 화면은 계속 마운트된
/// 채로 남아있으므로 그 화면 자체의 상태는 어느 쪽으로도 건드릴 필요가 없다.
class DictionaryScreen extends ConsumerStatefulWidget {
  const DictionaryScreen({super.key});

  /// 이 위젯의 상태 객체([_DictionaryScreenState])를 생성한다.
  @override
  ConsumerState<DictionaryScreen> createState() => _DictionaryScreenState();
}

/// [DictionaryScreen]의 State. 사전 검색어 입력 컨트롤러, 검색 진행 상태,
/// 검색 결과/에러/빈 입력 안내, 그리고 결과 표시에 쓸 언어 라벨을 로컬로
/// 관리한다(다이얼로그가 새로 열릴 때마다 항상 빈 상태로 시작하면 되므로
/// Riverpod provider 없이 StatefulWidget local state만으로 충분하다).
class _DictionaryScreenState extends ConsumerState<DictionaryScreen> {
  final _controller = TextEditingController();
  bool _isLookingUp = false;
  WordLookupResult? _result;
  String? _error;
  String? _emptyInputNotice;
  String? _nativeLanguage;
  String? _targetLanguage;

  /// 위젯이 트리에서 제거될 때 [_controller]를 해제해 메모리 누수를 막는다.
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// "Look up" 아이콘 버튼 또는 텍스트필드에서 Enter/검색 키를 누르면
  /// 호출된다. 입력값이 비어있으면 안내 메시지만 세팅하고 API를 호출하지
  /// 않는다. 그렇지 않으면 `configServiceProvider`에서 모국어/학습 언어를
  /// 읽고 `GeminiService.lookupWord`를 호출해 검색 결과를 가져와 [_result]에
  /// 담는다. 실패 시 [_error]에 에러 메시지를 담는다.
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

  /// 사전 검색 UI(AlertDialog: 검색어 입력, 검색 버튼, 안내/에러 메시지,
  /// [WordLookupBox] 결과)를 그린다.
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
              // Single-line on purpose: this field never needs a newline,
              // so Enter (hardware keyboard) or the mobile keyboard's
              // search/done key should submit instead of inserting one —
              // a multi-line field (maxLines > 1) would swallow Enter as a
              // literal newline instead of firing onSubmitted below.
              maxLines: 1,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Type a word or phrase, in either language',
              ),
              // Reuses the exact same handler as the lookup button below —
              // same empty-input guard, same loading state, no duplicated
              // logic.
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
