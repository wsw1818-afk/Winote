import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/services/settings_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize settings service
  await SettingsService.instance.initialize();

  runApp(
    const ProviderScope(
      child: WinoteApp(),
    ),
  );
}
