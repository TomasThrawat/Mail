import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/services.dart';

class AppLogger {
  AppLogger._();

  static final AppLogger instance = AppLogger._();
  static const MethodChannel _channel = MethodChannel(
    'com.hyouka.mail/diagnostics',
  );

  Future<void> _writeQueue = Future<void>.value();
  String? _logPath;
  bool _initialized = false;

  String? get logPath => _logPath;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;

    try {
      final Map<Object?, Object?>? result =
          await _channel.invokeMethod<Map<Object?, Object?>>('initialize');
      _logPath = result?['logPath']?.toString();
      await log(
        'native_diagnostics',
        fields: <String, Object?>{
          'log_path': _logPath,
          'os': Platform.operatingSystem,
          'os_version': Platform.operatingSystemVersion,
          'dart_version': Platform.version,
        },
      );
    } catch (error, stackTrace) {
      developer.log(
        'Logger initialization failed: ' + _sanitizeText(error.toString()),
        name: 'MailDiagnostics',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> log(
    String event, {
    String level = 'INFO',
    Map<String, Object?> fields = const <String, Object?>{},
  }) {
    final Map<String, Object?> payload = <String, Object?>{
      'timestamp_utc': DateTime.now().toUtc().toIso8601String(),
      'level': level,
      'event': event,
      'fields': _sanitizeMap(fields),
    };
    final String line = jsonEncode(payload);

    developer.log(line, name: 'MailDiagnostics');

    final Future<void> next = _writeQueue.then((_) async {
      try {
        await _channel.invokeMethod<void>('writeLog', <String, Object?>{
          'line': line + '\n',
        });
      } catch (error, stackTrace) {
        developer.log(
          'Log file write failed: ' + _sanitizeText(error.toString()),
          name: 'MailDiagnostics',
          error: error,
          stackTrace: stackTrace,
        );
      }
    });
    _writeQueue = next.catchError((_) {});
    return next;
  }

  Future<void> error(
    String event,
    Object errorObject,
    StackTrace stackTrace, {
    Map<String, Object?> fields = const <String, Object?>{},
  }) {
    final String message = _sanitizeText(errorObject.toString());
    final RegExpMatch? statusMatch = RegExp(r'\[(\d+)\]').firstMatch(message);
    final String? numericStatus = statusMatch?.group(1);
    final Map<String, Object?> merged = <String, Object?>{
      ...fields,
      'error_type': errorObject.runtimeType.toString(),
      'error': message,
      'stack_trace': _sanitizeText(stackTrace.toString()),
      if (numericStatus != null) 'numeric_status_code': int.tryParse(numericStatus),
      if (numericStatus == '16')
        'status_code_meaning': 'CommonStatusCodes.CANCELED / cancel-like result',
    };
    return log(event, level: 'ERROR', fields: merged);
  }

  Map<String, Object?> _sanitizeMap(Map<String, Object?> input) {
    return input.map(
      (String key, Object? value) => MapEntry(
        key,
        value is String ? _sanitizeText(value) : value,
      ),
    );
  }

  String _sanitizeText(String value) {
    String sanitized = value;
    final List<RegExp> patterns = <RegExp>[
      RegExp(r'Bearer\s+[^\s,]+', caseSensitive: false),
      RegExp(r'(access_token|refresh_token|id_token|authorization|authcode|serverAuthCode)\s*[:=]\s*[^\s,]+', caseSensitive: false),
      RegExp(r'ya29\.[A-Za-z0-9._-]+'),
      RegExp(r'1//[A-Za-z0-9._-]+'),
    ];
    for (final RegExp pattern in patterns) {
      sanitized = sanitized.replaceAll(pattern, 'REDACTED');
    }
    return sanitized;
  }

  static String maskEmail(String email) {
    final int at = email.indexOf('@');
    if (at <= 1) {
      return email.isEmpty ? '<empty>' : '***';
    }
    return email[0] + '***' + email.substring(at);
  }
}
