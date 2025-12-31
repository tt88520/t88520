import 'package:flutter/material.dart';
import 'package:new_tv/common/api.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:new_tv/pages/video_page.dart';
import 'package:new_tv/widgets/tv_focusable.dart';

class DetailPage extends StatefulWidget {
  final String videoId;
  const DetailPage({super.key, required this.videoId});

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  dynamic _detail;
  bool _isLoading = true;
  List<Map<String, dynamic>> _sources = [];
  int _currentSourceIndex = 0;

  @override
  void initState() {
    super.initState();
    _fetchDetail();
  }

  Future<void> _fetchDetail() async {
    setState(() => _isLoading = true);
    try {
      final detail = await Api.getDetail(widget.videoId);
      if (detail.isNotEmpty) {
        setState(() {
          _detail = detail;
          _parseSources(detail);
        });
      }
    } catch (e) {
      print('Fetch Detail Error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _parseSources(dynamic detail) {
    final fromStr = detail['vod_play_from'] ?? '';
    final urlStr = detail['vod_play_url'] ?? '';

    final fromList = fromStr.split('\$\$\$');
    final urlList = urlStr.split('\$\$\$');

    _sources = [];
    for (int i = 0; i < fromList.length; i++) {
      if (fromList[i].isNotEmpty) {
        final urlData = urlList.length > i ? urlList[i] : '';
        final items = urlData.split('#');
        final episodes = items.map((item) {
          final parts = item.split('\$');
          return {
            'name': parts[0],
            'url': parts.length > 1 ? parts[1] : parts[0],
          };
        }).toList();

        _sources.add({
          'name': fromList[i],
          'episodes': episodes,
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      body: _isLoading
          ? const Center(child: SpinKitFadingCube(color: Colors.red, size: 50))
          : _detail == null
              ? const Center(child: Text('获取详情失败', style: TextStyle(color: Colors.white)))
              : Stack(
                  children: [
                    _buildBackground(),
                    _buildContent(),
                  ],
                ),
    );
  }

  Widget _buildBackground() {
    return Positioned.fill(
      child: Opacity(
        opacity: 0.2,
        child: CachedNetworkImage(
          imageUrl: _detail['vod_pic'] ?? '',
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
        ),
      ),
    );
  }

  Widget _buildContent() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black.withOpacity(0.8), Colors.black],
        ),
      ),
      child: Row(
        children: [
          // 左侧：海报和操作
          _buildLeftSection(),
          // 右侧：详情和选集
          Expanded(child: _buildRightSection()),
        ],
      ),
    );
  }

  Widget _buildLeftSection() {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Container(
      width: screenWidth * 0.25, // 占 25% 宽度
      padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.02, vertical: screenHeight * 0.05),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Hero(
            tag: 'video_${_detail['vod_id']}',
            child: Container(
              width: screenWidth * 0.16,
              height: screenHeight * 0.45,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 15, spreadRadius: 2)
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: CachedNetworkImage(
                imageUrl: _detail['vod_pic'] ?? '',
                fit: BoxFit.cover,
              ),
            ),
          ),
          SizedBox(height: screenHeight * 0.05),
          TVFocusable(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => VideoPage(
                  videoId: widget.videoId,
                  initialSourceIndex: _currentSourceIndex,
                  initialEpisodeIndex: 0,
                )),
              );
            },
            borderRadius: 25, // 指定圆角
            child: Container(
              width: screenWidth * 0.16,
              padding: EdgeInsets.symmetric(vertical: screenHeight * 0.015),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(25),
                boxShadow: [
                  BoxShadow(color: Colors.red.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4))
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.play_arrow, color: Colors.white, size: screenHeight * 0.025),
                  const SizedBox(width: 8),
                  Text('立即播放', style: TextStyle(color: Colors.white, fontSize: screenHeight * 0.018, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
          SizedBox(height: screenHeight * 0.02),
          TVFocusable(
            onTap: () => Navigator.pop(context),
            borderRadius: 25, // 指定圆角
            child: Container(
              width: screenWidth * 0.16,
              padding: EdgeInsets.symmetric(vertical: screenHeight * 0.015),
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(25),
                border: Border.all(color: Colors.white24),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.arrow_back, color: Colors.white, size: screenHeight * 0.02),
                  const SizedBox(width: 8),
                  Text('返回首页', style: TextStyle(color: Colors.white, fontSize: screenHeight * 0.016)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRightSection() {
    final screenHeight = MediaQuery.of(context).size.height;
    
    return Container(
      padding: EdgeInsets.fromLTRB(10, screenHeight * 0.06, screenHeight * 0.06, screenHeight * 0.03),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题
          Text(
            _detail['vod_name'] ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: screenHeight * 0.045, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          SizedBox(height: screenHeight * 0.015),
          // 标签栏
          Row(
            children: [
              _buildInfoTag(_detail['vod_remarks'] ?? '高清'),
              SizedBox(width: screenHeight * 0.02),
              Text(_detail['vod_year'] ?? '', style: TextStyle(color: Colors.white70, fontSize: screenHeight * 0.018)),
              SizedBox(width: screenHeight * 0.02),
              Text(_detail['vod_area'] ?? '', style: TextStyle(color: Colors.white70, fontSize: screenHeight * 0.018)),
              SizedBox(width: screenHeight * 0.02),
              Text(_detail['type_name'] ?? '', style: TextStyle(color: Colors.white70, fontSize: screenHeight * 0.018)),
              SizedBox(width: screenHeight * 0.02),
              Icon(Icons.star, color: Colors.amber, size: screenHeight * 0.02),
              const SizedBox(width: 4),
              Text(_detail['vod_score'] ?? '0.0', style: TextStyle(color: Colors.amber, fontSize: screenHeight * 0.02, fontWeight: FontWeight.bold)),
            ],
          ),
          SizedBox(height: screenHeight * 0.02),
          // 导演主演
          _buildDetailRow('导演：', _detail['vod_director'] ?? '未知'),
          SizedBox(height: screenHeight * 0.005),
          _buildDetailRow('主演：', _detail['vod_actor']?.replaceAll(',', ' / ') ?? '未知'),
          SizedBox(height: screenHeight * 0.02),
          // 剧情介绍 - 限制行数
          Text('剧情介绍：', style: TextStyle(color: Colors.white, fontSize: screenHeight * 0.022, fontWeight: FontWeight.bold)),
          SizedBox(height: screenHeight * 0.005),
          Text(
            _detail['vod_content']?.replaceAll(RegExp(r'<[^>]*>'), '') ?? '暂无介绍',
            maxLines: 3, // 严格限制在 3 行
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.white70, fontSize: screenHeight * 0.016, height: 1.4),
          ),
          SizedBox(height: screenHeight * 0.03),
          
          // 播放源和选集 - 使用 Expanded + 滚动
          if (_sources.isNotEmpty) ...[
            Text('选集列表：', style: TextStyle(color: Colors.white, fontSize: screenHeight * 0.022, fontWeight: FontWeight.bold)),
            SizedBox(height: screenHeight * 0.015),
            
            // 播放源切换
            if (_sources.length > 1)
              SizedBox(
                height: screenHeight * 0.045,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _sources.length,
                  itemBuilder: (context, index) {
                    final isActive = _currentSourceIndex == index;
                    String displayName = (index == 0) ? "主线路" : "线路${index + 1}";
                    if (index == 1) displayName = "线路二";
                    if (index == 2) displayName = "线路三";

                    return Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: TVFocusable(
                        onTap: () => setState(() => _currentSourceIndex = index),
                        borderRadius: 20, // 指定圆角
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 15),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: isActive ? Colors.red : Colors.white10,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(displayName, style: TextStyle(color: isActive ? Colors.white : Colors.white70, fontSize: screenHeight * 0.016)),
                        ),
                      ),
                    );
                  },
                ),
              ),
            
            SizedBox(height: screenHeight * 0.015),
            
            // 选集列表区域 - 唯一可滚动区域
            Expanded(
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: List.generate(
                    (_sources[_currentSourceIndex]['episodes'] as List).length,
                    (index) {
                      final episode = _sources[_currentSourceIndex]['episodes'][index];
                      return TVFocusable(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => VideoPage(
                              videoId: widget.videoId,
                              initialSourceIndex: _currentSourceIndex,
                              initialEpisodeIndex: index,
                            )),
                          );
                        },
                        borderRadius: 8, // 指定圆角
                        child: Container(
                          constraints: BoxConstraints(minWidth: screenHeight * 0.1),
                          padding: EdgeInsets.symmetric(horizontal: screenHeight * 0.02, vertical: screenHeight * 0.01),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: Text(
                            episode['name'],
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white, fontSize: screenHeight * 0.016),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoTag(String text) {
    final screenHeight = MediaQuery.of(context).size.height;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: screenHeight * 0.004),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.red.withOpacity(0.5)),
      ),
      child: Text(text, style: TextStyle(color: Colors.red, fontSize: screenHeight * 0.014, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    final screenHeight = MediaQuery.of(context).size.height;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: Colors.grey, fontSize: screenHeight * 0.018)),
        Expanded(child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white70, fontSize: screenHeight * 0.018))),
      ],
    );
  }
}
