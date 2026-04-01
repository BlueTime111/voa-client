/// 简易日志工具，统一输出格式，便于排查问题。
import 'package:flutter/foundation.dart';

class AppLogger {
  static void info(String message) {
    debugPrint('[INFO] $message');
  }

  static void warn(String message) {
    debugPrint('[WARN] $message');
  }

  static void error(String message, [Object? error, StackTrace? stackTrace]) {
    debugPrint('[ERROR] $message');
    if (error != null) {
      debugPrint('         error: $error');
    }
    if (stackTrace != null) {
      debugPrint('         stack: $stackTrace');
    }
  }
}
