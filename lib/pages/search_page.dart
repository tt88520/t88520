import 'package:flutter/material.dart';
import 'package:new_tv/common/api.dart';
import 'package:new_tv/pages/detail_page.dart';
import 'package:new_tv/widgets/tv_focusable.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:cached_network_image/cached_network_image.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _controller = TextEditingController();
  List<dynamic> _searchResults = [];
  List<String> _history = [];
  bool _isLoading = false;
  final FocusNode _inputFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _loadHistory();
    // 自动聚焦输入框
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _inputFocus.requestFocus();
    });
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _history = prefs.getStringList('search_history') ?? [];
    });
  }

  Future<void> _saveHistory(String wd) async {
    if (wd.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    _history.remove(wd);
    _history.insert(0, wd);
    if (_history.length > 10) _history.removeLast();
    await prefs.setStringList('search_history', _history);
    setState(() {});
  }

  Future<void> _clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('search_history');
    setState(() {
      _history = [];
    });
  }

  Future<void> _onSearch(String wd) async {
    if (wd.isEmpty) {
      setState(() {
        _searchResults = [];
        _isLoading = false;
      });
      return;
    }

    setState(() => _isLoading = true);
    try {
      final res = await Api.getVideoList(page: 1, order: 'time', wd: wd);
      if (res.containsKey('list')) {
        setState(() {
          _searchResults = res['list'];
        });
      }
    } catch (e) {
      print('Search Error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 左侧搜索输入与历史
          _buildLeftSection(),
          // 右侧搜索结果
          Expanded(child: _buildResultSection()),
        ],
      ),
    );
  }

  Widget _buildLeftSection() {
    return Container(
      width: 350,
      padding: const EdgeInsets.all(40),
      decoration: const BoxDecoration(
        color: Color(0xFF161616),
        border: Border(right: BorderSide(color: Colors.white10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              TVFocusable(
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  child: const Icon(Icons.arrow_back, color: Colors.white),
                ),
              ),
              const Text('搜索视频', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 30),
          // 搜索框
          TextField(
            controller: _controller,
            focusNode: _inputFocus,
            style: const TextStyle(color: Colors.white, fontSize: 18),
            onChanged: (val) {
              _onSearch(val);
            },
            onSubmitted: (val) {
              _saveHistory(val);
            },
            decoration: InputDecoration(
              hintText: '输入片名、导演、主演...',
              hintStyle: const TextStyle(color: Colors.white24),
              prefixIcon: const Icon(Icons.search, color: Colors.red),
              filled: true,
              fillColor: Colors.white.withOpacity(0.05),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Colors.red, width: 2)),
            ),
          ),
          const SizedBox(height: 40),
          if (_history.isNotEmpty) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('搜索历史', style: TextStyle(color: Colors.white54, fontSize: 16)),
                TVFocusable(
                  onTap: _clearHistory,
                  child: const Text('清除', style: TextStyle(color: Colors.grey, fontSize: 14)),
                ),
              ],
            ),
            const SizedBox(height: 15),
            Expanded(
              child: ListView.builder(
                itemCount: _history.length,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: TVFocusable(
                      onTap: () {
                        _controller.text = _history[index];
                        _onSearch(_history[index]);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 15),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.03),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.history, color: Colors.grey, size: 18),
                            const SizedBox(width: 10),
                            Expanded(child: Text(_history[index], style: const TextStyle(color: Colors.white70, fontSize: 16), overflow: TextOverflow.ellipsis)),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildResultSection() {
    if (_isLoading) {
      return const Center(child: SpinKitFadingCube(color: Colors.red, size: 40));
    }

    if (_searchResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search, size: 100, color: Colors.white.withOpacity(0.05)),
            const SizedBox(height: 20),
            Text(_controller.text.isEmpty ? '想看点什么呢？' : '未找到相关视频', 
                 style: const TextStyle(color: Colors.white24, fontSize: 20)),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(40),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 1.6,
        crossAxisSpacing: 25,
        mainAxisSpacing: 25,
      ),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final video = _searchResults[index];
        return TVFocusable(
          onTap: () {
            _saveHistory(_controller.text);
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => DetailPage(videoId: video['vod_id'].toString())),
            );
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: CachedNetworkImage(
                          imageUrl: video['vod_pic'] ?? '',
                          fit: BoxFit.cover,
                          errorWidget: (context, url, error) => const Icon(Icons.image_not_supported, color: Colors.grey),
                        ),
                      ),
                      Positioned(
                        bottom: 0, left: 0, right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Colors.black.withOpacity(0.8), Colors.transparent]),
                          ),
                          child: Text(video['vod_remarks'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 10, left: 5),
                child: Text(video['vod_name'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 16), maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        );
      },
    );
  }
}

