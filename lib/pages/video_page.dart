import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:new_tv/common/api.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:new_tv/widgets/tv_focusable.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

class VideoPage extends StatefulWidget {
  final String videoId;
  final int? initialSourceIndex;
  final int? initialEpisodeIndex;
  const VideoPage({
    super.key, 
    required this.videoId,
    this.initialSourceIndex,
    this.initialEpisodeIndex,
  });

  @override
  State<VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<VideoPage> {
  dynamic _detail;
  List<Map<String, dynamic>> _sources = [];
  List<Map<String, String>> _episodes = [];
  int _currentSourceIndex = 0;
  int _currentEpisodeIndex = 0;
  bool _isLoading = true;
  bool _isDirectLink = false;
  bool _showRemoteControls = true;
  bool _isFullScreenMode = false;
  String _announcement = '';
  Timer? _hideTimer;

  late final Player _player = Player();
  late final VideoController _videoController = VideoController(_player);
  WebViewController? _webViewController;

  @override
  void initState() {
    super.initState();
    _currentSourceIndex = widget.initialSourceIndex ?? 0;
    _currentEpisodeIndex = widget.initialEpisodeIndex ?? 0;
    _fetchDetail();
    _fetchAnnouncement();
    _resetHideTimer();
  }

  Future<void> _fetchAnnouncement() async {
    try {
      final config = await Api.getConfig();
      if (config.containsKey('data') && config['data'] != null) {
        setState(() {
          _announcement = config['data']['app_notice'] ?? '';
        });
      }
    } catch (e) {
      print('Fetch Announcement Error: $e');
    }
  }

  void _resetHideTimer() {
    _hideTimer?.cancel();
    if (!mounted) return;
    if (!_showRemoteControls) {
      setState(() => _showRemoteControls = true);
    }
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() => _showRemoteControls = false);
      }
    });
  }

  Future<void> _fetchDetail() async {
    setState(() => _isLoading = true);
    final detail = await Api.getDetail(widget.videoId);
    if (detail.isNotEmpty) {
      _detail = detail;
      _parseSources(detail);
      if (_sources.isNotEmpty) {
        if (_currentSourceIndex >= _sources.length) _currentSourceIndex = 0;
        _switchSource(_currentSourceIndex, autoPlay: true, episodeIndex: _currentEpisodeIndex);
      }
    }
    setState(() => _isLoading = false);
  }

  void _parseSources(dynamic detail) {
    final fromStr = detail['vod_play_from'] ?? '';
    final urlStr = detail['vod_play_url'] ?? '';
    final fromList = fromStr.split('\$\$\$');
    final urlList = urlStr.split('\$\$\$');
    _sources = [];
    for (int i = 0; i < fromList.length; i++) {
      if (fromList[i].isNotEmpty) {
        _sources.add({
          'name': fromList[i],
          'urls': urlList.length > i ? urlList[i] : '',
        });
      }
    }
  }

  void _switchSource(int index, {bool autoPlay = false, int? episodeIndex}) {
    setState(() {
      _currentSourceIndex = index;
      final urlData = _sources[index]['urls'] as String;
      final items = urlData.split('#');
      _episodes = items.map((item) {
        final parts = item.split('\$');
        return {
          'name': parts[0],
          'url': parts.length > 1 ? parts[1] : parts[0],
        };
      }).toList();
    });
    if (autoPlay && _episodes.isNotEmpty) {
      int targetEpisode = episodeIndex ?? 0;
      if (targetEpisode >= _episodes.length) targetEpisode = 0;
      _playEpisode(targetEpisode);
    }
  }

  Future<void> _playEpisode(int index) async {
    await _player.stop();
    WakelockPlus.enable();
    setState(() {
      _currentEpisodeIndex = index;
      final url = _episodes[index]['url']!;
      
      final lowerUrl = url.toLowerCase();
      // 更加精准的直链判断逻辑
      _isDirectLink = lowerUrl.contains('.m3u8') || 
                      lowerUrl.contains('.mp4') || 
                      lowerUrl.contains('.flv') ||
                      lowerUrl.contains('.mkv') ||
                      lowerUrl.contains('playlist.m3u8');
      
      if (_isDirectLink) {
        _initVideoPlayer(url);
      } else {
        _initWebView(url);
      }
    });
    _resetHideTimer();
  }

  void _initVideoPlayer(String url) async {
    // 针对 PC 端优化：添加 UserAgent 和 Referer
    await _player.open(
      Media(
        url,
        httpHeaders: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Referer': url.split('?')[0],
        },
      ),
    );
    
    final prefs = await SharedPreferences.getInstance();
    final progressKey = 'progress_${widget.videoId}_${_currentSourceIndex}_${_currentEpisodeIndex}';
    final savedSeconds = prefs.getInt(progressKey) ?? 0;
    if (savedSeconds > 0) {
      _player.seek(Duration(seconds: savedSeconds));
    }

    _player.stream.position.listen((position) {
      if (position.inSeconds > 5 && position.inSeconds % 5 == 0) {
        prefs.setInt(progressKey, position.inSeconds);
        _saveToHistory();
      }
    });
    setState(() {});
    _resetHideTimer();
  }

  Future<void> _saveToHistory() async {
    if (_detail == null) return;
    final prefs = await SharedPreferences.getInstance();
    final String historyStr = prefs.getString('watch_history') ?? '[]';
    List<dynamic> history = jsonDecode(historyStr);
    final String videoId = widget.videoId;
    history.removeWhere((item) => item['vod_id'].toString() == videoId);
    final Map<String, dynamic> record = {
      'vod_id': _detail['vod_id'],
      'vod_name': _detail['vod_name'],
      'vod_pic': _detail['vod_pic'],
      'vod_remarks': _detail['vod_remarks'],
      'time': DateTime.now().millisecondsSinceEpoch,
      'position': _player.state.position.inSeconds,
      'duration': _player.state.duration.inSeconds,
      'source_index': _currentSourceIndex,
      'episode_index': _currentEpisodeIndex,
      'episode_name': _episodes.isNotEmpty ? _episodes[_currentEpisodeIndex]['name'] : '',
    };
    history.insert(0, record);
    if (history.length > 50) history = history.sublist(0, 50);
    await prefs.setString('watch_history', jsonEncode(history));
  }

  void _initWebView(String url) {
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..loadRequest(Uri.parse(url));
  }

  void _disposePlayer() {
    WakelockPlus.disable();
    _hideTimer?.cancel();
    _player.dispose();
    _webViewController = null;
  }

  @override
  void dispose() {
    _disposePlayer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isFullScreenMode,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_isFullScreenMode) {
          setState(() {
            _isFullScreenMode = false;
          });
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Row(
          children: [
            if (!_isFullScreenMode) _buildSidePanel(),
            Expanded(child: _buildPlayerArea()),
          ],
        ),
      ),
    );
  }

  Widget _buildSidePanel() {
    return Container(
      width: 200,
      color: const Color(0xFF121212),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Column(
                children: [
                  Image.asset(
                    'assets/images/logo.png',
                    width: 100,
                    fit: BoxFit.contain,
                    errorBuilder: (c, e, s) => const Text('唐人街影院', style: TextStyle(color: Colors.red, fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 4),
                  const Text('v1.9 - PC Fix', style: TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TVFocusable(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
                  ),
                ),
                if (_detail != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _detail['vod_name'],
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${_detail['vod_remarks']} · ${_detail['vod_year']}',
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  const SizedBox(height: 15),
                ],
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Text('播放源', style: TextStyle(fontSize: 14, color: Colors.white54)),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 40,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 15),
              itemCount: _sources.length,
              itemBuilder: (context, index) {
                final isActive = _currentSourceIndex == index;
                String displayName = index == 0 ? "主线路" : "线路${index + 1}";
                return TVFocusable(
                  onTap: () => _switchSource(index, autoPlay: true),
                  scale: 1.05,
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 5),
                    padding: const EdgeInsets.symmetric(horizontal: 15),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isActive ? Colors.red : Colors.white10,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      displayName,
                      style: TextStyle(color: isActive ? Colors.white : Colors.white70, fontSize: 12),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 20),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Text('选集', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              itemCount: _episodes.length,
              itemBuilder: (context, index) {
                final isActive = _currentEpisodeIndex == index;
                return TVFocusable(
                  onTap: () => _playEpisode(index),
                  scale: 1.02,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 15),
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    decoration: BoxDecoration(
                      color: isActive ? Colors.red.withOpacity(0.2) : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: isActive ? Border.all(color: Colors.red.withOpacity(0.5)) : null,
                    ),
                    child: Row(
                      children: [
                        if (isActive) 
                          const Padding(
                            padding: EdgeInsets.only(right: 10),
                            child: Icon(Icons.play_arrow, color: Colors.red, size: 16),
                          ),
                        Expanded(
                          child: Text(
                            _episodes[index]['name']!,
                            style: TextStyle(
                              color: isActive ? Colors.red : Colors.white70,
                              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayerArea() {
    return Focus(
      onKeyEvent: (node, event) {
        _resetHideTimer();
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.numpadEnter) {
            _player.playOrPause();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Container(
        decoration: const BoxDecoration(color: Colors.black),
        child: Stack(
          children: [
            Center(
              child: _isLoading 
                ? const SpinKitFadingCube(color: Colors.red, size: 50)
                : _isDirectLink 
                  ? Video(controller: _videoController)
                  : (_webViewController != null 
                      ? WebViewWidget(controller: _webViewController!)
                      : const SizedBox()),
            ),
            if (_announcement.isNotEmpty)
              Positioned(top: 0, left: 0, right: 0, child: _buildMarquee()),
            if (!_isLoading && _isDirectLink)
              Positioned(
                bottom: 20, left: 40, right: 40,
                child: AnimatedOpacity(
                  opacity: _showRemoteControls ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 300),
                  child: IgnorePointer(ignoring: !_showRemoteControls, child: _buildRemoteProgressBar()),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMarquee() {
    return Container(
      height: 40,
      color: Colors.black.withOpacity(0.7),
      child: _MarqueeText(text: _announcement),
    );
  }

  Widget _buildRemoteProgressBar() {
    return StreamBuilder<Duration>(
      stream: _player.stream.position,
      builder: (context, snapshot) {
        final position = snapshot.data ?? _player.state.position;
        final duration = _player.state.duration;
        final progress = duration.inMilliseconds > 0 ? position.inMilliseconds / duration.inMilliseconds : 0.0;
        return Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(15)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_formatDuration(position), style: const TextStyle(color: Colors.white, fontSize: 12)),
                  Text(_formatDuration(duration), style: const TextStyle(color: Colors.white54, fontSize: 12)),
                ],
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: progress, backgroundColor: Colors.white10, color: Colors.red),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(icon: const Icon(Icons.replay_10, color: Colors.white), onPressed: () => _player.seek(position - const Duration(seconds: 10))),
                  StreamBuilder<bool>(
                    stream: _player.stream.playing,
                    builder: (context, s) => IconButton(
                      icon: Icon(s.data ?? false ? Icons.pause : Icons.play_arrow, color: Colors.white, size: 40),
                      onPressed: () => _player.playOrPause(),
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.forward_10, color: Colors.white), onPressed: () => _player.seek(position + const Duration(seconds: 10))),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return duration.inHours > 0 ? "${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds" : "$twoDigitMinutes:$twoDigitSeconds";
  }
}

class _MarqueeText extends StatefulWidget {
  final String text;
  const _MarqueeText({required this.text});
  @override
  State<_MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<_MarqueeText> {
  late ScrollController _scrollController;
  Timer? _timer;
  double _offset = 0.0;
  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    Future.delayed(const Duration(milliseconds: 500), () => _startScrolling());
  }
  void _startScrolling() {
    _timer = Timer.periodic(const Duration(milliseconds: 40), (timer) {
      if (!mounted || !_scrollController.hasClients) return;
      double maxScroll = _scrollController.position.maxScrollExtent;
      if (maxScroll <= 0) return;
      _offset += 2.0;
      if (_offset >= maxScroll) _offset = 0.0;
      _scrollController.jumpTo(_offset);
    });
  }
  @override
  void dispose() {
    _timer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: _scrollController,
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        Container(
          height: 40, alignment: Alignment.center, padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(widget.text, style: const TextStyle(color: Colors.amber, fontSize: 16, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(width: 500),
        Container(
          height: 40, alignment: Alignment.center, padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(widget.text, style: const TextStyle(color: Colors.amber, fontSize: 16, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
