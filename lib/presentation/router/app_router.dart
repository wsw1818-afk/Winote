import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../pages/home/home_page.dart';
import '../pages/library/library_page.dart';
import '../pages/editor/editor_page.dart';
import '../pages/pdf_viewer/pdf_viewer_page.dart';
import '../pages/settings/settings_page.dart';

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
          return EditorPage(noteId: noteId);
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
