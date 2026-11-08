import 'package:flutter/material.dart';

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
