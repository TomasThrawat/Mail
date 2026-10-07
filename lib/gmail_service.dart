import 'dart:convert';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/gmail/v1.dart';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';

import 'models.dart';
import 'app_logger.dart';

class GmailService {
  bool _isAuthorizationMissing(
    GoogleSignInClientAuthorization? authorization,
  ) =>
      authorization == null;

  GmailService(this.signIn);

  final GoogleSignIn signIn;

  static const List<String> scopes = <String>['https://mail.google.com/'];

  // OAuth client IDs are public identifiers, so keep the Web client ID as the
  // default. The build-time value can still override it for another project.
  static const String _serverClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    defaultValue:
        '1057557137418-g440cu974hf39b1k4qhumag6lhbpkdnb.apps.googleusercontent.com',
  );

  final Map<String, GmailApi> _apis = <String, GmailApi>{};
  final Map<String, GoogleSignInAccount> _users =
      <String, GoogleSignInAccount>{};
  bool _initialized = false;
  final AppLogger _logger = AppLogger.instance;

  Future<void> initialize() async {
    if (_initialized) {
      await _logger.log('google.initialize.skip');
      return;
    }
    await _logger.log(
      'google.initialize.start',
      fields: <String, Object?>{
        'server_client_id': _serverClientId,
        'scopes': scopes,
      },
    );
    try {
      await signIn.initialize(
        serverClientId: _serverClientId.isEmpty ? null : _serverClientId,
      );
      _initialized = true;
      await _logger.log('google.initialize.success');
    } catch (error, stackTrace) {
      await _logger.error('google.initialize.error', error, stackTrace);
      rethrow;
    }
  }

  Future<MailAccount?> restoreAccount() async {
    await _logger.log('google.restore.start');
    try {
      await initialize();
      final Future<GoogleSignInAccount?>? attempt =
          signIn.attemptLightweightAuthentication();
      if (attempt == null) {
        await _logger.log('google.restore.lightweight_unavailable');
        return null;
      }

      final GoogleSignInAccount? user = await attempt;
      if (user == null) {
        await _logger.log('google.restore.no_account');
        return null;
      }

      await _logger.log(
        'google.restore.account_found',
        fields: <String, Object?>{
          'email': AppLogger.maskEmail(user.email),
        },
      );
      return await _authorize(user, promptIfNeeded: false);
    } catch (error, stackTrace) {
      await _logger.error('google.restore.error', error, stackTrace);
      rethrow;
    }
  }

  Future<MailAccount> authenticateAccount() async {
    await _logger.log('google.authenticate.start');
    try {
      await initialize();
      final bool supported = signIn.supportsAuthenticate();
      await _logger.log(
        'google.authenticate.capability',
        fields: <String, Object?>{'supports_authenticate': supported},
      );
      if (!supported) {
        throw StateError('Google Sign-In authentication is unavailable.');
      }

      await _logger.log('google.authenticate.disconnect.start');
      await signIn.disconnect();
      await _logger.log('google.authenticate.disconnect.success');

      await _logger.log('google.authenticate.interactive.start');
      final GoogleSignInAccount user = await signIn.authenticate();
      await _logger.log(
        'google.authenticate.interactive.success',
        fields: <String, Object?>{
          'email': AppLogger.maskEmail(user.email),
          'display_name_present': user.displayName?.isNotEmpty == true,
        },
      );

      final MailAccount? account = await _authorize(
        user,
        promptIfNeeded: true,
      );
      if (account == null) {
        throw StateError('Gmail authorization was not granted.');
      }
      await _logger.log(
        'google.authenticate.complete',
        fields: <String, Object?>{
          'email': AppLogger.maskEmail(account.email),
        },
      );
      return account;
    } catch (error, stackTrace) {
      await _logger.error('google.authenticate.error', error, stackTrace);
      rethrow;
    }
  }

  Future<MailAccount?> _authorize(
    GoogleSignInAccount user, {
    required bool promptIfNeeded,
  }) async {
    await _logger.log(
      'google.authorization.start',
      fields: <String, Object?>{
        'email': AppLogger.maskEmail(user.email),
        'prompt_if_needed': promptIfNeeded,
        'scopes': scopes,
      },
    );
    try {
      final Object? existingAuthorizationResult = await user
          .authorizationClient
          .authorizationForScopes(scopes);
      final GoogleSignInClientAuthorization? existingAuthorization =
          existingAuthorizationResult is GoogleSignInClientAuthorization
              ? existingAuthorizationResult
              : null;
      GoogleSignInClientAuthorization? authorization = existingAuthorization;

      await _logger.log(
        'google.authorization.existing_result',
        fields: <String, Object?>{
          'available': !_isAuthorizationMissing(authorization),
        },
      );

      if (_isAuthorizationMissing(authorization) && promptIfNeeded) {
        await _logger.log('google.authorization.prompt.start');
        authorization = await user.authorizationClient.authorizeScopes(scopes);
        await _logger.log(
          'google.authorization.prompt.result',
          fields: <String, Object?>{
            'available': !_isAuthorizationMissing(authorization),
          },
        );
      }
      if (_isAuthorizationMissing(authorization)) {
        await _logger.log('google.authorization.not_granted');
        return null;
      }

      final GoogleSignInClientAuthorization grantedAuthorization = authorization!;
      _apis[user.email] = GmailApi(
        grantedAuthorization.authClient(scopes: scopes),
      );
      _users[user.email] = user;

      await _logger.log(
        'google.authorization.success',
        fields: <String, Object?>{
          'email': AppLogger.maskEmail(user.email),
        },
      );

      return MailAccount(
        email: user.email,
        displayName: user.displayName,
        photoUrl: user.photoUrl,
      );
    } catch (error, stackTrace) {
      await _logger.error('google.authorization.error', error, stackTrace);
      rethrow;
    }
  }

  Future<void> refreshAuthorization(String email) async {
    await _logger.log(
      'google.refresh_authorization.start',
      fields: <String, Object?>{'email': AppLogger.maskEmail(email)},
    );
    try {
      final GoogleSignInAccount? user = _users[email];
      if (user == null) {
        throw StateError('The selected Google account is not available.');
      }
      final MailAccount? account = await _authorize(
        user,
        promptIfNeeded: true,
      );
      if (account == null) {
        throw StateError('Gmail authorization was not granted.');
      }
      await _logger.log('google.refresh_authorization.success');
    } catch (error, stackTrace) {
      await _logger.error(
        'google.refresh_authorization.error',
        error,
        stackTrace,
        fields: <String, Object?>{'email': AppLogger.maskEmail(email)},
      );
      rethrow;
    }
  }

  Future<List<MailMessage>> loadInbox(
    String email, {
    int maxResults = 50,
  }) async {
    await _ensureAuthorized(email);
    final GmailApi api = _requireApi(email);

    final List<Message> refs =
        (await api.users.messages.list(
          'me',
          labelIds: const <String>['INBOX'],
          maxResults: maxResults,
        )).messages ??
        const <Message>[];

    final List<MailMessage> messages = await Future.wait(
      refs
          .where((Message ref) => ref.id != null)
          .map(
            (Message ref) async => _toMailMessage(
              await api.users.messages.get('me', ref.id!, format: 'full'),
            ),
          ),
    );

    messages.sort(
      (MailMessage a, MailMessage b) =>
          (b.date ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(
            a.date ?? DateTime.fromMillisecondsSinceEpoch(0),
          ),
    );
    return messages;
  }

  Future<void> deleteMessage(String email, String id) async {
    await _ensureAuthorized(email);
    await _requireApi(email).users.messages.delete('me', id);
  }

  Future<void> deleteAllMessages(String email) async {
    await _ensureAuthorized(email);
    final GmailApi api = _requireApi(email);

    while (true) {
      final List<Message> messages =
          (await api.users.messages.list('me', maxResults: 500)).messages ??
          const <Message>[];
      final List<String> ids = messages
          .map((Message message) => message.id)
          .whereType<String>()
          .toList(growable: false);

      if (ids.isEmpty) {
        return;
      }

      await Future.wait(
        ids.map((String id) => api.users.messages.delete('me', id)),
      );
    }
  }

  Future<void> signOutCurrent() async {
    await _logger.log('google.signout.start');
    try {
      await signIn.disconnect();
      _apis.clear();
      _users.clear();
      await _logger.log('google.signout.success');
    } catch (error, stackTrace) {
      await _logger.error('google.signout.error', error, stackTrace);
      rethrow;
    }
  }

  Future<void> _ensureAuthorized(String email) async {
    await _logger.log(
      'gmail.ensure_authorized.start',
      fields: <String, Object?>{'email': AppLogger.maskEmail(email)},
    );
    if (_apis.containsKey(email)) {
      try {
        await _requireApi(email).users.getProfile('me');
        await _logger.log('gmail.ensure_authorized.cached_success');
        return;
      } catch (error, stackTrace) {
        await _logger.error(
          'gmail.ensure_authorized.cached_failed',
          error,
          stackTrace,
          fields: <String, Object?>{'email': AppLogger.maskEmail(email)},
        );
        _apis.remove(email);
      }
    }

    await refreshAuthorization(email);
  }

  GmailApi _requireApi(String email) {
    final GmailApi? api = _apis[email];
    if (api == null) {
      throw StateError('No Gmail authorization for $email.');
    }
    return api;
  }

  MailMessage _toMailMessage(Message message) {
    final Map<String, String> headers = <String, String>{
      for (final MessagePartHeader header
          in message.payload?.headers ?? const <MessagePartHeader>[])
        if (header.name != null && header.value != null)
          header.name!.toLowerCase(): header.value!,
    };

    final int? internalMilliseconds = int.tryParse(message.internalDate ?? '');
    final DateTime? date =
        internalMilliseconds == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(internalMilliseconds);

    return MailMessage(
      id: message.id ?? '',
      sender: headers['from'] ?? '',
      subject: headers['subject'] ?? '(No subject)',
      date: date,
      body: _extractText(message.payload),
      unread: (message.labelIds ?? const <String>[]).contains('UNREAD'),
    );
  }

  String _extractText(MessagePart? part) {
    if (part == null) {
      return '';
    }

    final String mimeType = part.mimeType ?? '';
    final String? data = part.body?.data;
    if (data != null && mimeType == 'text/plain') {
      return _decode(data);
    }

    for (final MessagePart child in part.parts ?? const <MessagePart>[]) {
      final String text = _extractText(child);
      if (text.trim().isNotEmpty) {
        return text;
      }
    }

    if (data != null && mimeType == 'text/html') {
      return _stripHtml(_decode(data));
    }

    return '';
  }

  String _decode(String value) {
    final String normalized = value.replaceAll('-', '+').replaceAll('_', '/');
    final String padded = normalized.padRight(
      (normalized.length + 3) ~/ 4 * 4,
      '=',
    );
    return utf8.decode(base64.decode(padded), allowMalformed: true);
  }

  String _stripHtml(String html) =>
      html
          .replaceAll(
            RegExp(r'<style[\s\S]*?</style>', caseSensitive: false),
            ' ',
          )
          .replaceAll(
            RegExp(r'<script[\s\S]*?</script>', caseSensitive: false),
            ' ',
          )
          .replaceAll(RegExp(r'<[^>]*>'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
}
