import 'dart:convert';

import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/gmail/v1.dart';

import 'models.dart';

class GmailService {
  GmailService(this.signIn);

  final GoogleSignIn signIn;

  static const List<String> scopes = <String>['https://mail.google.com/'];

  static const String _serverClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
  );

  final Map<String, GmailApi> _apis = <String, GmailApi>{};
  final Map<String, GoogleSignInAccount> _users =
      <String, GoogleSignInAccount>{};
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    await signIn.initialize(
      serverClientId: _serverClientId.isEmpty ? null : _serverClientId,
    );
    _initialized = true;
  }

  Future<MailAccount?> restoreAccount() async {
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

    return _authorize(user, promptIfNeeded: false);
  }

  Future<MailAccount> authenticateAccount() async {
    await initialize();
    if (!signIn.supportsAuthenticate()) {
      throw StateError('Google Sign-In authentication is unavailable.');
    }

    // Authenticate the account first, then request Gmail scopes separately.
    // This is the recommended google_sign_in 7.x flow and avoids the optional
    // combined Credential Manager authentication+authorization path.
    final GoogleSignInAccount user = await signIn.authenticate();
    final MailAccount? account = await _authorize(user, promptIfNeeded: true);
    if (account == null) {
      throw StateError('Gmail authorization was not granted.');
    }
    return account;
  }

  Future<MailAccount?> _authorize(
    GoogleSignInAccount user, {
    required bool promptIfNeeded,
  }) async {
    GoogleSignInClientAuthorization? authorization = await user
        .authorizationClient
        .authorizationForScopes(scopes);

    if (authorization == null && promptIfNeeded) {
      authorization = await user.authorizationClient.authorizeScopes(scopes);
    }
    if (authorization == null) {
      return null;
    }

    _apis[user.email] = GmailApi(authorization.authClient(scopes: scopes));
    _users[user.email] = user;

    return MailAccount(
      email: user.email,
      displayName: user.displayName,
      photoUrl: user.photoUrl,
    );
  }

  Future<void> refreshAuthorization(String email) async {
    final GoogleSignInAccount? user = _users[email];
    if (user == null) {
      throw StateError('The selected Google account is not available.');
    }
    final MailAccount? account = await _authorize(user, promptIfNeeded: true);
    if (account == null) {
      throw StateError('Gmail authorization was not granted.');
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
    await signIn.signOut();
    _apis.clear();
    _users.clear();
  }

  Future<void> _ensureAuthorized(String email) async {
    if (_apis.containsKey(email)) {
      try {
        await _requireApi(email).users.getProfile('me');
        return;
      } catch (_) {
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
