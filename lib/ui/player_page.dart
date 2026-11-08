import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';

import '../downloads/speed.dart';
import '../emby/api.dart';
import '../emby/playback.dart';
import '../session_controller.dart';
import '../theme.dart';

class PlayerPage extends StatefulWidget {
  const PlayerPage({
    super.key,
    required this.title,
    required this.itemId,
    required this.playback,
  });

  final String title;
  final String itemId;
  final ResolvedPlayback playback;

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
  }

  Future<void> _open(String url, {required bool transcode}) async {
    _method = transcode ? 'Transcode' : widget.playback.playMethod;
    try {
      await _player.open(
        Media(
          url,
          httpHeaders: widget.playback.headers,
          start: widget.playback.resume,
        ),
      );
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
    final fallback = widget.playback.transcodeUrl;
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
      playSessionId: widget.playback.playSessionId,
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
    if (_showChrome && _player.state.playing) {
      _chromeTimer = Timer(const Duration(seconds: 4), () {
        if (mounted && _player.state.playing) setState(() => _showChrome = false);
      });
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _progressTimer?.cancel();
    _chromeTimer?.cancel();
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
            if (_buffering && _error == null)
              const Center(child: CircularProgressIndicator(color: brass)),
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
          colors: const [Color(0xCC000000), Color(0x00000000)],
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
