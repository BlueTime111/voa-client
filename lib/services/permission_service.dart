/// 权限服务：负责麦克风权限检查、申请和设置页跳转。
import 'package:permission_handler/permission_handler.dart';

enum MicrophonePermissionResult {
  granted,
  denied,
  permanentlyDenied,
}

class PermissionService {
  /// 确保麦克风权限可用，并返回最终状态。
  Future<MicrophonePermissionResult> ensureMicrophonePermission() async {
    final currentStatus = await Permission.microphone.status;

    if (currentStatus.isGranted) {
      return MicrophonePermissionResult.granted;
    }

    if (currentStatus.isPermanentlyDenied) {
      return MicrophonePermissionResult.permanentlyDenied;
    }

    final result = await Permission.microphone.request();

    if (result.isGranted) {
      return MicrophonePermissionResult.granted;
    }
    if (result.isPermanentlyDenied) {
      return MicrophonePermissionResult.permanentlyDenied;
    }

    return MicrophonePermissionResult.denied;
  }

  /// 打开系统设置页面，供用户手动授权。
  Future<bool> openSystemSettings() {
    return openAppSettings();
  }
}
