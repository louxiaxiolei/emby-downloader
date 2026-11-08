import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';

import '../downloads/speed.dart';
import '../emby/api.dart';
import '../recordings/names.dart';
import '../recordings/store.dart';
import '../emby/net_log.dart';
import '../emby/playback.dart';
import '../session_controller.dart';
import '../theme.dart';

class PlayerPage extends StatefulWidget {
  const PlayerPage({
    super.key,
    required this.title,
    required this.itemId,
    required this.playback,
    this.tappedAt,
    this.recordTitle,
    this.recordEpisode,
  });

  final String title;
  final String itemId;
  final ResolvedPlayback playback;
  final DateTime? tappedAt;

  /// Base name inside 《》 for a recording, without the time range.
  final String? recordTitle;
  final String? recordEpisode;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  late final Player _player = Player();
  late final VideoController _video = VideoController(_player);
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Timer? _progressTimer;
  Timer? _chromeTimer;
  var _showChrome = true;
  var _fullscreen = false;
  var _buffering = true;
  var _bufferPercent = 0.0;
  var _firstFrame = false;
  int? _openMs;
  int? _infoMs;
  String? _fallbackUrl;
  String? _playSessionId;
  var _seeking = false;
  var _started = false;
  var _reportedStart = false;
  var _triedTranscode = false;
  var _disposed = false;
  String _method = 'DirectPlay';
  String? _error;
  String? _resumeNote;
  EmbyClient? _client;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Tracks _tracks = const Tracks();
  var _recording = false;
  String? _recordPath;
  String _recordExt = 'mkv';
  Duration _recordStart = Duration.zero;
  DateTime? _recordWall;
  Duration _recordElapsed = Duration.zero;
  Timer? _recordTimer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _client = context.read<SessionController>().client;
  }

  @override
  void initState() {
    super.initState();
    _method = widget.playback.playMethod;
    _subscriptions.addAll([
      _player.stream.position.listen((position) {
        if (_seeking || !mounted) return;
        setState(() => _position = position);
      }),
      _player.stream.duration.listen((duration) {
        if (!mounted) return;
        setState(() => _duration = duration);
      }),
      _player.stream.buffering.listen((buffering) {
        if (!mounted) return;
        setState(() => _buffering = buffering);
      }),
      _player.stream.bufferingPercentage.listen((value) {
        if (!mounted) return;
        setState(() => _bufferPercent = value);
      }),
      _player.stream.width.listen((width) {
        if (width == null || width <= 0 || _firstFrame) return;
        _firstFrame = true;
        final total = widget.tappedAt == null ? null : DateTime.now().difference(widget.tappedAt!).inMilliseconds;
        NetLog.instance.add(
          '首帧 ${total ?? -1}ms 打开 ${_openMs ?? -1}ms PlaybackInfo ${_infoMs ?? -1}ms',
        );
        if (mounted) setState(() {});
      }),
      _player.stream.tracks.listen((tracks) {
        if (!mounted) return;
        setState(() => _tracks = tracks);
      }),
      _player.stream.playing.listen((playing) {
        if (playing) _started = true;
        if (playing && !_reportedStart) {
          unawaited(_reportStart());
        } else if (_reportedStart) {
          unawaited(_reportProgress(playing ? 'Unpause' : 'Pause', paused: !playing));
        }
      }),
      _player.stream.error.listen((message) {
        if (message.isEmpty || _disposed) return;
        unawaited(_onError(message));
      }),
    ]);
    unawaited(_open(widget.playback.url, transcode: widget.playback.playMethod == 'Transcode'));
    unawaited(_loadPlaybackInfo());
  }

  Future<void> _loadPlaybackInfo() async {
    final client = context.read<SessionController>().client;
    if (client == null) return;
    final watch = Stopwatch()..start();
    try {
      final info = await client.playbackInfo(
        itemId: widget.itemId,
        mediaSourceId: widget.playback.mediaSourceId,
        startTimeTicks: ticksFor(widget.playback.resume ?? Duration.zero),
      );
      _infoMs = watch.elapsedMilliseconds;
      NetLog.instance.add('PlaybackInfo ${_infoMs}ms');
      if (!mounted || _disposed) return;
      final resolved = resolvePlayback(
        base: client.session.base,
        apiRoot: client.session.apiRoot,
        accessToken: client.session.accessToken,
        itemId: widget.itemId,
        mediaSourceId: widget.playback.mediaSourceId,
        playbackInfo: info,
        headers: client.headers,
        resume: widget.playback.resume,
      );
      _fallbackUrl = resolved.transcodeUrl ?? (resolved.playMethod == 'Transcode' ? resolved.url : null);
      _playSessionId = resolved.playSessionId;
    } catch (error) {
      _infoMs = watch.elapsedMilliseconds;
      NetLog.instance.add('PlaybackInfo 失败 ${_infoMs}ms $error');
    }
  }

  Future<void> _tune() async {
    final native = _player.platform;
    if (native is! NativePlayer) return;
    const options = {
      'hwdec': 'auto',
      'cache': 'yes',
      'demuxer-readahead-secs': '2',
      'demuxer-max-bytes': '32MiB',
      'network-timeout': '20',
      'demuxer-lavf-probesize': '1048576',
      'demuxer-lavf-analyzeduration': '1000000',
    };
    for (final entry in options.entries) {
      try {
        await native.setProperty(entry.key, entry.value);
      } catch (error) {
        NetLog.instance.add('mpv ${entry.key} 失败 $error');
      }
    }
  }

  Future<void> _open(String url, {required bool transcode}) async {
    _method = transcode ? 'Transcode' : widget.playback.playMethod;
    final watch = Stopwatch()..start();
    try {
      await _tune();
      await _player.open(
        Media(
          url,
          httpHeaders: widget.playback.headers,
          start: widget.playback.resume,
        ),
      );
      _openMs = watch.elapsedMilliseconds;
      NetLog.instance.add('打开播放器 ${_openMs}ms ${transcode ? '转码' : '直连'}');
      if (_disposed) return;
      final resume = widget.playback.resume;
      if (resume != null && resume > Duration.zero && mounted) {
        setState(() => _resumeNote = '从 ${formatClock(resume)} 继续');
      }
      final preferred = widget.playback.subtitles.where((track) => track.isDefault && track.url != null);
      if (!transcode && preferred.isNotEmpty) {
        await _player.setSubtitleTrack(
          SubtitleTrack.uri(
            preferred.first.url!,
            title: preferred.first.title,
            language: preferred.first.language,
          ),
        );
      }
      _progressTimer?.cancel();
      _progressTimer = Timer.periodic(const Duration(seconds: 10), (_) {
        unawaited(_reportProgress('TimeUpdate', paused: !_player.state.playing));
      });
    } catch (error) {
      if (mounted) setState(() => _error = '无法播放');
    }
  }

  Future<void> _onError(String message) async {
    final fallback = _fallbackUrl ?? widget.playback.transcodeUrl;
    if (!_started && !_triedTranscode && fallback != null && _method != 'Transcode') {
      _triedTranscode = true;
      if (mounted) {
        setState(() {
          _error = null;
          _buffering = true;
        });
      }
      await _open(fallback, transcode: true);
      return;
    }
    if (!mounted || _disposed) return;
    setState(() => _error = '无法播放');
  }

  Future<void> _reportStart() async {
    if (_reportedStart || widget.itemId.isEmpty) return;
    _reportedStart = true;
    await _send('start', paused: !_player.state.playing);
  }

  Future<void> _reportProgress(String event, {required bool paused}) async {
    if (!_reportedStart || widget.itemId.isEmpty) return;
    await _send('progress', paused: paused, eventName: event);
  }

  Future<void> _reportStopped() async {
    if (!_reportedStart || widget.itemId.isEmpty) return;
    await _send('stop', paused: true, eventName: 'Stop');
  }

  Future<void> _send(String phase, {required bool paused, String? eventName}) async {
    final client = _client;
    if (client == null) return;
    try {
      await client.reportPlayback(
      phase: phase,
      itemId: widget.itemId,
      mediaSourceId: widget.playback.mediaSourceId,
      playSessionId: _playSessionId ?? widget.playback.playSessionId,
      positionTicks: ticksFor(_player.state.position),
      isPaused: paused,
      playMethod: _method,
      eventName: eventName,
    );
    } catch (_) {}
  }

  Future<void> _setFullscreen(bool enabled) async {
    setState(() {
      _fullscreen = enabled;
      _showChrome = true;
    });
    if (enabled) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      await _restoreChrome();
    }
  }

  Future<void> _restoreChrome() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  void _toggleChrome() {
    setState(() => _showChrome = !_showChrome);
    _chromeTimer?.cancel();
    if (_showChrome && _firstFrame && _player.state.playing) {
      _chromeTimer = Timer(const Duration(seconds: 4), () {
        if (mounted && _player.state.playing) setState(() => _showChrome = false);
      });
    }
  }

  Future<void> _toggleRecord() async {
    if (_recording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    final native = _player.platform;
    if (native is! NativePlayer) {
      NetLog.instance.add('开始录制失败 没有 mpv');
      _tell('无法录制');
      return;
    }
    try {
      final directory = await recordingsDirectory();
      final ext = sourceContainer(widget.playback.url);
      final temp = p.join(directory.path, '.recording-${DateTime.now().millisecondsSinceEpoch}.$ext');
      await native.setProperty('stream-record', temp);
      _recordPath = temp;
      _recordExt = ext;
      _recordStart = _position;
      _recordWall = DateTime.now();
      _recordElapsed = Duration.zero;
      _recordTimer?.cancel();
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        final start = _recordWall;
        if (!mounted || start == null) return;
        setState(() => _recordElapsed = DateTime.now().difference(start));
      });
      NetLog.instance.add('开始录制 $temp 从 ${formatClock(_position)}');
      if (mounted) setState(() => _recording = true);
    } catch (error) {
      NetLog.instance.add('开始录制失败 $error');
      _tell('无法开始录制');
    }
  }

  Future<void> _stopRecording() async {
    if (!_recording && _recordPath == null) return;
    _recordTimer?.cancel();
    final temp = _recordPath;
    final start = _recordStart;
    final end = _position;
    final ext = _recordExt;
    if (mounted) setState(() => _recording = false);
    try {
      final native = _player.platform;
      if (native is NativePlayer) {
        await native.setProperty('stream-record', '');
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (temp == null) return;
      final file = File(temp);
      if (!await file.exists() || await file.length() <= 0) {
        NetLog.instance.add('停止录制失败 没有写出文件');
        _tell('录制文件是空的');
        if (await file.exists()) await file.delete();
        return;
      }
      final directory = p.dirname(temp);
      final name = recordingFileName(
        title: widget.recordTitle ?? widget.title,
        episode: widget.recordEpisode,
        start: start,
        end: end,
        extension: ext,
      );
      var dest = p.join(directory, name);
      if (await File(dest).exists()) {
        dest = p.join(directory, '${p.basenameWithoutExtension(name)}-${DateTime.now().millisecondsSinceEpoch}.$ext');
      }
      await file.rename(dest);
      NetLog.instance.add('停止录制 $dest');
      _tell('已保存 $name');
    } catch (error) {
      NetLog.instance.add('停止录制失败 $error');
      _tell('停止录制失败');
    } finally {
      _recordPath = null;
    }
  }

  void _tell(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _disposed = true;
    _progressTimer?.cancel();
    _chromeTimer?.cancel();
    _recordTimer?.cancel();
    if (_recording && _recordPath != null) {
      final native = _player.platform;
      final temp = _recordPath!;
      final start = _recordStart;
      final end = _position;
      final ext = _recordExt;
      final title = widget.recordTitle ?? widget.title;
      final episode = widget.recordEpisode;
      unawaited(() async {
        try {
          if (native is NativePlayer) await native.setProperty('stream-record', '');
          await Future<void>.delayed(const Duration(milliseconds: 250));
          final file = File(temp);
          if (await file.exists() && await file.length() > 0) {
            final name = recordingFileName(title: title, episode: episode, start: start, end: end, extension: ext);
            await file.rename(p.join(p.dirname(temp), name));
            NetLog.instance.add('离开播放器时保存录制 $name');
          }
        } catch (error) {
          NetLog.instance.add('离开播放器时停止录制失败 $error');
        }
      }());
    }
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    if (_reportedStart) unawaited(_reportStopped());
    unawaited(_restoreChrome());
    unawaited(_player.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final max = _duration.inMilliseconds <= 0 ? 1.0 : _duration.inMilliseconds.toDouble();
    final value = _position.inMilliseconds.clamp(0, max.round()).toDouble();
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleChrome,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: Video(
                controller: _video,
                controls: null,
                fit: BoxFit.contain,
                wakelock: true,
              ),
            ),
            if (_recording)
              Positioned(
                top: 8,
                right: 12,
                child: SafeArea(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xCC1A0000),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '● ${formatClock(_recordElapsed)}',
                      style: const TextStyle(color: Color(0xFFFF4D4D), fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ),
            if (_buffering && _error == null)
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: brass),
                    const SizedBox(height: 12),
                    Text(
                      '缓冲中 ${_bufferPercent.round()}%',
                      style: const TextStyle(color: ivory, fontSize: 14),
                    ),
                  ],
                ),
              ),
            if (_error != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_error!, style: const TextStyle(color: ivory)),
                ),
              ),
            if (_showChrome) ...[
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: _bar(
                  top: true,
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.arrow_back, color: ivory),
                      ),
                      Expanded(
                        child: Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: ivory, fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (_method == 'Transcode')
                        const Padding(
                          padding: EdgeInsets.only(right: 8),
                          child: Text('转码', style: TextStyle(color: brass, fontSize: 12)),
                        ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _bar(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_resumeNote != null)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            onPressed: () async {
                              await _player.seek(Duration.zero);
                              if (mounted) setState(() => _resumeNote = null);
                            },
                            child: Text('$_resumeNote · 从头播放', style: const TextStyle(color: brass)),
                          ),
                        ),
                      Row(
                        children: [
                          IconButton(
                            onPressed: () => _player.playOrPause(),
                            icon: Icon(
                              _player.state.playing ? Icons.pause : Icons.play_arrow,
                              color: ivory,
                            ),
                          ),
                          Text(formatClock(_position), style: const TextStyle(color: muted, fontSize: 12)),
                          Expanded(
                            child: Slider(
                              value: value,
                              max: max,
                              activeColor: brass,
                              onChangeStart: (_) => _seeking = true,
                              onChanged: (next) => setState(() => _position = Duration(milliseconds: next.round())),
                              onChangeEnd: (next) async {
                                await _player.seek(Duration(milliseconds: next.round()));
                                _seeking = false;
                                unawaited(_reportProgress('TimeUpdate', paused: !_player.state.playing));
                              },
                            ),
                          ),
                          Text(formatClock(_duration), style: const TextStyle(color: muted, fontSize: 12)),
                        ],
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          IconButton(
                            tooltip: _recording ? '停止录制' : '录制',
                            onPressed: _toggleRecord,
                            icon: Icon(
                              _recording ? Icons.stop_circle : Icons.fiber_manual_record,
                              color: _recording ? const Color(0xFFFF4D4D) : ivory,
                            ),
                          ),
                          _audioMenu(),
                          _subtitleMenu(),
                          IconButton(
                            tooltip: _fullscreen ? '退出全屏' : '全屏',
                            onPressed: () => _setFullscreen(!_fullscreen),
                            icon: Icon(
                              _fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                              color: ivory,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _bar({required Widget child, required bool top}) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: top ? Alignment.topCenter : Alignment.bottomCenter,
          end: top ? Alignment.bottomCenter : Alignment.topCenter,
          colors: const [Color(0xF2000000), Color(0x00000000)],
        ),
      ),
      child: SafeArea(child: child),
    );
  }

  Widget _audioMenu() {
    final tracks = _tracks.audio.where((track) => track.id != 'no').toList();
    return PopupMenuButton<AudioTrack>(
      tooltip: '音轨',
      icon: const Icon(Icons.audiotrack, color: ivory),
      onSelected: (track) => _player.setAudioTrack(track),
      itemBuilder: (context) => [
        for (var i = 0; i < tracks.length; i++)
          PopupMenuItem(
            value: tracks[i],
            child: Text(_trackName(tracks[i].id, tracks[i].title, tracks[i].language, '音轨 ${i + 1}')),
          ),
      ],
    );
  }

  Widget _subtitleMenu() {
    final embedded = _tracks.subtitle.where((track) => !track.uri && track.id != 'no').toList();
    final external = widget.playback.subtitles.where((track) => track.url != null).toList();
    return PopupMenuButton<Object>(
      tooltip: '字幕',
      icon: const Icon(Icons.subtitles_outlined, color: ivory),
      onSelected: (value) {
        if (value is SubtitleTrack) {
          _player.setSubtitleTrack(value);
        } else if (value is PlaybackSubtitle && value.url != null) {
          _player.setSubtitleTrack(
            SubtitleTrack.uri(value.url!, title: value.title, language: value.language),
          );
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(value: SubtitleTrack.no(), child: const Text('关闭')),
        for (var i = 0; i < embedded.length; i++)
          PopupMenuItem(
            value: embedded[i],
            child: Text(_trackName(embedded[i].id, embedded[i].title, embedded[i].language, '内嵌 ${i + 1}')),
          ),
        for (final track in external)
          PopupMenuItem(value: track, child: Text(track.title.isEmpty ? '外挂字幕' : track.title)),
      ],
    );
  }
}

String _trackName(String id, String? title, String? language, String fallback) {
  if (id == 'auto') return '自动';
  if (title != null && title.trim().isNotEmpty) return title.trim();
  if (language != null && language.trim().isNotEmpty) return language.trim();
  return fallback;
}
