import 'package:flutter/material.dart';

/// Bootstrap-only landing spot for `/learning` — the router's redirect
/// resolves this into the actual destination (a learning-loop screen or
/// ReviewPlaceholderScreen) almost immediately, so this is rarely visible
/// for more than a frame.
class LearningScreen extends StatelessWidget {
  const LearningScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
