import 'constants.dart';

String deriveVoiceUrlFromAgentUrl(String agentUrl) {
  final fallback = AppConstants.defaultCustomWebSocketUrl
      .replaceFirst(RegExp(r'/agent/?$'), '/voice');
  final trimmed = agentUrl.trim();
  if (trimmed.isEmpty) {
    return fallback;
  }

  try {
    final uri = Uri.parse(trimmed);
    final path = uri.path;

    String voicePath;
    if (path.endsWith('/agent')) {
      voicePath = '${path.substring(0, path.length - '/agent'.length)}/voice';
    } else if (path.endsWith('/agent/')) {
      voicePath = '${path.substring(0, path.length - '/agent/'.length)}/voice';
    } else if (path.endsWith('/voice')) {
      voicePath = path;
    } else if (path.endsWith('/voice/')) {
      voicePath = path.substring(0, path.length - 1);
    } else if (path.isEmpty || path == '/') {
      voicePath = '/voice';
    } else {
      voicePath = path.endsWith('/') ? '${path}voice' : '$path/voice';
    }

    return uri.replace(path: voicePath).toString();
  } catch (_) {
    if (trimmed.endsWith('/agent')) {
      return '${trimmed.substring(0, trimmed.length - '/agent'.length)}/voice';
    }
    if (trimmed.endsWith('/agent/')) {
      return '${trimmed.substring(0, trimmed.length - '/agent/'.length)}/voice';
    }
    if (trimmed.endsWith('/voice')) {
      return trimmed;
    }
    if (trimmed.endsWith('/voice/')) {
      return trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed.endsWith('/') ? '${trimmed}voice' : '$trimmed/voice';
  }
}
