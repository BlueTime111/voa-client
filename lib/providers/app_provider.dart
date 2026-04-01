/// 全局应用状态：配置项与历史记录的读取、更新和持久化。
import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_config.dart';
import '../models/conversation_message.dart';
import '../utils/constants.dart';
import '../utils/logger.dart';

class AppProvider extends ChangeNotifier {
  AppConfig _config = AppConfig.initial();
  List<ConversationMessage> _history = <ConversationMessage>[];

  bool _isLoading = false;
  bool _isLoaded = false;
  Completer<void>? _loadCompleter;

  AppConfig get config => _config;
  List<ConversationMessage> get history =>
      List<ConversationMessage>.unmodifiable(_history);
  bool get isLoading => _isLoading;
  bool get isLoaded => _isLoaded;

  /// 从本地存储加载配置和历史记录。
  Future<void> load() async {
    if (_isLoaded) {
      return;
    }

    if (_isLoading) {
      await _loadCompleter?.future;
      return;
    }

    _isLoading = true;
    final completer = Completer<void>();
    _loadCompleter = completer;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await _loadConfig(prefs);
      await _loadHistory(prefs);
      _isLoaded = true;
      AppLogger.info('AppProvider loaded from local storage.');
    } catch (error, stackTrace) {
      AppLogger.error('Failed to load app data.', error, stackTrace);
    } finally {
      _isLoading = false;
      if (!completer.isCompleted) {
        completer.complete();
      }
      if (identical(_loadCompleter, completer)) {
        _loadCompleter = null;
      }
      notifyListeners();
    }
  }

  /// 更新 WebSocket 地址。
  Future<void> updateWebSocketUrl(String value) async {
    final fallback =
        _config.communicationMode == CommunicationMode.geminiWebSocket
            ? AppConstants.defaultGeminiWebSocketUrl
            : AppConstants.defaultCustomWebSocketUrl;
    final normalized = value.trim().isEmpty ? fallback : value.trim();
    _config = _config.copyWith(webSocketUrl: normalized);
    await _saveConfig();
    notifyListeners();
  }

  /// 更新通信模式。
  Future<void> updateCommunicationMode(CommunicationMode mode) async {
    _config = _config.copyWith(communicationMode: mode);
    await _saveConfig();
    notifyListeners();
  }

  /// 更新 Gemini WebSocket 地址。
  Future<void> updateGeminiWebSocketUrl(String value) async {
    final normalized = value.trim().isEmpty
        ? AppConstants.defaultGeminiWebSocketUrl
        : value.trim();
    _config = _config.copyWith(geminiWebSocketUrl: normalized);
    await _saveConfig();
    notifyListeners();
  }

  /// 更新自定义 WebSocket 地址。
  Future<void> updateCustomWebSocketUrl(String value) async {
    final normalized = value.trim().isEmpty
        ? AppConstants.defaultCustomWebSocketUrl
        : value.trim();
    _config = _config.copyWith(customWebSocketUrl: normalized);
    await _saveConfig();
    notifyListeners();
  }

  /// 更新音频质量。
  Future<void> updateAudioQuality(AudioQuality quality) async {
    _config = _config.copyWith(audioQuality: quality);
    await _saveConfig();
    notifyListeners();
  }

  /// 更新自动发送延迟。
  Future<void> updateAutoSendDelay(Duration delay) async {
    _config = _config.copyWith(autoSendDelay: delay);
    await _saveConfig();
    notifyListeners();
  }

  /// 更新主题模式。
  Future<void> updateThemeMode(ThemeMode mode) async {
    _config = _config.copyWith(themeMode: mode);
    await _saveConfig();
    notifyListeners();
  }

  /// 添加一条输入文本历史记录。
  Future<void> addHistoryText(String text) async {
    final normalized = text.trim();
    if (normalized.isEmpty) {
      return;
    }

    final message = ConversationMessage(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      text: normalized,
      createdAt: DateTime.now(),
    );

    _history = <ConversationMessage>[message, ..._history];
    await _saveHistory();
    notifyListeners();
  }

  /// 删除单条历史记录。
  Future<void> removeConversation(String id) async {
    _history = _history.where((item) => item.id != id).toList(growable: false);
    await _saveHistory();
    notifyListeners();
  }

  /// 清空历史记录。
  Future<void> clearHistory() async {
    _history = <ConversationMessage>[];
    await _saveHistory();
    notifyListeners();
  }

  Future<void> _loadConfig(SharedPreferences prefs) async {
    final raw = prefs.getString(AppConstants.prefsConfigKey);
    if (raw == null || raw.isEmpty) {
      _config = AppConfig.initial();
      return;
    }

    final jsonMap = jsonDecode(raw) as Map<String, dynamic>;
    _config = AppConfig.fromJson(jsonMap);
  }

  Future<void> _loadHistory(SharedPreferences prefs) async {
    final raw = prefs.getString(AppConstants.prefsHistoryKey);
    if (raw == null || raw.isEmpty) {
      _history = <ConversationMessage>[];
      return;
    }

    final decoded = jsonDecode(raw) as List<dynamic>;
    _history = decoded
        .map((item) {
          if (item is Map<String, dynamic>) {
            return ConversationMessage.fromJson(item);
          }
          if (item is Map) {
            final converted = item.map(
              (key, value) => MapEntry(key.toString(), value),
            );
            return ConversationMessage.fromJson(converted);
          }
          return null;
        })
        .whereType<ConversationMessage>()
        .toList(growable: false)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<void> _saveConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          AppConstants.prefsConfigKey, jsonEncode(_config.toJson()));
    } catch (error, stackTrace) {
      AppLogger.error('Failed to save config.', error, stackTrace);
    }
  }

  Future<void> _saveHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw =
          _history.map((message) => message.toJson()).toList(growable: false);
      await prefs.setString(AppConstants.prefsHistoryKey, jsonEncode(raw));
    } catch (error, stackTrace) {
      AppLogger.error('Failed to save history.', error, stackTrace);
    }
  }
}
