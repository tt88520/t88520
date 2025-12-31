import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:new_tv/common/api.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:new_tv/widgets/tv_focusable.dart';

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
  bool _isFullScreenMode = false; // 新增：内部全屏模式标记
  String _announcement = '';
  Timer? _hideTimer;

  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;
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
        // 确保初始索引在范围内
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
    _disposePlayer();
    // 启用屏幕常亮
    WakelockPlus.enable();
    setState(() {
      _currentEpisodeIndex = index;
      final url = _episodes[index]['url']!;
      _isDirectLink = url.contains('.m3u8') || url.contains('.mp4');
      
      if (_isDirectLink) {
        _initVideoPlayer(url);
      } else {
        _initWebView(url);
      }
    });
    _resetHideTimer(); // 切换集数时重置计时器
  }

  void _initVideoPlayer(String url) async {
    _videoPlayerController = VideoPlayerController.networkUrl(Uri.parse(url));
    await _videoPlayerController!.initialize();

    // 恢复进度
    final prefs = await SharedPreferences.getInstance();
    final progressKey = 'progress_${widget.videoId}_${_currentSourceIndex}_${_currentEpisodeIndex}';
    final savedSeconds = prefs.getInt(progressKey) ?? 0;
    if (savedSeconds > 0) {
      _videoPlayerController!.seekTo(Duration(seconds: savedSeconds));
    }

    _chewieController = ChewieController(
      videoPlayerController: _videoPlayerController!,
      autoPlay: true,
      looping: false,
      isLive: url.contains('m3u8'),
      aspectRatio: _videoPlayerController!.value.aspectRatio,
      showControls: false, // 禁用 Chewie 默认控制栏，只使用我们自定义的
      showControlsOnInitialize: false,
      allowedScreenSleep: false,
      placeholder: Container(color: Colors.black),
    );

    _videoPlayerController!.addListener(() {
      if (_videoPlayerController!.value.position.inSeconds > 5) {
        prefs.setInt(progressKey, _videoPlayerController!.value.position.inSeconds);
        _saveToHistory(); // 实时更新历史记录中的进度
      }
    });

    setState(() {});
    _resetHideTimer(); // 初始化完成，开启 3 秒隐藏计时
  }

  Future<void> _saveToHistory() async {
    if (_detail == null) return;
    
    final prefs = await SharedPreferences.getInstance();
    final String historyStr = prefs.getString('watch_history') ?? '[]';
    List<dynamic> history = jsonDecode(historyStr);

    final String videoId = widget.videoId;
    
    // 移除旧的相同视频记录
    history.removeWhere((item) => item['vod_id'].toString() == videoId);

    // 准备新的记录
    final Map<String, dynamic> record = {
      'vod_id': _detail['vod_id'],
      'vod_name': _detail['vod_name'],
      'vod_pic': _detail['vod_pic'],
      'vod_remarks': _detail['vod_remarks'],
      'time': DateTime.now().millisecondsSinceEpoch,
      'position': _videoPlayerController?.value.position.inSeconds ?? 0,
      'duration': _videoPlayerController?.value.duration.inSeconds ?? 0,
      'source_index': _currentSourceIndex,
      'episode_index': _currentEpisodeIndex,
      'episode_name': _episodes.isNotEmpty ? _episodes[_currentEpisodeIndex]['name'] : '',
    };

    // 插入到开头
    history.insert(0, record);

    // 最多保留 50 条
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
    // 释放播放器时关闭常亮
    WakelockPlus.disable();
    _hideTimer?.cancel();
    _chewieController?.dispose();
    _videoPlayerController?.dispose();
    _chewieController = null;
    _videoPlayerController = null;
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
      width: 200, // 从 300 减少到 200，大约是原来的 2/3
      color: const Color(0xFF121212),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Logo 和 版本号
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
                  const Text('v1.9 - New Layout', style: TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
          // 顶部返回与基本信息
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15), // 稍微缩小边距以适应更窄的宽度
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
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white), // 减小字体
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${_detail['vod_remarks']} · ${_detail['vod_year']}',
                    style: const TextStyle(color: Colors.grey, fontSize: 12), // 减小字体
                  ),
                  const SizedBox(height: 15),
                  // 全屏按钮已移动到底部控制栏
                ],
              ],
            ),
          ),

          // 播放源选择 (水平滚动)
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
                // 强制重命名线路名称
                String displayName = "";
                if (index == 0) displayName = "主线路";
                else if (index == 1) displayName = "线路二";
                else if (index == 2) displayName = "线路三";
                else if (index == 3) displayName = "线路四";
                else displayName = "线路${index + 1}";

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

          // 选集列表 (占据剩余空间)
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
        // 任何按键都重置隐藏计时器
        _resetHideTimer();
        
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.numpadEnter) {
            if (_chewieController != null) {
              _chewieController!.togglePause();
            }
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Container(
        decoration: const BoxDecoration(color: Colors.black),
        child: Stack(
          children: [
            // 1. 底部播放器层
            Center(
              child: _isLoading 
                ? _buildLoadingUI()
                : _isDirectLink 
                  ? (_chewieController != null 
                      ? Chewie(controller: _chewieController!) 
                      : const Center(child: SpinKitFadingCube(color: Colors.red, size: 50)))
                      : (_webViewController != null 
                      ? WebViewWidget(controller: _webViewController!)
                      : const SizedBox()),
            ),
            
            // 2. 透明点击层：覆盖全屏，用于捕获视频区域的点击来呼出控制栏
            Positioned.fill(
              child: GestureDetector(
                onTap: _resetHideTimer,
                behavior: HitTestBehavior.translucent, // 允许事件穿透，但不被视频层完全吸收
              ),
            ),

            // 3. 顶部滚动公告
            if (_announcement.isNotEmpty)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: _buildMarquee(),
              ),

            // 4. 底部遥控器进度条控制区
            if (!_isLoading && _isDirectLink && _videoPlayerController != null)
              Positioned(
                bottom: 20,
                left: 40,
                right: 40,
                child: AnimatedOpacity(
                  opacity: _showRemoteControls ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 300),
                  child: IgnorePointer(
                    ignoring: !_showRemoteControls,
                    child: _buildRemoteProgressBar(),
                  ),
                ),
              ),

            // 5. 左上角返回按钮 (全屏或非全屏下呼出控制栏时显示)
            if (!_isLoading)
              Positioned(
                top: 50,
                left: 20,
                child: AnimatedOpacity(
                  opacity: _showRemoteControls ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 300),
                  child: IgnorePointer(
                    ignoring: !_showRemoteControls,
                    child: TVFocusable(
                      onTap: () {
                        if (_isFullScreenMode) {
                          setState(() => _isFullScreenMode = false);
                        } else {
                          Navigator.pop(context);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white24),
                        ),
                        child: const Icon(Icons.arrow_back, color: Colors.white, size: 28),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingUI() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SpinKitFadingCube(color: Colors.red, size: 50),
        const SizedBox(height: 30),
        const Text('正在加载视频...', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 15),
        _buildShortcutTips(),
      ],
    );
  }

  Widget _buildMarquee() {
    return Container(
      height: 40,
      color: Colors.black.withOpacity(0.7),
      child: _MarqueeText(text: _announcement),
    );
  }

  Widget _buildShortcutTips() {
    return Container(
      padding: const EdgeInsets.all(10),
      color: Colors.black54,
      child: const Text(
        '遥控器快捷键：\nOK键：播放/暂停\n方向下：选中进度条\n方向左：返回侧边栏', 
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.amber, fontSize: 14, height: 1.5)
      ),
    );
  }

  Widget _buildRemoteProgressBar() {
    return ValueListenableBuilder(
      valueListenable: _videoPlayerController!,
      builder: (context, VideoPlayerValue value, child) {
        final position = value.position;
        final duration = value.duration;
        final isPlaying = value.isPlaying;
        final progress = duration.inMilliseconds > 0 
            ? position.inMilliseconds / duration.inMilliseconds 
            : 0.0;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12), // 减小内边距 (原 25, 20)
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.85), // 稍微调高透明度
            borderRadius: BorderRadius.circular(15), // 减小圆角 (原 20)
            border: Border.all(color: Colors.white10),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 15)
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 1. 进度条区域 (独立聚焦，支持左右拉动)
              TVFocusable(
                onTap: () {
                  _chewieController?.togglePause();
                  _resetHideTimer();
                },
                scale: 1.0,
                child: Focus(
                  onKeyEvent: (node, event) {
                    _resetHideTimer(); // 重置计时器
                    if (event is KeyDownEvent || event is KeyRepeatEvent) {
                      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                        _videoPlayerController!.seekTo(position - const Duration(seconds: 10));
                        return KeyEventResult.handled;
                      } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                        _videoPlayerController!.seekTo(position + const Duration(seconds: 10));
                        return KeyEventResult.handled;
                      }
                    }
                    return KeyEventResult.ignored;
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 10), // 减小垂直间距 (原 10)
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(_formatDuration(position), style: const TextStyle(color: Colors.white, fontSize: 12)), // 减小字号
                            Text(_formatDuration(duration), style: const TextStyle(color: Colors.white54, fontSize: 12)),
                          ],
                        ),
                        const SizedBox(height: 6), // 减小间距 (原 8)
                        Stack(
                          children: [
                            Container(
                              height: 4, // 减小高度 (原 8)
                              width: double.infinity,
                              decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(2)),
                            ),
                            FractionallySizedBox(
                              widthFactor: progress.clamp(0.0, 1.0),
                              child: Container(
                                height: 4, // 减小高度 (原 8)
                                decoration: BoxDecoration(
                                  color: Colors.red, 
                                  borderRadius: BorderRadius.circular(2),
                                  boxShadow: [const BoxShadow(color: Colors.redAccent, blurRadius: 2)]
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8), // 减小间距 (原 15)
              // 2. 控制按钮区域 (每个按钮独立聚焦)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 上一集
                  if (_episodes.length > 1)
                    _buildControlIcon(
                      Icons.skip_previous, 
                      () {
                        if (_currentEpisodeIndex > 0) _playEpisode(_currentEpisodeIndex - 1);
                        _resetHideTimer();
                      },
                      enabled: _currentEpisodeIndex > 0,
                    ),
                  
                  const SizedBox(width: 15), // 减小间距 (原 20)
                  _buildControlIcon(Icons.fast_rewind, () {
                    _videoPlayerController!.seekTo(position - const Duration(seconds: 15));
                    _resetHideTimer();
                  }),
                  
                  const SizedBox(width: 15),
                  _buildControlIcon(
                    isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled, 
                    () {
                      _chewieController?.togglePause();
                      _resetHideTimer();
                    },
                    isLarge: true
                  ),
                  
                  const SizedBox(width: 15),
                  _buildControlIcon(Icons.fast_forward, () {
                    _videoPlayerController!.seekTo(position + const Duration(seconds: 15));
                    _resetHideTimer();
                  }),

                  const SizedBox(width: 15),
                  // 下一集
                  if (_episodes.length > 1)
                    _buildControlIcon(
                      Icons.skip_next, 
                      () {
                        if (_currentEpisodeIndex < _episodes.length - 1) _playEpisode(_currentEpisodeIndex + 1);
                        _resetHideTimer();
                      },
                      enabled: _currentEpisodeIndex < _episodes.length - 1,
                    ),
                  
                  const SizedBox(width: 25), // 减小间距 (原 30)
                  // 全屏按钮 (切换侧边栏显示)
                  _buildControlIcon(
                    _isFullScreenMode ? Icons.fullscreen_exit : Icons.fullscreen, 
                    () {
                      setState(() => _isFullScreenMode = !_isFullScreenMode);
                      _resetHideTimer();
                    }
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildControlIcon(IconData icon, VoidCallback onTap, {bool isLarge = false, bool enabled = true}) {
    return TVFocusable(
      onTap: enabled ? onTap : () {},
      scale: enabled ? 1.2 : 1.0,
      child: Container(
        padding: const EdgeInsets.all(8),
        child: Icon(
          icon, 
          color: enabled ? Colors.white : Colors.white24, 
          size: isLarge ? 48 : 32
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    if (duration.inHours > 0) {
      return "${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
    }
    return "$twoDigitMinutes:$twoDigitSeconds";
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
    // 延迟启动，确保布局完成
    Future.delayed(const Duration(milliseconds: 500), () {
      _startScrolling();
    });
  }

  void _startScrolling() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 40), (timer) {
      if (!mounted) return;
      if (_scrollController.hasClients) {
        double maxScroll = _scrollController.position.maxScrollExtent;
        // 如果文字太短不需要滚动，则不执行
        if (maxScroll <= 0) return;

        _offset += 2.0; // 每一帧移动的像素数
        if (_offset >= maxScroll) {
          _offset = 0.0;
          _scrollController.jumpTo(_offset);
        } else {
          _scrollController.jumpTo(_offset);
        }
      }
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
          height: 40,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Text(
                widget.text,
                style: const TextStyle(color: Colors.amber, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 500), // 循环间距
              Text(
                widget.text,
                style: const TextStyle(color: Colors.amber, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 500),
            ],
          ),
        ),
      ],
    );
  }
}
