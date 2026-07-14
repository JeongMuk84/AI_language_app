import 'package:flutter/material.dart';

import '../widgets/settings_icon_button.dart';

class LearningScreen extends StatelessWidget {
  const LearningScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Learning'),
        actions: const [SettingsIconButton()],
      ),
      body: const Center(child: Text('Learning content coming soon.')),
    );
  }
}
