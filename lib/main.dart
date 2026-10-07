import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'gmail_service.dart';
import 'models.dart';

void main() {
  runApp(const MailApp());
}

class MailApp extends StatefulWidget {
  const MailApp({super.key});
  @override State<MailApp> createState() => _MailAppState();
}

class _MailAppState extends State<MailApp> {
  bool pureBlack = true;
  Locale locale = const Locale('en');
  bool notificationsOn = true;
  final GoogleSignIn signIn = GoogleSignIn.instance;
  late final GmailService gmail = GmailService(signIn);

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      pureBlack = p.getBool('pureBlack') ?? true;
      notificationsOn = p.getBool('notificationsOn') ?? true;
      locale = Locale(p.getString('language') ?? 'en');
    });
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('pureBlack', pureBlack);
    await p.setBool('notificationsOn', notificationsOn);
    await p.setString('language', locale.languageCode);
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Mail',
    locale: locale,
    themeMode: pureBlack ? ThemeMode.dark : ThemeMode.light,
    theme: ThemeData(brightness: Brightness.light, scaffoldBackgroundColor: Colors.white, colorScheme: ColorScheme.fromSeed(seedColor: Colors.black), useMaterial3: true),
    darkTheme: ThemeData(brightness: Brightness.dark, scaffoldBackgroundColor: Colors.black, canvasColor: Colors.black, colorScheme: const ColorScheme.dark(surface: Colors.black, onSurface: Colors.white, primary: Colors.white, onPrimary: Colors.black, error: Colors.red, onError: Colors.white), useMaterial3: true),
    home: MailPage(
      gmail: gmail,
      locale: locale,
      pureBlack: pureBlack,
      notificationsOn: notificationsOn,
      onTheme: (v) => setState(() { pureBlack = v; _save(); }),
      onLanguage: (v) => setState(() { locale = v; _save(); }),
      onNotifications: (v) => setState(() { notificationsOn = v; _save(); }),
    ),
  );
}

class MailPage extends StatefulWidget {
  const MailPage({super.key, required this.gmail, required this.locale, required this.pureBlack, required this.notificationsOn, required this.onTheme, required this.onLanguage, required this.onNotifications});
  final GmailService gmail;
  final Locale locale;
  final bool pureBlack;
  final bool notificationsOn;
  final ValueChanged<bool> onTheme;
  final ValueChanged<Locale> onLanguage;
  final ValueChanged<bool> onNotifications;
  @override State<MailPage> createState() => _MailPageState();
}

class _MailPageState extends State<MailPage> {
  MailAccount? account;
  final accounts = <MailAccount>[];
  List<MailMessage> messages = const [];
  bool loading = true;
  String? error;

  bool get ar => widget.locale.languageCode == 'ar';
  String tr(String en, String ar) => this.ar ? ar : en;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final a = await widget.gmail.initialize();
      if (a != null) {
        account = a;
        accounts.add(a);
        await _refresh();
      }
    } catch (e) {
      error = e.toString();
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _addAccount() async {
    try {
      final a = await widget.gmail.signInAccount();
      if (a != null && mounted) {
        setState(() {
          if (!accounts.any((x) => x.email == a.email)) accounts.add(a);
          account = a;
        });
        await _refresh();
      }
    } catch (e) {
      _showError(e.toString());
    }
  }

  Future<void> _refresh() async {
    if (account == null) return;
    setState(() => loading = true);
    try {
      final result = await widget.gmail.loadInbox();
      if (mounted) setState(() => messages = result);
    } catch (e) {
      if (mounted) _showError(e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _deleteAll() async {
    try {
      await widget.gmail.deleteAllMessages();
      if (mounted) setState(() => messages = const []);
    } catch (e) {
      _showError(e.toString());
    }
  }

  void _showError(String message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mail', style: TextStyle(fontWeight: FontWeight.w600)),
        actions: [
          IconButton(onPressed: _accountPopup, icon: account?.photoUrl != null ? CircleAvatar(backgroundImage: NetworkImage(account!.photoUrl!), radius: 14) : const Icon(Icons.account_circle_outlined)),
          IconButton(onPressed: _confirmDeleteAll, icon: const Icon(Icons.delete_outline)),
        ],
      ),
      body: loading && messages.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(onRefresh: _refresh, child: messages.isEmpty ? ListView(children: [const SizedBox(height: 220), Center(child: Text('No messages'))]) : ListView.builder(itemCount: messages.length, itemBuilder: (_, i) => _messageTile(messages[i]))),
      floatingActionButton: account == null ? FloatingActionButton.extended(onPressed: _addAccount, label: Text(tr('Add email', 'إضافة بريد إلكتروني')), icon: const Icon(Icons.add)) : null,
    );
  }

  Widget _messageTile(MailMessage m) => ListTile(
    title: Text(m.sender, maxLines: 1, overflow: TextOverflow.ellipsis),
    subtitle: Text(m.subject, maxLines: 1, overflow: TextOverflow.ellipsis),
    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MessagePage(message: m))),
  );

  void _accountPopup() {
    showModalBottomSheet<void>(context: context, builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      ...accounts.map((a) => ListTile(leading: a.photoUrl == null ? const Icon(Icons.account_circle) : CircleAvatar(backgroundImage: NetworkImage(a.photoUrl!)), title: Text(a.email), onTap: () { setState(() => account = a); Navigator.pop(context); _refresh(); })),
      ListTile(leading: const Icon(Icons.add), title: Text(tr('Add email', 'إضافة بريد إلكتروني')), onTap: () { Navigator.pop(context); _addAccount(); }),
      ListTile(leading: const Icon(Icons.settings_outlined), title: Text(tr('Settings', 'الإعدادات')), onTap: () { Navigator.pop(context); _settings(); }),
    ])));
  }

  void _confirmDeleteAll() {
    showDialog<void>(context: context, builder: (_) => AlertDialog(
      title: Text(tr('Delete all messages?', 'حذف كل الرسائل؟')),
      content: Text(tr('Do you want to delete all the messages?', 'هل تريد حذف كل الرسائل؟')),
      actions: [TextButton(style: TextButton.styleFrom(backgroundColor: Colors.black, foregroundColor: Colors.white), onPressed: () => Navigator.pop(context), child: Text(tr('Cancel', 'إلغاء'))), FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white), onPressed: () { Navigator.pop(context); _deleteAll(); }, child: Text(tr('Delete', 'حذف')))],
    ));
  }

  void _settings() => Navigator.push(context, MaterialPageRoute(builder: (_) => SettingsPage(locale: widget.locale, pureBlack: widget.pureBlack, notificationsOn: widget.notificationsOn, onTheme: widget.onTheme, onLanguage: widget.onLanguage, onNotifications: widget.onNotifications)));
}

class MessagePage extends StatelessWidget {
  const MessagePage({super.key, required this.message});
  final MailMessage message;
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Mail')), body: SelectionArea(child: ListView(padding: const EdgeInsets.all(20), children: [Text(message.subject, style: Theme.of(context).textTheme.headlineSmall), const SizedBox(height: 12), Text(message.sender), const SizedBox(height: 20), SelectableText(message.body.isEmpty ? '(No text)' : message.body)])));
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.locale, required this.pureBlack, required this.notificationsOn, required this.onTheme, required this.onLanguage, required this.onNotifications});
  final Locale locale; final bool pureBlack; final bool notificationsOn; final ValueChanged<bool> onTheme; final ValueChanged<Locale> onLanguage; final ValueChanged<bool> onNotifications;
  String tr(String en, String ar) => locale.languageCode == 'ar' ? ar : en;
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text(tr('Settings', 'الإعدادات'))), body: ListView(padding: const EdgeInsets.all(20), children: [
    Text(tr('Color', 'اللون'), style: Theme.of(context).textTheme.titleLarge),
    RadioListTile(value: true, groupValue: pureBlack, title: Text(tr('Pure Black', 'أسود نقي')), onChanged: (v) { if (v != null) onTheme(v); }),
    RadioListTile(value: false, groupValue: pureBlack, title: Text(tr('White', 'أبيض')), onChanged: (v) { if (v != null) onTheme(v); }),
    const SizedBox(height: 16), Text(tr('Notifications', 'الإشعارات'), style: Theme.of(context).textTheme.titleLarge),
    RadioListTile(value: true, groupValue: notificationsOn, title: Text(tr('Notifications On', 'الإشعارات مفعلة')), onChanged: (v) { if (v != null) onNotifications(v); }),
    RadioListTile(value: false, groupValue: notificationsOn, title: Text(tr('Notifications Off', 'الإشعارات متوقفة')), onChanged: (v) { if (v != null) onNotifications(v); }),
    const SizedBox(height: 16), Text(tr('Language', 'اللغة'), style: Theme.of(context).textTheme.titleLarge),
    RadioListTile(value: const Locale('ar'), groupValue: locale, title: const Text('Arabic'), onChanged: (v) { if (v != null) onLanguage(v); }),
    RadioListTile(value: const Locale('en'), groupValue: locale, title: const Text('English'), onChanged: (v) { if (v != null) onLanguage(v); }),
    const SizedBox(height: 40), FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white), onPressed: () {}, child: Text(tr('Sign out', 'تسجيل الخروج'))),
  ]));
}
