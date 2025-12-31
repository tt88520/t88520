import 'dart:convert';
import 'package:dio/dio.dart';

class Api {
  static const String baseUrl = 'https://tangrenjie.net/api.php/provide/vod';
  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ));

  static Future<Map<String, dynamic>> get(String ac, {Map<String, dynamic>? params}) async {
    try {
      final Map<String, dynamic> queryParams = {
        'ac': ac, 
        'at': 'json',
        't_rnd': DateTime.now().millisecondsSinceEpoch.toString()
      };
      if (params != null) {
        queryParams.addAll(params);
      }
      print('Requesting API: $ac');
      
      final response = await _dio.get(baseUrl, queryParameters: queryParams);
      
      if (response.statusCode == 200) {
        var data = response.data;
        // 核心修复：处理 Dio 可能没自动解析字符串的情况
        if (data is String) {
          try {
            data = jsonDecode(data);
          } catch (e) {
            print('JSON Decode Error: $e');
            return {};
          }
        }
        
        if (data is Map) {
          return Map<String, dynamic>.from(data);
        }
      }
      return {};
    } catch (e) {
      print('Network Error ($ac): $e');
      return {};
    }
  }

  // 获取分类
  static Future<List<dynamic>> getCategories() async {
    final res = await get('list');
    if (res.containsKey('class')) {
      final classData = res['class'];
      if (classData is List) return classData;
      if (classData is Map) return classData.values.toList();
    }
    return [];
  }

  // 获取视频列表
  static Future<Map<String, dynamic>> getVideoList({
    dynamic typeId, // 改为 dynamic，增强兼容性
    int page = 1,
    int? level, // 新增 level 支持
    String? year,
    String? area,
    String? lang,
    String? order,
    String? wd,
    int num = 25, // 允许自定义数量
  }) async {
    final Map<String, dynamic> params = {
      'pg': page,
      'num': num,
      'pagesize': num,
    };
    
    if (level != null) params['level'] = level;
    
    // 安全转换 typeId 为整数
    if (typeId != null) {
      final int? t = int.tryParse(typeId.toString());
      if (t != null && t > 0) {
        params['t'] = t;
      }
    }
    
    // 处理年份和年代逻辑
    if (year != null && year.isNotEmpty) {
      if (year == 'older') {
        // “更早”通常指 2000 年以前，或者接口支持的具体范围
        params['year'] = '1900-2000'; 
      } else if (year.length == 3 && (year.startsWith('19') || year.startsWith('20'))) {
        // 如果是 3 位数（如 199），则代表 90 年代
        // 尝试将其转换为 1990-1999 这种范围格式，这是许多 MacCMS 增强版接口支持的
        params['year'] = '${year}0-${year}9';
      } else {
        params['year'] = year;
      }
    }

    if (area != null && area.isNotEmpty) params['area'] = area;
    if (lang != null && lang.isNotEmpty) params['lang'] = lang;
    if (order != null && order.isNotEmpty) params['by'] = order;
    if (wd != null && wd.isNotEmpty) params['wd'] = wd;

    return await get('videolist', params: params);
  }

  // 获取配置
  static Future<Map<String, dynamic>> getConfig() async {
    return await get('config');
  }

  // 获取详情
  static Future<Map<String, dynamic>> getDetail(String ids) async {
    final res = await get('detail', params: {'ids': ids});
    if (res.containsKey('list') && (res['list'] as List).isNotEmpty) {
      return res['list'][0];
    }
    return {};
  }
}
