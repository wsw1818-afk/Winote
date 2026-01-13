import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('설정'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView(
        children: [
          const ListTile(
            leading: Icon(Icons.edit),
            title: Text('펜 설정'),
            subtitle: Text('기본 색상, 굵기'),
            trailing: Icon(Icons.chevron_right),
          ),
          const ListTile(
            leading: Icon(Icons.grid_on),
            title: Text('기본 템플릿'),
            subtitle: Text('빈 페이지'),
            trailing: Icon(Icons.chevron_right),
          ),
          const ListTile(
            leading: Icon(Icons.save),
            title: Text('자동 저장'),
            subtitle: Text('3초 후 자동 저장'),
            trailing: Icon(Icons.chevron_right),
          ),
          const Divider(),
          const ListTile(
            leading: Icon(Icons.folder),
            title: Text('동기화 폴더'),
            subtitle: Text('설정되지 않음'),
            trailing: Icon(Icons.chevron_right),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('앱 정보'),
            subtitle: const Text('버전 1.0.0'),
            onTap: () {
              showAboutDialog(
                context: context,
                applicationName: 'Winote',
                applicationVersion: '1.0.0',
                applicationLegalese: '© 2024 Winote',
              );
            },
          ),
        ],
      ),
    );
  }
}
