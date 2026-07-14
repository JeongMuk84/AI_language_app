import 'package:flutter/material.dart';

/// Wraps the app and lets any descendant force a full restart — a fresh
/// `ProviderScope` (all providers reset) and a fresh widget tree — without
/// exiting the process. Used after switching target languages, since that
/// flow needs config.json and every in-memory provider re-derived from
/// scratch.
class RestartWidget extends StatefulWidget {
  const RestartWidget({super.key, required this.child});

  final Widget child;

  static void restartApp(BuildContext context) {
    context.findAncestorStateOfType<_RestartWidgetState>()?._restart();
  }

  @override
  State<RestartWidget> createState() => _RestartWidgetState();
}

class _RestartWidgetState extends State<RestartWidget> {
  Key _key = UniqueKey();

  void _restart() {
    setState(() {
      _key = UniqueKey();
    });
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(key: _key, child: widget.child);
  }
}
