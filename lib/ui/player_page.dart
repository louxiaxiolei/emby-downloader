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
import '../emby/net_log.dart';
import '../emby/playback.dart';
import '../emby/playback_guard.dart';
import '../recordings/clip.dart';
import '../recordings/names.dart';
import '../recordings/remux.dart';
import '../recordings/store.dart';
import '../session_controller.dart';
import '../storage/settings_store.dart';
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
  late final Player _player = Player(
    configuration: const PlayerConfiguration(bufferSize: 150 * 1024 * 1024),
  );
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
  String? _playSessionId;
  var _seeking = false;
  var _started = false;
  var _reportedStart = false;
  var _triedServerDirect = false;
  var _triedTranscode = false;
  var _fallbackRunning = false;
  var _disposed = false;
  String _method = 'DirectPlay';
  String _currentUrl = '';
  String? _error;
  String? _lastMpvError;
  ResolvedPlayback? _serverPlayback;
  Future<void>? _infoFuture;
  Timer? _noFrameWatch;
  String? _resumeNote;
  EmbyClient? _client;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Tracks _tracks = const Tracks();
  var _recording = false;
  String _recordExt = 'mkv';
  Duration _recordStart = Duration.zero;
  Duration _recordChunkFrom = Duration.zero;
  DateTime? _recordWall;
  Duration _recordElapsed = Duration.zero;
  Timer? _recordTimer;
  var _recordId = 0;
  var _recordSegment = 0;
  final List<String> _recordSegments = [];
  Future<void> _recordJobs = Future<void>.value();

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
        if (!_opening && framesAreOnScreen(firstFrame: _firstFrame, position: position)) _notePicture();
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
        if (_opening || width == null || width <= 0 || _firstFrame) return;
        _firstFrame = true;
        final total = widget.tappedAt == null ? null : DateTime.now().difference(widget.tappedAt!).inMilliseconds;
        NetLog.instance.add(
          '首帧 ${total ?? -1}ms 打开 ${_openMs ?? -1}ms PlaybackInfo ${_infoMs ?? -1}ms',
        );
        _notePicture();
        if (mounted) setState(() {});
      }),
      _player.stream.tracks.listen((tracks) {
        if (!mounted) return;
        setState(() => _tracks = tracks);
      }),
      _player.stream.playing.listen((playing) {
        if (playing) _started = true;
        if (playing && _pictureOnScreen && !_reportedStart) {
          unawaited(_reportStart());
        } else if (_reportedStart) {
          unawaited(_reportProgress(playing ? 'Unpause' : 'Pause', paused: !playing));
        }
      }),
      _player.stream.error.listen((message) {
        if (message.isEmpty || _disposed) return;
        unawaited(_onMpvError(message));
      }),
    ]);
    final initialLabel = _networkPlayback ? '直连' : '本地';
    unawaited(() async {
      final opened = await _open(
        widget.playback.url,
        transcode: widget.playback.playMethod == 'Transcode',
        label: initialLabel,
      );
      if (!opened && !_disposed && !_pictureOnScreen) await _fallback('打开失败');
    }());
    if (_networkPlayback && widget.itemId.isNotEmpty) {
      unawaited(_loadPlaybackInfo());
      final client = context.read<SessionController>().client;
      if (client != null) unawaited(client.probeMedia(widget.playback.url));
    }
  }

  bool get _networkPlayback {
    final scheme = Uri.tryParse(widget.playback.url)?.scheme;
    return scheme == 'http' || scheme == 'https';
  }

  bool get _pictureOnScreen => framesAreOnScreen(firstFrame: _firstFrame, position: _position);

  var _opening = false;

  void _notePicture() {
    _noFrameWatch?.cancel();
    if (_error != null && mounted) setState(() => _error = null);
    if (!_reportedStart && _started) unawaited(_reportStart());
  }

  Future<void> _loadPlaybackInfo() {
    return _infoFuture ??= _fetchPlaybackInfo();
  }

  Future<void> _fetchPlaybackInfo() async {
    final client = _client ?? context.read<SessionController>().client;
    if (client == null || widget.itemId.isEmpty) return;
    final watch = Stopwatch()..start();
    try {
      final info = await client.playbackInfo(
        itemId: widget.itemId,
        mediaSourceId: widget.playback.mediaSourceId,
        startTimeTicks: ticksFor(widget.playback.resume ?? Duration.zero),
      );
      _infoMs = watch.elapsedMilliseconds;
      if (!mounted || _disposed) return;
      final resolved = resolvePlayback(
        base: client.session.base,
        apiRoot: client.session.apiRoot,
        accessToken: client.session.accessToken,
        itemId: widget.itemId,
        mediaSourceId: widget.playback.mediaSourceId,
        container: sourceContainer(widget.playback.url) == 'mkv' ? null : sourceContainer(widget.playback.url),
        playbackInfo: info,
        headers: playbackHeaders(client.mediaHeaders),
        resume: widget.playback.resume,
      );
      _serverPlayback = resolved;
      _playSessionId = resolved.playSessionId;
      final direct = resolved.playMethod == 'Transcode' ? '' : NetLog.redact(Uri.parse(resolved.url));
      final transcode = resolved.transcodeUrl ?? (resolved.playMethod == 'Transcode' ? resolved.url : null);
      final transcodeText = transcode == null ? '' : NetLog.redact(Uri.parse(transcode));
      NetLog.instance.add(
        'PlaybackInfo ${_infoMs}ms 路径 ${resolved.playMethod} 直连 $direct 转码 $transcodeText',
      );
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
      'demuxer-readahead-secs': '20',
      'demuxer-max-bytes': '150MiB',
      // Keep the played range. stream-record ignores packets already in this cache.
      'demuxer-max-back-bytes': '300MiB',
      'demuxer-seekable-cache': 'yes',
      'network-timeout': '60',
    };
    for (final entry in options.entries) {
      try {
        await native.setProperty(entry.key, entry.value);
      } catch (error) {
        NetLog.instance.add('mpv ${entry.key} 失败 $error');
      }
    }
  }

  Future<bool> _open(String url, {required bool transcode, required String label}) async {
    _method = transcode ? 'Transcode' : (_serverPlayback?.playMethod ?? widget.playback.playMethod);
    if (!transcode && _method == 'Transcode') _method = 'DirectPlay';
    _opening = true;
    _firstFrame = false;
    _position = Duration.zero;
    _currentUrl = url;
    final watch = Stopwatch()..start();
    final redacted = NetLog.redact(Uri.parse(url));
    NetLog.instance.add('播放尝试 $label $redacted');
    _noFrameWatch?.cancel();
    _noFrameWatch = Timer(const Duration(seconds: 8), () {
      if (_disposed || _pictureOnScreen) return;
      if (_networkPlayback) {
        unawaited(_fallback(_lastMpvError ?? '8秒没有画面'));
      } else {
        _showFatal(_lastMpvError ?? '8秒没有画面');
      }
    });
    try {
      await _tune();
      _opening = false;
      await _player.open(
        Media(
          url,
          httpHeaders: playbackHeaders(widget.playback.headers),
          start: widget.playback.resume,
        ),
      );
      _openMs = watch.elapsedMilliseconds;
      NetLog.instance.add('打开播放器 ${_openMs}ms $label');
      if (_disposed) return false;
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
      return true;
    } catch (error) {
      _opening = false;
      NetLog.instance.add('打开播放器失败 $label $error');
      _lastMpvError = '$error';
      return false;
    }
  }

  Future<void> _onMpvError(String message) async {
    _lastMpvError = message;
    NetLog.instance.add('mpv 错误 $message');
    if (_pictureOnScreen) {
      NetLog.instance.add('画面播放中，忽略该错误');
      _notePicture();
      return;
    }
    if (hardPlaybackFailure(message)) {
      await _fallback(message);
    }
  }

  Future<void> _fallback(String reason) async {
    if (_disposed || _pictureOnScreen || _fallbackRunning) return;
    if (!surfacePlaybackError(framesVisible: _pictureOnScreen)) return;
    if (!_networkPlayback) {
      _showFatal(reason);
      return;
    }
    _fallbackRunning = true;
    try {
      await _loadPlaybackInfo();
      while (!_disposed && !_pictureOnScreen) {
        final server = _serverPlayback;
        final transcode = server == null
            ? widget.playback.transcodeUrl
            : server.transcodeUrl ?? (server.playMethod == 'Transcode' ? server.url : null);
        final next = choosePlaybackFallback(
          currentUrl: _currentUrl,
          triedDirect: _triedServerDirect,
          triedTranscode: _triedTranscode,
          directUrl: server != null && server.playMethod != 'Transcode' ? server.url : null,
          directLabel: server?.playMethod ?? 'DirectStream',
          transcodeUrl: transcode,
        );
        if (next == null) {
          _showFatal(_lastMpvError ?? reason);
          return;
        }
        if (next.transcode) {
          _triedTranscode = true;
        } else {
          _triedServerDirect = true;
        }
        _playSessionId = server?.playSessionId ?? _playSessionId;
        NetLog.instance.add('回退 ${next.label}，原因 $reason');
        final opened = await _open(next.url, transcode: next.transcode, label: next.label);
        if (_disposed || _pictureOnScreen || opened) return;
      }
    } finally {
      _fallbackRunning = false;
    }
  }

  void _showFatal(String message) {
    if (_disposed || _pictureOnScreen || !mounted) return;
    final text = message.trim().isEmpty ? '没有画面' : message.trim();
    NetLog.instance.add('播放失败 $text');
    setState(() => _error = text);
  }

  Future<void> _retry() async {
    _triedServerDirect = false;
    _triedTranscode = false;
    _lastMpvError = null;
    _noFrameWatch?.cancel();
    if (mounted) {
      setState(() {
        _error = null;
        _buffering = true;
        _firstFrame = false;
      });
    }
    final opened = await _open(widget.playback.url, transcode: false, label: '重试直连');
    if (!opened && !_disposed && !_pictureOnScreen) await _fallback('重试失败');
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
    _recordId = DateTime.now().millisecondsSinceEpoch;
    _recordSegment = 0;
    _recordSegments.clear();
    _recordExt = sourceContainer(widget.playback.url);
    _recordStart = _position;
    _recordChunkFrom = _position;
    _recordWall = DateTime.now();
    _recordElapsed = Duration.zero;
    _recordTimer?.cancel();
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final start = _recordWall;
      if (!mounted || start == null) return;
      setState(() => _recordElapsed = DateTime.now().difference(start));
      final elapsed = DateTime.now().difference(start);
      if (elapsed.inSeconds > 0 && elapsed.inSeconds % 12 == 0) {
        _enqueueDump(_position, why: '分段');
      }
    });
    NetLog.instance.add(
      '开始录制 dump-cache 从 ${formatClock(_position)} back-bytes=300MiB。stream-record 不写已经在缓存里的包',
    );
    if (mounted) setState(() => _recording = true);
  }

  void _enqueueDump(Duration end, {required String why}) {
    final start = _recordChunkFrom;
    if (!recordSpanIsUsable(start, end)) return;
    _recordChunkFrom = end;
    final index = _recordSegment++;
    final id = _recordId;
    _recordJobs = _recordJobs.then((_) => _dumpChunk(id, index, start, end, why));
  }

  Future<void> _dumpChunk(int id, int index, Duration start, Duration end, String why) async {
    final native = _player.platform;
    if (native is! NativePlayer) return;
    final directory = await recordingsDirectory();
    final path = p.join(directory.path, 'rec-$id-$index.ts');
    try {
      await native.command(['dump-cache', mpvSeconds(start), mpvSeconds(end), path]).timeout(const Duration(seconds: 20));
    } catch (error) {
      NetLog.instance.add('dump-cache 失败 $why ${mpvSeconds(start)}-${mpvSeconds(end)} $error');
    }
    final file = File(path);
    final size = await file.exists() ? await file.length() : 0;
    NetLog.instance.add('dump-cache $why ${mpvSeconds(start)}-${mpvSeconds(end)} ${size}B $path');
    if (size > 0) {
      _recordSegments.add(path);
    } else if (await file.exists()) {
      await file.delete();
    }
  }

  Future<File?> _joinSegments(Directory directory) async {
    final existing = <File>[];
    for (final path in _recordSegments) {
      final file = File(path);
      if (await file.exists() && await file.length() > 0) existing.add(file);
    }
    if (existing.isEmpty) return null;
    if (existing.length == 1) return existing.single;
    final combined = File(p.join(directory.path, 'rec-$_recordId.ts'));
    final sink = combined.openWrite();
    try {
      for (final file in existing) {
        await sink.addStream(file.openRead());
      }
    } finally {
      await sink.close();
    }
    for (final file in existing) {
      if (file.path != combined.path && await file.exists()) await file.delete();
    }
    final size = await combined.length();
    NetLog.instance.add('拼接录制 ${existing.length} 段 ${size}B ${combined.path}');
    return size > 0 ? combined : null;
  }

  Future<File?> _rereadClip(Directory directory, Duration start, Duration end) async {
    final headers = playbackHeaders(widget.playback.headers);
    final target = File(p.join(directory.path, 'rec-$_recordId-reread.mkv'));
    NetLog.instance.add('重读原地址剪辑 ${mpvSeconds(start)}-${mpvSeconds(end)}');
    try {
      await remuxWithMpv(
        input: _currentUrl,
        output: target.path,
        format: 'matroska',
        copyVideo: true,
        copyAudio: true,
        start: start,
        end: end,
        headers: headers,
      );
      final size = await target.length();
      NetLog.instance.add('重读剪辑 ${size}B ${target.path}');
      return target;
    } catch (error) {
      NetLog.instance.add('重读剪辑失败 $error');
      if (await target.exists()) await target.delete();
    }
    final clip = embyClipUrl(_currentUrl, start);
    if (clip == null) return null;
    final serverFile = File(p.join(directory.path, 'rec-$_recordId-server.mp4'));
    NetLog.instance.add('服务器剪辑 ${NetLog.redact(Uri.parse(clip))}');
    try {
      await remuxWithMpv(
        input: clip,
        output: serverFile.path,
        format: 'mp4',
        copyVideo: true,
        copyAudio: false,
        start: Duration.zero,
        end: end - start,
        headers: headers,
      );
      final size = await serverFile.length();
      NetLog.instance.add('服务器剪辑 ${size}B ${serverFile.path}');
      return serverFile;
    } catch (error) {
      NetLog.instance.add('服务器剪辑失败 $error');
      if (await serverFile.exists()) await serverFile.delete();
      return null;
    }
  }

  Future<void> _stopRecording() async {
    if (!_recording) return;
    _recordTimer?.cancel();
    final start = _recordStart;
    final end = _position;
    final ext = _recordExt;
    if (mounted) setState(() => _recording = false);
    _enqueueDump(end, why: '停止');
    try {
      await _recordJobs;
      final directory = await recordingsDirectory();
      var captured = await _joinSegments(directory);
      var capturedBytes = captured == null ? 0 : await captured.length();
      if (capturedBytes < 1024 && recordSpanIsUsable(start, end)) {
        NetLog.instance.add('缓存剪辑只有 ${capturedBytes}B，改从原地址重读');
        if (captured != null && await captured.exists()) await captured.delete();
        captured = await _rereadClip(directory, start, end);
        capturedBytes = captured == null ? 0 : await captured.length();
      }
      if (captured == null || capturedBytes <= 0) {
        NetLog.instance.add('停止录制失败 没有写出文件 0B');
        _tell('录制文件是空的');
        return;
      }
      var output = captured;
      final producedExt = p.extension(output.path).replaceAll('.', '').toLowerCase();
      final finalExt = producedExt == 'ts' ? ext : producedExt;
      final name = recordingFileName(
        title: widget.recordTitle ?? widget.title,
        episode: widget.recordEpisode,
        start: start,
        end: end,
        extension: finalExt.isEmpty ? ext : finalExt,
      );
      var dest = p.join(directory.path, name);
      if (await File(dest).exists()) {
        dest = p.join(directory.path, '${p.basenameWithoutExtension(name)}-$_recordId.$finalExt');
      }
      if (producedExt == 'ts' && finalExt != 'ts') {
        final remuxed = File(p.join(directory.path, 'rec-$_recordId.$finalExt'));
        try {
          await remuxWithMpv(
            input: output.path,
            output: remuxed.path,
            format: finalExt == 'mp4' || finalExt == 'mov' || finalExt == 'm4v' ? 'mp4' : 'matroska',
            copyVideo: true,
            copyAudio: true,
          );
          await output.delete();
          output = remuxed;
          NetLog.instance.add('录制封装 ${await remuxed.length()}B ${remuxed.path}');
        } catch (error) {
          NetLog.instance.add('录制封装失败，保留 ts $error');
          dest = p.join(directory.path, recordingFileName(
            title: widget.recordTitle ?? widget.title,
            episode: widget.recordEpisode,
            start: start,
            end: end,
            extension: 'ts',
          ));
        }
      }
      await output.rename(dest);
      final saved = await File(dest).length();
      NetLog.instance.add('停止录制 ${saved}B $dest');
      final autoSave = mounted && context.read<SettingsStore>().saveRecordingsToPhotos;
      _tell('已保存 ${p.basename(dest)}');
      if (autoSave) unawaited(_saveToPhotos(dest));
    } catch (error) {
      NetLog.instance.add('停止录制失败 $error');
      _tell('停止录制失败');
    } finally {
      _recordSegments.clear();
    }
  }

  Future<void> _saveToPhotos(String path) async {
    _tell('正在保存到相册');
    try {
      final message = await saveRecordingToPhotos(path);
      _tell(message);
    } catch (error) {
      NetLog.instance.add('保存到相册失败 $error');
      _tell('保存到相册失败');
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
    _noFrameWatch?.cancel();
    if (_recording) {
      final end = _position;
      unawaited(() async {
        try {
          _enqueueDump(end, why: '离开');
          await _recordJobs;
          NetLog.instance.add('离开播放器时已写出 ${_recordSegments.length} 段');
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
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: ivory),
                      ),
                      const SizedBox(height: 12),
                      TextButton(onPressed: _retry, child: const Text('重试', style: TextStyle(color: brass))),
                    ],
                  ),
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
