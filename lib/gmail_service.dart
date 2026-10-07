import 'dart:async';
import 'dart:convert';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/gmail/v1.dart';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';

import 'models.dart';

class GmailService {
  bool _isAuthorizationMissing(
    GoogleSignInClientAuthorization? authorization,
  ) => authorization == null;

  GmailService(this.signIn);

  final GoogleSignIn signIn;

  static const List<String> scopes = <String>['https://mail.google.com/'];

  // OAuth client IDs are public identifiers, so keep the Web client ID as the
  // default. The build-time value can still override it for another project.
  static const String _serverClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    defaultValue:
        '1057557137418-shkm3tmihedijreur8u8lvf3d84tnpmo.apps.googleusercontent.com',
  );

  final Map<String, GmailApi> _apis = <String, GmailApi>{};
  final Map<String, GoogleSignInAccount> _users =
      <String, GoogleSignInAccount>{};
  Future<void>? _initialization;
  Future<void> _operationQueue = Future<void>.value();

  Future<void> initialize() {
    return _initialization ??= signIn.initialize(
      serverClientId: _serverClientId.isEmpty ? null : _serverClientId,
    );
  }

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final Completer<T> result = Completer<T>();

    _operationQueue = _operationQueue.then<void>((_) async {
      try {
        result.complete(await operation());
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });

    return result.future;
  }

  bool _isRetryableApiError(Object error) {
    if (error is! DetailedApiRequestError) {
      return false;
    }

    final int? status = error.status;
    return status == 429 || (status != null && status >= 500 && status <= 599);
  }

  Future<T> _withApiRetry<T>(Future<T> Function() request) async {
    const int maxRetries = 4;

    for (int attempt = 0; ; attempt++) {
      try {
        return await request();
      } catch (error) {
        if (!_isRetryableApiError(error) || attempt >= maxRetries) {
          rethrow;
        }

        final int delayMs = 500 * (1 << attempt);
        await Future<void>.delayed(Duration(milliseconds: delayMs));
      }
    }
  }

  Future<MailAccount?> restoreAccount() async {
    try {
      await initialize();
      final Future<GoogleSignInAccount?>? attempt =
          signIn.attemptLightweightAuthentication();
      if (attempt == null) {
        return null;
      }

      final GoogleSignInAccount? user = await attempt;
      if (user == null) {
        return null;
      }

      return await _authorize(user, promptIfNeeded: false);
    } catch (error) {
      rethrow;
    }
  }

  Future<MailAccount> authenticateAccount() {
    return _enqueue(() async {
      await initialize();
      final bool supported = signIn.supportsAuthenticate();
      if (!supported) {
        throw StateError('Google Sign-In authentication is unavailable.');
      }

      // google_sign_in recommends signing out before starting a new
      // interactive authentication flow. Disconnect would revoke the app's
      // Google authorization and can make the add-account flow appear to do
      // nothing on Android.
      await signIn.signOut();
      final GoogleSignInAccount user = await signIn.authenticate();
      final MailAccount? account = await _authorize(user, promptIfNeeded: true);
      if (account == null) {
        throw StateError('Gmail authorization was not granted.');
      }
      return account;
    });
  }

  Future<MailAccount?> _authorize(
    GoogleSignInAccount user, {
    required bool promptIfNeeded,
  }) async {
    try {
      final Object? existingAuthorizationResult = await user.authorizationClient
          .authorizationForScopes(scopes);
      final GoogleSignInClientAuthorization? existingAuthorization =
          existingAuthorizationResult is GoogleSignInClientAuthorization
              ? existingAuthorizationResult
              : null;
      GoogleSignInClientAuthorization? authorization = existingAuthorization;

      if (_isAuthorizationMissing(authorization) && promptIfNeeded) {
        authorization = await user.authorizationClient.authorizeScopes(scopes);
      }
      if (_isAuthorizationMissing(authorization)) {
        return null;
      }

      final GoogleSignInClientAuthorization grantedAuthorization =
          authorization!;
      _apis[user.email] = GmailApi(
        grantedAuthorization.authClient(scopes: scopes),
      );
      _users[user.email] = user;

      return MailAccount(
        email: user.email,
        displayName: user.displayName,
        photoUrl: user.photoUrl,
      );
    } catch (error) {
      rethrow;
    }
  }

  Future<void> refreshAuthorization(String email) {
    return _enqueue(() => _refreshAuthorization(email));
  }

  Future<void> _refreshAuthorization(String email) async {
    final GoogleSignInAccount? user = _users[email];
    if (user == null) {
      throw StateError('The selected Google account is not available.');
    }
    final MailAccount? account = await _authorize(user, promptIfNeeded: true);
    if (account == null) {
      throw StateError('Gmail authorization was not granted.');
    }
  }

  Future<List<MailMessage>> loadInbox(String email, {int maxResults = 50}) {
    return _enqueue(() => _loadInbox(email, maxResults: maxResults));
  }

  Future<List<MailMessage>> _loadInbox(
    String email, {
    required int maxResults,
  }) async {
    await _ensureAuthorized(email);
    final GmailApi api = _requireApi(email);

    final List<Message> refs =
        (await _withApiRetry(
          () => api.users.messages.list(
            'me',
            labelIds: const <String>['INBOX'],
            maxResults: maxResults,
          ),
        )).messages ??
        const <Message>[];

    final List<MailMessage> messages = <MailMessage>[];
    for (final Message ref in refs) {
      final String? id = ref.id;
      if (id == null) {
        continue;
      }

      final Message message = await _withApiRetry(
        () => api.users.messages.get('me', id, format: 'full'),
      );
      messages.add(_toMailMessage(message));
    }

    messages.sort(
      (MailMessage a, MailMessage b) =>
          (b.date ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(
            a.date ?? DateTime.fromMillisecondsSinceEpoch(0),
          ),
    );
    return messages;
  }

  Future<void> deleteMessage(String email, String id) {
    return _enqueue(() async {
      await _ensureAuthorized(email);
      await _withApiRetry(
        () => _requireApi(email).users.messages.delete('me', id),
      );
    });
  }

  Future<void> deleteAllMessages(String email) {
    return _enqueue(() => _deleteAllMessages(email));
  }

  Future<void> _deleteAllMessages(String email) async {
    await _ensureAuthorized(email);
    final GmailApi api = _requireApi(email);

    // Drain the currently authorized mailbox in bounded server-side batches.
    // includeSpamTrash makes "Delete All" cover every mailbox message, not
    // only Inbox, while the "me" user ID scopes deletion to this account.
    const int batchSize = 500;

    while (true) {
      final List<Message> messages =
          (await _withApiRetry(
            () => api.users.messages.list(
              'me',
              maxResults: batchSize,
              includeSpamTrash: true,
            ),
          )).messages ??
          const <Message>[];
      final List<String> ids = messages
          .map((Message message) => message.id)
          .whereType<String>()
          .toList(growable: false);

      if (ids.isEmpty) {
        return;
      }

      // Use Gmail's server-side batch operation instead of issuing hundreds
      // of individual delete requests concurrently.
      await _withApiRetry(
        () => api.users.messages.batchDelete(
          BatchDeleteMessagesRequest()..ids = ids,
          'me',
        ),
      );
    }
  }

  Future<void> signOutCurrent() {
    return _enqueue(() async {
      await signIn.disconnect();
      _apis.clear();
      _users.clear();
    });
  }

  Future<void> _ensureAuthorized(String email) async {
    if (_apis.containsKey(email)) {
      return;
    }

    await _refreshAuthorization(email);
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
