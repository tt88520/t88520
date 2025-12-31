import 'dart:async';
import 'package:flutter/material.dart';
import 'package:new_tv/common/api.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:new_tv/pages/video_page.dart';
import 'package:new_tv/pages/detail_page.dart';
import 'package:new_tv/pages/search_page.dart';
import 'package:new_tv/pages/history_page.dart';
import 'package:new_tv/widgets/tv_focusable.dart';
import 'package:new_tv/common/update_util.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentMenuIndex = 0;
  List<dynamic> _menus = [
    {'type_name': '首页', 'type_id': 0, 'icon': Icons.home}
  ];
  List<dynamic> _allCategories = []; // 保存原始分类列表
  List<dynamic> _videoList = [];
  Map<String, List<dynamic>> _homeRows = {};
  dynamic _featuredVideo;
  bool _isLoading = true;
  bool _isTimeout = false; // 是否连接超时
  Timer? _initTimer; // 初始化计时器
  
  Map<String, dynamic> _appInfo = {
    'name': '唐人街影院',
    'version': '1.0.0',
    'site': '',
  };
  
  // 分页与筛选
  int _currentPage = 1;
  int _totalPages = 1;
  String _year = '';
  String _area = '';
  String _order = 'time';
  dynamic _subTypeId; // 选中的子分类 ID
  
  Map<String, dynamic> _filterOptions = {
    'year': [],
    'area': [],
    'order': [
      {'name': '按时间', 'value': 'time'},
      {'name': '按热度', 'value': 'hits'}
    ]
  };

  @override
  void initState() {
    super.initState();
    _initData();
  }

  @override
  void dispose() {
    _initTimer?.cancel();
    super.dispose();
  }

  Future<void> _initData() async {
    _initTimer?.cancel();
    setState(() {
      _isLoading = true;
      _isTimeout = false;
      _menus = [
        {'type_name': '首页', 'type_id': 0, 'icon': Icons.home}
      ];
    });

    // 启动 20 秒超时监控
    _initTimer = Timer(const Duration(seconds: 20), () {
      if (mounted && _isLoading) {
        setState(() {
          _isLoading = false;
          _isTimeout = true;
        });
        print('Home Page: API Connection Timeout (20s)');
      }
    });

    print('Home Page: Initializing data...');
    
    try {
      // 并行获取配置和分类
      await Future.wait([
        _loadConfig(),
        _loadCategories(),
      ]);

      // 只要拿到了菜单数据，就认为连接成功
      if (_menus.length > 1) {
        _initTimer?.cancel();
        setState(() => _isTimeout = false);
        await _fetchContent();
      } else {
        throw Exception("API Data Empty");
      }
      
      if (mounted) {
        UpdateUtil.checkUpdate(context);
      }
    } catch (e) {
      print('Home Page Init Error: $e');
      if (!_isTimeout) {
        _initTimer?.cancel();
        setState(() {
          _isLoading = false;
          _isTimeout = true;
        });
      }
    } finally {
      if (!_isTimeout) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadConfig() async {
    try {
      final config = await Api.getConfig();
      if (config.containsKey('data') && config['data'] != null) {
        setState(() {
          final data = config['data'];
          
          if (data['area'] != null) {
            if (data['area'] is List) {
              _filterOptions['area'] = data['area'];
            } else if (data['area'] is String && data['area'].toString().isNotEmpty) {
              _filterOptions['area'] = data['area'].toString().split(',');
            }
          }
          
          _appInfo['name'] = data['app_name'] ?? _appInfo['name'];
          _appInfo['version'] = data['app_version'] ?? _appInfo['version'];
          _appInfo['site'] = data['app_site_url'] ?? _appInfo['site'];
        });
      }
    } catch (e) {
      print('Load Config Error: $e');
    }
    
    setState(() {
      final int currentYear = DateTime.now().year;
      _filterOptions['year'] = [
        {'name': '今年', 'value': currentYear.toString()},
        {'name': '去年', 'value': (currentYear - 1).toString()},
        {'name': '2023', 'value': '2023'},
        {'name': '2022', 'value': '2022'},
        {'name': '90年代', 'value': '199'},
        {'name': '80年代', 'value': '198'},
        {'name': '70年代', 'value': '197'},
        {'name': '更早', 'value': 'older'},
      ];

      if (_filterOptions['area'] == null || (_filterOptions['area'] as List).isEmpty) {
        _filterOptions['area'] = ['大陆', '香港', '台湾', '美国', '韩国', '日本', '泰国', '英国', '法国', '德国'];
      }
    });
  }

  Future<void> _loadCategories() async {
    try {
      final cats = await Api.getCategories();
      if (cats.isNotEmpty) {
        setState(() {
          _allCategories = cats;
          final List<dynamic> menuList = [
            {'type_name': '首页', 'type_id': 0, 'icon': Icons.home},
          ];
          
          for (var c in cats) {
            final pid = c['type_pid']?.toString();
            if (pid == '0' || pid == null || pid == '') {
              IconData icon = Icons.movie;
              final name = c['type_name']?.toString() ?? '';
              if (name.contains('剧')) icon = Icons.tv;
              if (name.contains('动')) icon = Icons.palette;
              if (name.contains('综')) icon = Icons.airplane_ticket;
              menuList.add({...c, 'icon': icon});
            }
          }
          menuList.add({'type_name': '搜索', 'type_id': -2, 'icon': Icons.search});
          menuList.add({'type_name': '历史', 'type_id': -3, 'icon': Icons.history});
          menuList.add({'type_name': '关于', 'type_id': -1, 'icon': Icons.info_outline});
          _menus = menuList;
        });
      }
    } catch (e) {
      print('Load Categories Error: $e');
    }
  }

  Future<void> _fetchContent() async {
    final menu = _menus[_currentMenuIndex];
    if (menu['type_id'] == -1 || menu['type_id'] == -2) return; 

    setState(() {
      _isLoading = true;
      if (_currentPage == 1) {
        _videoList = [];
        _homeRows = {};
      }
    });
    
    final dynamic rawTypeId = _subTypeId ?? menu['type_id'];
    int? typeId;
    if (rawTypeId != null && rawTypeId != 0) {
      typeId = int.tryParse(rawTypeId.toString());
    }
    
    try {
      if (_currentMenuIndex == 0) {
        final Map<String, List<dynamic>> rows = {};
        final featuredRes = await Api.getVideoList(level: 9, num: 1);
        if (featuredRes.containsKey('list') && (featuredRes['list'] as List).isNotEmpty) {
          setState(() => _featuredVideo = featuredRes['list'][0]);
        }

        final hotRes = await Api.getVideoList(num: 12);
        if (hotRes.containsKey('list') && (hotRes['list'] as List).isNotEmpty) {
          rows['正在热播'] = hotRes['list'];
          if (_featuredVideo == null) {
            setState(() => _featuredVideo = hotRes['list'][0]);
          }
        }

        for (var m in _menus) {
          final tid = int.tryParse(m['type_id'].toString()) ?? 0;
          if (tid > 0) {
            final catRes = await Api.getVideoList(typeId: tid, num: 12);
            if (catRes.containsKey('list') && (catRes['list'] as List).isNotEmpty) {
              rows['最新${m['type_name']}'] = catRes['list'];
            }
          }
        }

        setState(() {
          _homeRows = rows;
        });
      } else {
        final res = await Api.getVideoList(
          typeId: typeId,
          page: _currentPage,
          year: _year,
          area: _area,
          order: _order,
        );

        if (res.containsKey('list') && res['list'] is List) {
          final list = res['list'] as List;
          setState(() {
            _videoList = list;
            _totalPages = int.tryParse(res['pagecount']?.toString() ?? '1') ?? 1;
            if (list.isNotEmpty) _featuredVideo = list[0];
          });
        }
      }
    } catch (e) {
      print('Home Page Fetch Content Error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          _buildSidebar(),
          Expanded(child: _buildMainContent()),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 130,
      color: const Color(0xFF151515),
      child: Column(
        children: [
          const SizedBox(height: 30),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: Column(
              children: [
                Image.asset(
                  'assets/images/logo.png', 
                  width: 110,
                  fit: BoxFit.contain, 
                  errorBuilder: (c, e, s) => const Text('M', style: TextStyle(color: Colors.red, fontSize: 24, fontWeight: FontWeight.bold))
                ),
                const Text('v1.9 - New Layout', style: TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const SizedBox(height: 30),
          Expanded(
            child: ListView.builder(
              itemCount: _menus.length,
              clipBehavior: Clip.none,
              itemBuilder: (context, index) {
                final menu = _menus[index];
                final isActive = _currentMenuIndex == index;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
                  child: TVFocusable(
                    onTap: () {
                      if (menu['type_id'] == -2) {
                        Navigator.push(context, MaterialPageRoute(builder: (context) => const SearchPage()));
                        return;
                      }
                      if (menu['type_id'] == -3) {
                        Navigator.push(context, MaterialPageRoute(builder: (context) => const HistoryPage()));
                        return;
                      }
                      if (_currentMenuIndex == index) return;
                      setState(() {
                        _currentMenuIndex = index;
                        _currentPage = 1;
                        _year = '';
                        _area = '';
                        _subTypeId = null;
                      });
                      _fetchContent();
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: isActive ? Colors.red.withOpacity(0.1) : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        children: [
                          Icon(menu['icon'] ?? Icons.movie, color: isActive ? Colors.red : Colors.grey, size: 24),
                          const SizedBox(height: 5),
                          Text(
                            menu['type_name'] ?? '',
                            style: TextStyle(
                              color: isActive ? Colors.white : Colors.grey,
                              fontSize: 13,
                              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
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

  Widget _buildMainContent() {
    final menu = _menus[_currentMenuIndex];
    if (menu['type_id'] == -1) return _buildAboutPage();

    if (_isTimeout) return _buildErrorUI();

    bool showSkeleton = _isLoading && _homeRows.isEmpty && _videoList.isEmpty && _currentMenuIndex == 0;

    if (showSkeleton) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SpinKitFadingCube(color: Colors.red, size: 50),
            const SizedBox(height: 20),
            Text('正在尝试连接服务器...', style: TextStyle(color: Colors.white70)),
          ],
        ),
      );
    }

    return Stack(
      children: [
        if (_featuredVideo != null) _buildHeroBackground(),
        _buildContentScroll(),
        if (_isLoading && _videoList.isEmpty && _currentMenuIndex != 0)
          const Center(child: SpinKitFadingCube(color: Colors.red, size: 50)),
        if (_isLoading && (_videoList.isNotEmpty || _homeRows.isNotEmpty))
          const Positioned(
            top: 20,
            right: 20,
            child: SpinKitRing(color: Colors.red, size: 30, lineWidth: 3),
          ),
      ],
    );
  }

  Widget _buildErrorUI() {
    return Container(
      width: double.infinity,
      color: Colors.black,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.cloud_off, size: 80, color: Colors.white24),
          const SizedBox(height: 20),
          const Text('网络连接困难', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          const Text('连接 API 服务器超时，请检查您的网络设置', style: TextStyle(color: Colors.white54, fontSize: 16)),
          const SizedBox(height: 40),
          TVFocusable(
            onTap: _initData,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(color: Colors.red.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 5))
                ],
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.refresh, color: Colors.white),
                  SizedBox(width: 10),
                  Text('立即重试', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAboutPage() {
    return Container(
      color: Colors.black,
      width: double.infinity,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset(
            'assets/images/logo.png', 
            width: 400,
            fit: BoxFit.contain,
            errorBuilder: (c, e, s) => Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Center(child: Text('M', style: TextStyle(color: Colors.white, fontSize: 80, fontWeight: FontWeight.bold))),
            ),
          ),
          const SizedBox(height: 40),
          Text(_appInfo['name'], style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Text('版本号：v${_appInfo['version']}', style: const TextStyle(color: Colors.grey, fontSize: 18)),
          const SizedBox(height: 40),
          if (_appInfo['site'].toString().isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                children: [
                  const Text('官方网址', style: TextStyle(color: Colors.grey, fontSize: 14)),
                  const SizedBox(height: 5),
                  Text(_appInfo['site'], style: const TextStyle(color: Colors.red, fontSize: 24, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          const SizedBox(height: 60),
          const Text('© 2025 Tangrenjie Entertainment. All rights reserved.', style: TextStyle(color: Colors.white24, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildHeroBackground() {
    return Positioned.fill(
      child: Opacity(
        opacity: 0.4,
        child: CachedNetworkImage(
          imageUrl: _featuredVideo['vod_pic'] ?? '',
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
          placeholder: (context, url) => Container(color: Colors.black),
          errorWidget: (context, url, error) => Container(color: Colors.black),
        ),
      ),
    );
  }

  Widget _buildContentScroll() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Colors.black, Colors.black.withOpacity(0.8), Colors.transparent],
        ),
      ),
      child: CustomScrollView(
        clipBehavior: Clip.none,
        slivers: [
          if (_currentMenuIndex == 0) ...[
            SliverToBoxAdapter(child: _buildHeroInfo()),
            ..._buildHomeRows(),
          ] else ...[
            SliverToBoxAdapter(child: const SizedBox(height: 40)),
            SliverToBoxAdapter(child: _buildFilterSection()),
            _buildCategoryList(),
            SliverToBoxAdapter(child: _buildPagination()),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 50)),
        ],
      ),
    );
  }

  Widget _buildHeroInfo() {
    if (_featuredVideo == null) return const SizedBox(height: 300);
    return Container(
      padding: const EdgeInsets.fromLTRB(30, 80, 30, 40),
      height: MediaQuery.of(context).size.height * 0.7,
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            _featuredVideo['vod_name'] ?? '加载中...',
            style: const TextStyle(fontSize: 60, fontWeight: FontWeight.w900, color: Colors.white),
          ),
          const SizedBox(height: 15),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: Colors.amber, borderRadius: BorderRadius.circular(4)),
                child: Text(_featuredVideo['vod_score'] ?? '8.0', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 15),
              Text('${_featuredVideo['vod_year'] ?? ''} | ${_featuredVideo['vod_area'] ?? ''} | ${_featuredVideo['vod_remarks'] ?? ''}', style: const TextStyle(fontSize: 18)),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: 600,
            child: Text(
              _featuredVideo['vod_content']?.replaceAll(RegExp(r'<[^>]*>'), '') ?? '正在获取内容详情...',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, color: Colors.white70, height: 1.5),
            ),
          ),
          const SizedBox(height: 30),
          Wrap(
            spacing: 20,
            runSpacing: 20,
            children: [
              TVFocusable(
                onTap: () => _toDetail(_featuredVideo['vod_id']),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.play_arrow, color: Colors.black, size: 30),
                      SizedBox(width: 8),
                      Text('立即播放', style: TextStyle(color: Colors.black, fontSize: 20, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
              TVFocusable(
                onTap: () {},
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.info_outline, color: Colors.white),
                      SizedBox(width: 8),
                      Text('详情介绍', style: TextStyle(color: Colors.white)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _buildHomeRows() {
    return _homeRows.entries.map((entry) {
      return SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(30, 30, 0, 15),
              child: Text(entry.key, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            ),
            SizedBox(
              height: 220,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: entry.value.length,
                itemBuilder: (context, index) {
                  return _buildVideoCard(entry.value[index]);
                },
              ),
            ),
          ],
        ),
      );
    }).toList();
  }

  Widget _buildCategoryList() {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 20),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 220,
          childAspectRatio: 0.58,
          crossAxisSpacing: 20,
          mainAxisSpacing: 25,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) => _buildVideoCard(_videoList[index], isLarge: true),
          childCount: _videoList.length,
        ),
      ),
    );
  }

  Widget _buildVideoCard(dynamic video, {bool isLarge = false}) {
    final double? cardWidth = isLarge ? null : 280.0;
    return Container(
      width: cardWidth,
      margin: isLarge ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 10),
      child: TVFocusable(
        onTap: () => _toDetail(video['vod_id']),
        scale: 1.1,
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.grey[900],
                  borderRadius: BorderRadius.circular(8),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: CachedNetworkImage(
                        imageUrl: video['vod_pic'] ?? '',
                        fit: BoxFit.cover,
                        placeholder: (context, url) => const Center(child: SpinKitPulse(color: Colors.red, size: 30)),
                        errorWidget: (context, url, error) => const Icon(Icons.image_not_supported, color: Colors.grey),
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [Colors.black.withOpacity(0.9), Colors.transparent],
                          ),
                        ),
                        child: Text(
                          video['vod_remarks'] ?? '',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.amber),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(5, 12, 5, 5),
              child: Column(
                children: [
                  Text(
                    video['vod_name'] ?? '',
                    maxLines: 1,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: isLarge ? 14 : 12, color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    (video['vod_actor'] ?? '').toString().replaceAll(',', ' / '),
                    maxLines: 1,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: isLarge ? 12 : 10, color: Colors.white54),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterSection() {
    if (_menus.isEmpty || _currentMenuIndex >= _menus.length) return const SizedBox();
    
    final menu = _menus[_currentMenuIndex];
    final parentId = menu['type_id']?.toString() ?? '';
    final subCats = _allCategories.where((c) {
      final pid = c['type_pid']?.toString();
      final cid = c['type_id']?.toString();
      return pid != null && pid != '0' && pid != '' && pid == parentId && cid != parentId;
    }).toList();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.02),
        borderRadius: BorderRadius.circular(10),
      ),
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (subCats.isNotEmpty)
            _buildFilterRow('类型', subCats, _subTypeId?.toString() ?? '', (v) {
              setState(() {
                _subTypeId = v == '' ? null : v;
                _currentPage = 1;
                _fetchContent();
              });
            }, isCategory: true),
          if (_filterOptions['year'] != null && (_filterOptions['year'] as List).isNotEmpty)
            _buildFilterRow('年份', _filterOptions['year'], _year, (v) => setState(() { _year = v; _currentPage = 1; _fetchContent(); }), isMap: true),
          if (_filterOptions['area'] != null && (_filterOptions['area'] as List).isNotEmpty)
            _buildFilterRow('地区', _filterOptions['area'], _area, (v) => setState(() { _area = v; _currentPage = 1; _fetchContent(); })),
          _buildFilterRow('排序', _filterOptions['order'], _order, (v) => setState(() { _order = v; _currentPage = 1; _fetchContent(); }), isMap: true),
        ],
      ),
    );
  }

  Widget _buildFilterRow(String label, List<dynamic> items, String current, Function(String) onSelect, {bool isMap = false, bool isCategory = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Text('$label：', style: const TextStyle(color: Colors.grey, fontSize: 14)),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFilterItem('全部', current == '', () => onSelect('')),
                  ...items.map((item) {
                    String name;
                    String value;
                    try {
                      if (isMap && item is Map) {
                        name = item['name']?.toString() ?? '';
                        value = item['value']?.toString() ?? '';
                      } else if (isCategory && item is Map) {
                        name = item['type_name']?.toString() ?? '';
                        value = item['type_id']?.toString() ?? '';
                      } else {
                        name = item.toString();
                        value = item.toString();
                      }
                    } catch (e) {
                      name = item.toString();
                      value = item.toString();
                    }
                    if (name.isEmpty) return const SizedBox();
                    return _buildFilterItem(name, current == value, () => onSelect(value));
                  }),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterItem(String name, bool isActive, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: TVFocusable(
        onTap: onTap,
        scale: 1.05,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isActive ? Colors.red : Colors.grey.withOpacity(0.2),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Text(name, style: TextStyle(color: isActive ? Colors.white : Colors.white70, fontSize: 13)),
        ),
      ),
    );
  }

  Widget _buildPagination() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildPageBtn('上一页', _currentPage > 1, () {
            if (_currentPage > 1) {
              setState(() => _currentPage--);
              _fetchContent();
            }
          }),
          const SizedBox(width: 20),
          Text('第 $_currentPage / $_totalPages 页', style: const TextStyle(fontSize: 18, color: Colors.grey)),
          const SizedBox(width: 20),
          _buildPageBtn('下一页', _currentPage < _totalPages, () {
            if (_currentPage < _totalPages) {
              setState(() => _currentPage++);
              _fetchContent();
            }
          }),
        ],
      ),
    );
  }

  Widget _buildPageBtn(String text, bool enabled, VoidCallback onTap) {
    return TVFocusable(
      onTap: enabled ? onTap : () {},
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 12),
        decoration: BoxDecoration(
          color: enabled ? Colors.white.withOpacity(0.1) : Colors.transparent,
          border: Border.all(color: enabled ? Colors.white30 : Colors.white10),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(text, style: TextStyle(color: enabled ? Colors.white : Colors.grey)),
      ),
    );
  }

  void _toDetail(dynamic id) {
    if (id == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => DetailPage(videoId: id.toString())),
    );
  }
}
