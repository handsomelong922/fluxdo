import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../services/network/exceptions/api_exception.dart';

/// 结构化错误信息（图标 + 标题 + 描述）
class ErrorInfo {
  final IconData icon;
  final String title;
  final String message;

  const ErrorInfo({
    required this.icon,
    required this.title,
    required this.message,
  });
}

/// 错误信息工具类
/// 将各种异常转换为用户友好的错误提示
class ErrorUtils {
  /// 获取结构化的错误信息（图标 + 标题 + 描述）
  static ErrorInfo getErrorInfo(Object? error) {
    if (error == null) {
      return const ErrorInfo(
        icon: Icons.error_outline_rounded,
        title: '加载失败',
        message: '未知错误',
      );
    }

    // 自定义异常
    if (error is RateLimitException) {
      return ErrorInfo(
        icon: Icons.speed_rounded,
        title: '请求过于频繁',
        message: error.toString(),
      );
    }
    if (error is ServerException) {
      return ErrorInfo(
        icon: Icons.cloud_off_rounded,
        title: '服务器不可用',
        message: error.toString(),
      );
    }
    if (error is CfChallengeException) {
      return ErrorInfo(
        icon: Icons.shield_rounded,
        title: '安全验证',
        message: error.toString(),
      );
    }

    // Dio 异常
    if (error is DioException) {
      // 检查内嵌的自定义异常（如 CfChallengeException 通过 handler.reject 包装）
      final innerError = error.error;
      if (innerError is CfChallengeException) {
        return ErrorInfo(
          icon: Icons.shield_rounded,
          title: '安全验证',
          message: innerError.toString(),
        );
      }
      if (innerError is RateLimitException) {
        return ErrorInfo(
          icon: Icons.speed_rounded,
          title: '请求过于频繁',
          message: innerError.toString(),
        );
      }
      if (innerError is ServerException) {
        return ErrorInfo(
          icon: Icons.cloud_off_rounded,
          title: '服务器不可用',
          message: innerError.toString(),
        );
      }
      return _handleDioException(error);
    }

    // 网络相关异常
    if (error is SocketException) {
      return const ErrorInfo(
        icon: Icons.signal_wifi_off_rounded,
        title: '网络不可用',
        message: '网络连接失败，请检查网络设置',
      );
    }
    if (error is TimeoutException) {
      return const ErrorInfo(
        icon: Icons.timer_off_rounded,
        title: '连接超时',
        message: '请求超时，请稍后重试',
      );
    }
    if (error is HttpException) {
      return const ErrorInfo(
        icon: Icons.public_off_rounded,
        title: '请求失败',
        message: '网络请求失败',
      );
    }
    if (error is FormatException) {
      return const ErrorInfo(
        icon: Icons.data_object_rounded,
        title: '数据异常',
        message: '服务器返回了无法识别的数据格式',
      );
    }

    // 通用 Exception
    if (error is Exception) {
      final message = error.toString();
      final cleaned = message.startsWith('Exception: ')
          ? message.substring(11)
          : message;
      return ErrorInfo(
        icon: Icons.error_outline_rounded,
        title: '加载失败',
        message: cleaned,
      );
    }

    return ErrorInfo(
      icon: Icons.error_outline_rounded,
      title: '加载失败',
      message: error.toString(),
    );
  }

  /// 获取用户友好的错误消息
  static String getFriendlyMessage(Object? error) {
    return getErrorInfo(error).message;
  }

  /// 获取完整的错误详情（用于调试）
  static String getErrorDetails(Object? error, [StackTrace? stackTrace]) {
    final buffer = StringBuffer();

    buffer.writeln('错误类型: ${error.runtimeType}');
    buffer.writeln('错误信息: $error');

    if (error is DioException) {
      buffer.writeln('');
      buffer.writeln('=== 请求详情 ===');
      buffer.writeln('URL: ${error.requestOptions.uri}');
      buffer.writeln('方法: ${error.requestOptions.method}');
      if (error.response != null) {
        buffer.writeln('状态码: ${error.response?.statusCode}');
        buffer.writeln('响应: ${error.response?.data}');
      }
    }

    if (stackTrace != null) {
      buffer.writeln('');
      buffer.writeln('=== 堆栈跟踪 ===');
      buffer.writeln(stackTrace.toString());
    }

    return buffer.toString();
  }

  static ErrorInfo _handleDioException(DioException error) {
    // 有 HTTP 响应的情况
    if (error.type == DioExceptionType.badResponse) {
      return _handleHttpStatus(error.response?.statusCode, error);
    }

    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
        return const ErrorInfo(
          icon: Icons.timer_off_rounded,
          title: '连接超时',
          message: '无法在规定时间内连接到服务器，请检查网络',
        );
      case DioExceptionType.receiveTimeout:
        return const ErrorInfo(
          icon: Icons.hourglass_disabled_rounded,
          title: '响应超时',
          message: '服务器响应时间过长，请稍后重试',
        );
      case DioExceptionType.connectionError:
        return const ErrorInfo(
          icon: Icons.signal_wifi_off_rounded,
          title: '网络不可用',
          message: '网络连接失败，请检查网络设置',
        );
      case DioExceptionType.badCertificate:
        return const ErrorInfo(
          icon: Icons.gpp_bad_rounded,
          title: '证书异常',
          message: '服务器证书验证失败，请检查网络环境',
        );
      case DioExceptionType.cancel:
        return const ErrorInfo(
          icon: Icons.cancel_outlined,
          title: '请求取消',
          message: '请求已取消',
        );
      default:
        // unknown 类型，检查内部 error
        if (error.error is SocketException) {
          return const ErrorInfo(
            icon: Icons.signal_wifi_off_rounded,
            title: '网络不可用',
            message: '网络连接失败，请检查网络设置',
          );
        }
        // 检查错误信息中的网络错误模式（如 Chromium/Cronet 的 net:: 错误）
        final errorStr = error.error?.toString().toUpperCase() ?? '';
        if (errorStr.contains('TIMED_OUT') ||
            errorStr.contains('TIMEOUT')) {
          return const ErrorInfo(
            icon: Icons.timer_off_rounded,
            title: '连接超时',
            message: '无法在规定时间内连接到服务器，请检查网络',
          );
        }
        if (errorStr.contains('CONNECTION_REFUSED') ||
            errorStr.contains('CONNECTION_RESET') ||
            errorStr.contains('CONNECTION_CLOSED') ||
            errorStr.contains('CONNECTION_FAILED') ||
            errorStr.contains('NAME_NOT_RESOLVED') ||
            errorStr.contains('ADDRESS_UNREACHABLE') ||
            errorStr.contains('INTERNET_DISCONNECTED') ||
            errorStr.contains('NETWORK_CHANGED')) {
          return const ErrorInfo(
            icon: Icons.signal_wifi_off_rounded,
            title: '网络不可用',
            message: '网络连接失败，请检查网络设置',
          );
        }
        if (errorStr.contains('SSL') ||
            errorStr.contains('CERT') ||
            errorStr.contains('CERTIFICATE')) {
          return const ErrorInfo(
            icon: Icons.gpp_bad_rounded,
            title: '证书异常',
            message: '服务器证书验证失败，请检查网络环境',
          );
        }
        // 尝试从响应中提取错误信息
        final data = error.response?.data;
        if (data is Map) {
          final errorMsg = data['error'] ?? data['message'];
          if (errorMsg is String && errorMsg.isNotEmpty) {
            return ErrorInfo(
              icon: Icons.error_outline_rounded,
              title: '请求失败',
              message: errorMsg,
            );
          }
          final errors = data['errors'];
          if (errors is List && errors.isNotEmpty) {
            return ErrorInfo(
              icon: Icons.error_outline_rounded,
              title: '请求失败',
              message: errors.first.toString(),
            );
          }
        }
        return const ErrorInfo(
          icon: Icons.public_off_rounded,
          title: '请求失败',
          message: '网络请求失败',
        );
    }
  }

  static ErrorInfo _handleHttpStatus(int? statusCode, DioException error) {
    // 先尝试从响应体提取服务器返回的具体错误信息
    String? serverMessage;
    final data = error.response?.data;
    if (data is Map) {
      final errorMsg = data['error'] ?? data['message'];
      if (errorMsg is String && errorMsg.isNotEmpty) {
        serverMessage = errorMsg;
      } else {
        final errors = data['errors'];
        if (errors is List && errors.isNotEmpty) {
          serverMessage = errors.first.toString();
        }
      }
    }

    switch (statusCode) {
      case 400:
        return ErrorInfo(
          icon: Icons.error_outline_rounded,
          title: '请求错误',
          message: serverMessage ?? '请求参数错误',
        );
      case 401:
        return ErrorInfo(
          icon: Icons.lock_outline_rounded,
          title: '未登录',
          message: serverMessage ?? '未登录或登录已过期',
        );
      case 403:
        return ErrorInfo(
          icon: Icons.block_rounded,
          title: '没有权限',
          message: serverMessage ?? '没有权限访问',
        );
      case 404:
        return ErrorInfo(
          icon: Icons.explore_off_rounded,
          title: '内容不存在',
          message: serverMessage ?? '内容不存在或已被删除',
        );
      case 410:
        return ErrorInfo(
          icon: Icons.delete_outline_rounded,
          title: '已删除',
          message: serverMessage ?? '内容已被删除',
        );
      case 422:
        return ErrorInfo(
          icon: Icons.warning_amber_rounded,
          title: '无法处理',
          message: serverMessage ?? '请求无法处理',
        );
      case 429:
        return ErrorInfo(
          icon: Icons.speed_rounded,
          title: '请求过于频繁',
          message: serverMessage ?? '请求过于频繁，请稍后再试',
        );
      case 500:
        return ErrorInfo(
          icon: Icons.cloud_off_rounded,
          title: '服务器错误',
          message: serverMessage ?? '服务器内部错误',
        );
      case 502:
      case 503:
      case 504:
        return ErrorInfo(
          icon: Icons.cloud_off_rounded,
          title: '服务器不可用',
          message: serverMessage ?? '服务器暂时不可用，请稍后重试',
        );
      default:
        return ErrorInfo(
          icon: Icons.error_outline_rounded,
          title: '请求失败',
          message: serverMessage ?? '请求失败 ($statusCode)',
        );
    }
  }
}
