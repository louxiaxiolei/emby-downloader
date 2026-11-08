import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../emby/models.dart';
import '../emby/net_log.dart';
import '../emby/playback.dart';
import '../emby/urls.dart';
import '../session_controller.dart';
import 'player_page.dart';

/// Push the player immediately with a direct stream URL. PlaybackInfo runs
/// inside the player and does not delay the first frame.
Future<void> playItem(BuildContext context, EmbyItem item) {
  if (!item.canDownload) return Future.value();
  final client = context.read<SessionController>().client;
  if (client == null) return Future.value();
  final tappedAt = DateTime.now();
  NetLog.instance.add('点播 ${mediaTitle(item)}');
  final playback = instantPlayback(
    apiRoot: client.session.apiRoot,
    accessToken: client.session.accessToken,
    item: item,
    headers: client.headers,
  );
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => PlayerPage(
        title: mediaTitle(item),
        itemId: item.id,
        playback: playback,
        tappedAt: tappedAt,
      ),
    ),
  );
}
