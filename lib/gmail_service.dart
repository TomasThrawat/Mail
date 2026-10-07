import 'dart:convert';

import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/gmail/v1.dart';

import 'models.dart';

class GmailService {
  GmailService(this.signIn);

  final GoogleSignIn signIn;
  static const scopes = <String>[
    'https://mail.google.com/',
  ];

  GmailApi? _gmail;

  Future<MailAccount?> initialize() async {
    await signIn.initialize();
    final user = signIn.currentUser;
    if (user == null) return null;
    return _authorize(user);
  }

  Future<MailAccount?> signInAccount() async {
    final user = await signIn.authenticate();
    return _authorize(user);
  }

  Future<MailAccount?> _authorize(GoogleSignInAccount user) async {
    final authorization = await user.authorizationClient.authorizeScopes(scopes);
    final client = authorization.authClient(scopes: scopes);
    _gmail = GmailApi(client);
    return MailAccount(
      email: user.email,
      displayName: user.displayName,
      photoUrl: user.photoUrl,
    );
  }

  Future<List<MailMessage>> loadInbox({int maxResults = 50}) async {
    final api = _requireApi();
    final response = await api.users.messages.list('me', labelIds: const ['INBOX'], maxResults: maxResults);
    final refs = response.messages ?? const <Message>[];
    final result = <MailMessage>[];
    for (final ref in refs) {
      final id = ref.id;
      if (id == null) continue;
      final message = await api.users.messages.get('me', id, format: 'full');
      result.add(_toMailMessage(message));
    }
    return result;
  }

  Future<void> deleteMessage(String id) async {
    await _requireApi().users.messages.delete('me', id);
  }

  Future<void> deleteAllMessages() async {
    final api = _requireApi();
    String? pageToken;
    do {
      final page = await api.users.messages.list('me', maxResults: 500, pageToken: pageToken);
      for (final message in page.messages ?? const <Message>[]) {
        final id = message.id;
        if (id != null) await api.users.messages.delete('me', id);
      }
      pageToken = page.nextPageToken;
    } while (pageToken != null && pageToken.isNotEmpty);
  }

  GmailApi _requireApi() {
    final api = _gmail;
    if (api == null) throw StateError('No Gmail account is authorized.');
    return api;
  }

  MailMessage _toMailMessage(Message message) {
    final headers = <String, String>{
      for (final h in message.payload?.headers ?? const <MessagePartHeader>[])
        if (h.name != null && h.value != null) h.name!.toLowerCase(): h.value!,
    };
    final internal = int.tryParse(message.internalDate ?? '');
    final body = _extractText(message.payload);
    return MailMessage(
      id: message.id ?? '',
      sender: headers['from'] ?? '',
      subject: headers['subject'] ?? '(No subject)',
      date: internal == null ? null : DateTime.fromMillisecondsSinceEpoch(internal),
      body: body,
      unread: (message.labelIds ?? const <String>[]).contains('UNREAD'),
    );
  }

  String _extractText(MessagePart? part) {
    if (part == null) return '';
    final type = part.mimeType ?? '';
    if (part.body?.data != null && type == 'text/plain') {
      return _decode(part.body!.data!);
    }
    for (final child in part.parts ?? const <MessagePart>[]) {
      final text = _extractText(child);
      if (text.trim().isNotEmpty) return text;
    }
    if (part.body?.data != null && type == 'text/html') {
      return _stripHtml(_decode(part.body!.data!));
    }
    return '';
  }

  String _decode(String value) {
    final normalized = value.replaceAll('-', '+').replaceAll('_', '/');
    final padded = normalized.padRight((normalized.length + 3) ~/ 4 * 4, '=');
    return utf8.decode(base64.decode(padded), allowMalformed: true);
  }

  String _stripHtml(String html) => html
      .replaceAll(RegExp(r'<style[\\s\\S]*?</style>', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'<script[\\s\\S]*?</script>', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll(RegExp(r'\\s+'), ' ')
      .trim();
}
