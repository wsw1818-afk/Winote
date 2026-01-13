import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class PdfViewerPage extends ConsumerWidget {
  final String attachmentId;

  const PdfViewerPage({
    super.key,
    required this.attachmentId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PDF 뷰어'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: Center(
        child: Text('PDF 뷰어 페이지 - 구현 예정\nID: $attachmentId'),
      ),
    );
  }
}
