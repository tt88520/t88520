import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:new_tv/common/api.dart';
import 'package:new_tv/widgets/tv_focusable.dart';

class UpdateUtil {
  static Future<void> checkUpdate(BuildContext context) async {
    // Web 环境不支持自动化更新
    if (kIsWeb) return;

    try {
      final config = await Api.getConfig();
      if (!config.containsKey('data')) return;
      
      final remoteVersion = config['data']['app_version']?.toString() ?? '';
      final updateDesc = config['data']['app_update_desc']?.toString() ?? '发现新版本，请更新体验更多功能。';
      
      // 根据平台获取对应的下载地址
      String downloadUrl = '';
      if (Platform.isAndroid) {
        // 优先尝试 TV 版下载地址，如果没有则使用普通安卓地址
        downloadUrl = config['data']['app_download_tv']?.toString() ?? '';
        if (downloadUrl.isEmpty) {
          downloadUrl = config['data']['app_download_android']?.toString() ?? '';
        }
      } else if (Platform.isMacOS) {
        downloadUrl = config['data']['app_download_mac']?.toString() ?? '';
      } else if (Platform.isWindows) {
        downloadUrl = config['data']['app_download_pc']?.toString() ?? '';
      } else if (Platform.isIOS) {
        downloadUrl = config['data']['app_download_ios']?.toString() ?? '';
      }

      // 如果没有配置下载地址，使用通用下载地址作为兜底
      if (downloadUrl.isEmpty) {
        downloadUrl = config['data']['app_download_url']?.toString() ?? '';
      }

      if (remoteVersion.isEmpty || downloadUrl.isEmpty) return;

      final packageInfo = await PackageInfo.fromPlatform();
      final localVersion = packageInfo.version;

      if (_isNewer(remoteVersion, localVersion)) {
        if (context.mounted) {
          _showUpdateDialog(context, remoteVersion, downloadUrl, updateDesc);
        }
      }
    } catch (e) {
      print('Check update error: $e');
    }
  }

  static bool _isNewer(String remote, String local) {
    List<int> r = remote.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    List<int> l = local.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    
    for (int i = 0; i < r.length && i < l.length; i++) {
      if (r[i] > l[i]) return true;
      if (r[i] < l[i]) return false;
    }
    return r.length > l.length;
  }

  static void _showUpdateDialog(BuildContext context, String version, String url, String desc) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _UpdateDialog(version: version, url: url, desc: desc),
    );
  }
}

class _UpdateDialog extends StatefulWidget {
  final String version;
  final String url;
  final String desc;

  const _UpdateDialog({required this.version, required this.url, required this.desc});

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  double _progress = 0;
  bool _isDownloading = false;
  bool _isDownloaded = false;
  String _statusText = '立即更新';
  String _savedPath = '';

  Future<void> _startDownload() async {
    if (_isDownloading && !_isDownloaded) return;
    
    // 如果已经下载完成，点击则再次尝试安装 (仅限安卓)
    if (_isDownloaded && _savedPath.isNotEmpty && Platform.isAndroid) {
      await OpenFilex.open(_savedPath);
      return;
    }

    // 非安卓平台 (Mac, Windows, iOS) 采用浏览器打开下载链接
    if (!Platform.isAndroid) {
      final Uri url = Uri.parse(widget.url);
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('无法打开下载链接')));
        }
      }
      return;
    }

    setState(() {
      _isDownloading = true;
      _statusText = '正在下载...';
    });

    try {
      final directory = await getExternalStorageDirectory();
      final path = "${directory!.path}/new_tv_update.apk";
      _savedPath = path;
      
      final dio = Dio();
      await dio.download(
        widget.url,
        path,
        onReceiveProgress: (count, total) {
          if (total > 0) {
            setState(() {
              _progress = count / total;
            });
          }
        },
      );

      setState(() {
        _isDownloaded = true;
        _statusText = '下载完成，点击安装';
      });

      await OpenFilex.open(path);
    } catch (e) {
      setState(() {
        _isDownloading = false;
        _statusText = '重试下载';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('下载失败: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Container(
        width: 450,
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('发现新版本 V${widget.version}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 20),
            Text(widget.desc, style: const TextStyle(color: Colors.white70, fontSize: 16)),
            const SizedBox(height: 30),
            if (_isDownloading && !_isDownloaded) ...[
              LinearProgressIndicator(
                value: _progress,
                backgroundColor: Colors.white10,
                color: Colors.red,
                minHeight: 8,
              ),
              const SizedBox(height: 10),
              Text('${(_progress * 100).toStringAsFixed(1)}%', style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 30),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (!_isDownloading)
                  TVFocusable(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      child: const Text('以后再说', style: TextStyle(color: Colors.grey)),
                    ),
                  ),
                const SizedBox(width: 20),
                TVFocusable(
                  onTap: _startDownload,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(_statusText, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}

