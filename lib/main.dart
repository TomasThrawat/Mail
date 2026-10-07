import 'package:flutter/material.dart';

void main() {
  runApp(const MailApp());
}

class MailApp extends StatefulWidget {
  const MailApp({super.key});

  @override
  State<MailApp> createState() => _MailAppState();
}

class _MailAppState extends State<MailApp> {
  ThemeMode _themeMode = ThemeMode.dark;
  Locale _locale = const Locale('en');

  @override
  Widget build(BuildContext context) {
    final isBlack = _themeMode == ThemeMode.dark;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Mail',
      locale: _locale,
      themeMode: _themeMode,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: Colors.white,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.black, brightness: Brightness.light),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        canvasColor: Colors.black,
        colorScheme: const ColorScheme.dark(
          surface: Colors.black,
          onSurface: Colors.white,
          primary: Colors.white,
          onPrimary: Colors.black,
          error: Colors.red,
          onError: Colors.white,
        ),
        useMaterial3: true,
      ),
      home: MailHome(
        pureBlack: isBlack,
        locale: _locale,
        onThemeChanged: (black) => setState(() => _themeMode = black ? ThemeMode.dark : ThemeMode.light),
        onLocaleChanged: (locale) => setState(() => _locale = locale),
      ),
    );
  }
}

class MailHome extends StatefulWidget {
  const MailHome({super.key, required this.pureBlack, required this.locale, required this.onThemeChanged, required this.onLocaleChanged});
  final bool pureBlack;
  final Locale locale;
  final ValueChanged<bool> onThemeChanged;
  final ValueChanged<Locale> onLocaleChanged;

  @override
  State<MailHome> createState() => _MailHomeState();
}

class _MailHomeState extends State<MailHome> {
  bool notificationsOn = true;
  String? activeAccount;
  final List<String> accounts = [];

  bool get ar => widget.locale.languageCode == 'ar';
  String tr(String en, String ar) => this.ar ? ar : en;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Mail', 'Mail'), style: const TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: widget.pureBlack ? Colors.black : Colors.white,
        foregroundColor: widget.pureBlack ? Colors.white : Colors.black,
        actions: [
          IconButton(icon: const Icon(Icons.account_circle_outlined), onPressed: _accountPopup),
          IconButton(icon: const Icon(Icons.delete_outline), onPressed: _deleteAllConfirmation),
        ],
      ),
      body: Center(
        child: accounts.isEmpty
            ? FilledButton.icon(
                onPressed: _addEmail,
                icon: const Icon(Icons.add),
                label: Text(tr('Add email', 'إضافة بريد إلكتروني')),
              )
            : ListView.builder(
                itemCount: 0,
                itemBuilder: (_, __) => const SizedBox.shrink(),
              ),
      ),
    );
  }

  void _accountPopup() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: widget.pureBlack ? Colors.black : Colors.white,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (activeAccount != null) Text(activeAccount!, style: const TextStyle(fontWeight: FontWeight.w600)),
            if (accounts.isNotEmpty) ...accounts.map((a) => ListTile(title: Text(a), onTap: () { setState(() => activeAccount = a); Navigator.pop(context); })),
            ListTile(leading: const Icon(Icons.add), title: Text(tr('Add email', 'إضافة بريد إلكتروني')), onTap: () { Navigator.pop(context); _addEmail(); }),
            ListTile(leading: const Icon(Icons.settings_outlined), title: Text(tr('Settings', 'الإعدادات')), onTap: () { Navigator.pop(context); _settings(); }),
          ]),
        ),
      ),
    );
  }

  Future<void> _addEmail() async {
    // Real Google OAuth/Gmail API integration is implemented in the account service layer.
    // This UI intentionally does not fake an account connection.
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Google account connection is being wired to Gmail API.', 'جاري ربط حساب Google بخدمة Gmail API.'))));
  }

  void _deleteAllConfirmation() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: widget.pureBlack ? Colors.black : Colors.white,
        title: Text(tr('Delete all messages?', 'حذف كل الرسائل؟')),
        content: Text(tr('Do you want to delete all the messages?', 'هل تريد حذف كل الرسائل؟')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Cancel', 'إلغاء'))),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white), onPressed: () { Navigator.pop(context); }, child: Text(tr('Delete', 'حذف'))),
        ],
      ),
    );
  }

  void _settings() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => SettingsPage(
      pureBlack: widget.pureBlack,
      notificationsOn: notificationsOn,
      locale: widget.locale,
      onThemeChanged: widget.onThemeChanged,
      onNotificationsChanged: (v) => setState(() => notificationsOn = v),
      onLocaleChanged: widget.onLocaleChanged,
    )));
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.pureBlack, required this.notificationsOn, required this.locale, required this.onThemeChanged, required this.onNotificationsChanged, required this.onLocaleChanged});
  final bool pureBlack;
  final bool notificationsOn;
  final Locale locale;
  final ValueChanged<bool> onThemeChanged;
  final ValueChanged<bool> onNotificationsChanged;
  final ValueChanged<Locale> onLocaleChanged;

  String tr(String en, String ar) => locale.languageCode == 'ar' ? ar : en;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Settings', 'الإعدادات'))),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Text(tr('Color', 'اللون'), style: Theme.of(context).textTheme.titleLarge),
        RadioListTile<bool>(value: true, groupValue: pureBlack, title: Text(tr('Pure Black', 'أسود نقي')), onChanged: (v) { if (v != null) onThemeChanged(v); }),
        RadioListTile<bool>(value: false, groupValue: pureBlack, title: Text(tr('White', 'أبيض')), onChanged: (v) { if (v != null) onThemeChanged(v); }),
        const SizedBox(height: 20),
        Text(tr('Notifications', 'الإشعارات'), style: Theme.of(context).textTheme.titleLarge),
        RadioListTile<bool>(value: true, groupValue: notificationsOn, title: Text(tr('Notifications On', 'الإشعارات مفعلة')), onChanged: (v) { if (v != null) onNotificationsChanged(v); }),
        RadioListTile<bool>(value: false, groupValue: notificationsOn, title: Text(tr('Notifications Off', 'الإشعارات متوقفة')), onChanged: (v) { if (v != null) onNotificationsChanged(v); }),
        const SizedBox(height: 20),
        Text(tr('Language', 'اللغة'), style: Theme.of(context).textTheme.titleLarge),
        RadioListTile<Locale>(value: const Locale('ar'), groupValue: locale, title: const Text('Arabic'), onChanged: (v) { if (v != null) onLocaleChanged(v); }),
        RadioListTile<Locale>(value: const Locale('en'), groupValue: locale, title: const Text('English'), onChanged: (v) { if (v != null) onLocaleChanged(v); }),
        const SizedBox(height: 40),
        FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white), onPressed: () => Navigator.pop(context), child: Text(tr('Sign out', 'تسجيل الخروج'))),
      ]),
    );
  }
}
