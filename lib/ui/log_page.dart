import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../emby/net_log.dart';
import '../theme.dart';

class LogPage extends StatelessWidget {
  const LogPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cinema = context.cinema;
    return Scaffold(
      appBar: AppBar(
        title: const Text('日志'),
        actions: [
          TextButton(
            onPressed: () async {
              final text = NetLog.instance.exportText();
              await Clipboard.setData(ClipboardData(text: text.isEmpty ? '还没有请求' : text));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('日志已复制')));
              }
            },
            child: const Text('复制'),
          ),
          TextButton(
            onPressed: () {
              final text = NetLog.instance.exportText();
              Share.share(text.isEmpty ? '还没有请求' : text, subject: 'Emby 下载日志');
            },
            child: const Text('分享'),
          ),
          TextButton(onPressed: NetLog.instance.clear, child: const Text('清空')),
        ],
      ),
      body: ListenableBuilder(
        listenable: NetLog.instance,
        builder: (context, _) {
          final lines = NetLog.instance.lines;
          if (lines.isEmpty) {
            return Center(child: Text('还没有请求', style: TextStyle(color: cinema.muted)));
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
            itemCount: lines.length,
            itemBuilder: (context, index) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SelectableText(
                  lines[lines.length - 1 - index],
                  style: TextStyle(fontSize: 12, height: 1.35, color: cinema.text),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
