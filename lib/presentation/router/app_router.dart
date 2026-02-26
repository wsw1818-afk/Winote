import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../pages/home/home_page.dart';
import '../pages/library/library_page.dart';
import '../pages/editor/editor_page.dart';
import '../pages/pdf_viewer/pdf_viewer_page.dart';
import '../pages/settings/settings_page.dart';
import '../pages/scanner/scanner_page.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        name: 'home',
        builder: (context, state) => const HomePage(),
      ),
      GoRoute(
        path: '/library',
        name: 'library',
        builder: (context, state) => const LibraryPage(),
      ),
      GoRoute(
        path: '/editor/:noteId',
        name: 'editor',
        builder: (context, state) {
          final noteId = state.pathParameters['noteId'] ?? '';
          final extra = state.extra as Map<String, dynamic>?;
          final backgroundPath = extra?['initialBackgroundImagePath'] as String?;
          return EditorPage(
            noteId: noteId,
            initialBackgroundImagePath: backgroundPath,
          );
        },
      ),
      GoRoute(
        path: '/pdf/:attachmentId',
        name: 'pdf_viewer',
        builder: (context, state) {
          final attachmentId = state.pathParameters['attachmentId'] ?? '';
          return PdfViewerPage(attachmentId: attachmentId);
        },
      ),
      GoRoute(
        path: '/scanner',
        name: 'scanner',
        builder: (context, state) => const ScannerPage(
          entryMode: ScanEntryMode.standalone,
        ),
      ),
      GoRoute(
        path: '/settings',
        name: 'settings',
        builder: (context, state) => const SettingsPage(),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Text('Page not found: ${state.uri}'),
      ),
    ),
  );
});
