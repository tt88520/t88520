import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:new_tv/widgets/tv_focusable.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:new_tv/pages/detail_page.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<dynamic> _history = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final String historyStr = prefs.getString('watch_history') ?? '[]';
    setState(() {
      _history = jsonDecode(historyStr);
      _isLoading = false;
    });
  }

  Future<void> _clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('watch_history');
    setState(() {
      _history = [];
    });
  }

  String _formatTime(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return "${date.month}-${date.day} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Row(
        children: [
          // 左侧标题和操作
          Container(
            width: 200,
            padding: const EdgeInsets.all(30),
            decoration: const BoxDecoration(
              color: Color(0xFF0F0F0F),
              border: Border(right: BorderSide(color: Colors.white10)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TVFocusable(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    child: const Icon(Icons.arrow_back, color: Colors.white),
                  ),
                ),
                const SizedBox(height: 40),
                const Text('观看历史', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                Text('共 ${_history.length} 条记录', style: const TextStyle(color: Colors.grey, fontSize: 14)),
                const Spacer(),
                if (_history.isNotEmpty)
                  TVFocusable(
                    onTap: _clearHistory,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 15),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.delete_outline, color: Colors.grey, size: 18),
                          SizedBox(width: 8),
                          Text('清空历史', style: TextStyle(color: Colors.grey)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          
          // 右侧历史列表
          Expanded(
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator(color: Colors.red))
              : _history.isEmpty
                ? const Center(child: Text('暂无观看历史', style: TextStyle(color: Colors.white24, fontSize: 20)))
                : GridView.builder(
                    padding: const EdgeInsets.all(40),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 5,
                      childAspectRatio: 0.55, // 调小比例，增加下方文字空间
                      crossAxisSpacing: 20,
                      mainAxisSpacing: 30,
                    ),
                    itemCount: _history.length,
                    itemBuilder: (context, index) {
                      final item = _history[index];
                      final double progress = (item['duration'] ?? 0) > 0 
                          ? (item['position'] ?? 0) / (item['duration'] ?? 1)
                          : 0.0;
                      
                      return TVFocusable(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => DetailPage(videoId: item['vod_id'].toString())),
                          ).then((_) => _loadHistory()); // 返回时刷新历史
                        },
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min, // 确保 Column 占用最小空间
                          children: [
                            AspectRatio( // 使用 AspectRatio 代替 Expanded
                              aspectRatio: 0.7, 
                              child: Stack(
                                children: [
                                  Container(
                                    width: double.infinity,
                                    height: double.infinity,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(8),
                                      color: Colors.grey[900],
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    child: CachedNetworkImage(
                                      imageUrl: item['vod_pic'] ?? '',
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                  // 进度条
                                  Positioned(
                                    bottom: 0,
                                    left: 0,
                                    right: 0,
                                    child: Column(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(5),
                                          color: Colors.black54,
                                          width: double.infinity,
                                          child: Text(
                                            item['episode_name'] ?? '',
                                            style: const TextStyle(color: Colors.amber, fontSize: 10),
                                            textAlign: TextAlign.center,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        LinearProgressIndicator(
                                          value: progress,
                                          backgroundColor: Colors.white24,
                                          color: Colors.red,
                                          minHeight: 3,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 5),
                              child: Text(
                                item['vod_name'] ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white, fontSize: 14),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 5),
                              child: Text(
                                _formatTime(item['time']),
                                style: const TextStyle(color: Colors.white24, fontSize: 11),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

