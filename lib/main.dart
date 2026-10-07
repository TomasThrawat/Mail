import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_logger.dart';
import 'gmail_service.dart';
import 'models.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppLogger.instance.initialize();
  await AppLogger.instance.log(
    'app.start',
    fields: <String, Object?>{'entrypoint': 'main'},
  );
  runApp(const MailApp());
}

class MailApp extends StatefulWidget {
  const MailApp({super.key});

  @override
  State<MailApp> createState() => _MailAppState();
}

class _MailAppState extends State<MailApp> {
  bool pureBlack = true;
  bool notificationsOn = true;
  Locale locale = const Locale('en');

  final GoogleSignIn signIn = GoogleSignIn.instance;
  late final GmailService gmail = GmailService(signIn);

  @override
  void initState() {
    super.initState();
    unawaited(_loadSettings());
  }

  Future<void> _loadSettings() async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    if (!mounted) {
      return;
    }
    setState(() {
      pureBlack = preferences.getBool('pureBlack') ?? true;
      notificationsOn = preferences.getBool('notificationsOn') ?? true;
      locale = Locale(preferences.getString('language') ?? 'en');
    });
  }

  Future<void> _saveSettings() async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    await preferences.setBool('pureBlack', pureBlack);
    await preferences.setBool('notificationsOn', notificationsOn);
    await preferences.setString('language', locale.languageCode);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Mail',
      locale: locale,
      themeMode: pureBlack ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          centerTitle: false,
        ),
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.black,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        canvasColor: Colors.black,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          centerTitle: false,
        ),
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
      builder: (BuildContext context, Widget? child) {
        final TextDirection direction =
            locale.languageCode == 'ar' ? TextDirection.rtl : TextDirection.ltr;
        return Directionality(
          textDirection: direction,
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: MailPage(
        gmail: gmail,
        locale: locale,
        pureBlack: pureBlack,
        notificationsOn: notificationsOn,
        onTheme: (bool value) {
          setState(() => pureBlack = value);
          unawaited(_saveSettings());
        },
        onLanguage: (Locale value) {
          setState(() => locale = value);
          unawaited(_saveSettings());
        },
        onNotifications: (bool value) {
          setState(() => notificationsOn = value);
          unawaited(_saveSettings());
        },
      ),
    );
  }
}

class MailPage extends StatefulWidget {
  const MailPage({
    super.key,
    required this.gmail,
    required this.locale,
    required this.pureBlack,
    required this.notificationsOn,
    required this.onTheme,
    required this.onLanguage,
    required this.onNotifications,
  });

  final GmailService gmail;
  final Locale locale;
  final bool pureBlack;
  final bool notificationsOn;
  final ValueChanged<bool> onTheme;
  final ValueChanged<Locale> onLanguage;
  final ValueChanged<bool> onNotifications;

  @override
  State<MailPage> createState() => _MailPageState();
}

class _MailPageState extends State<MailPage> {
  MailAccount? account;
  final List<MailAccount> accounts = <MailAccount>[];
  List<MailMessage> messages = const <MailMessage>[];
  bool loading = true;
  bool authenticating = false;

  bool get ar => widget.locale.languageCode == 'ar';

  String tr(String en, String ar) => this.ar ? ar : en;

  @override
  void initState() {
    super.initState();
    unawaited(_restore());
  }

  Future<void> _restore() async {
    await AppLogger.instance.log('ui.restore.start');
    try {
      final MailAccount? restored = await widget.gmail.restoreAccount();
      if (restored != null && mounted) {
        await AppLogger.instance.log(
          'ui.restore.success',
          fields: <String, Object?>{
            'email': AppLogger.maskEmail(restored.email),
          },
        );
        setState(() {
          account = restored;
          _upsertAccount(restored);
        });
        await _refresh();
      } else {
        await AppLogger.instance.log('ui.restore.no_account');
      }
    } catch (error, stackTrace) {
      await AppLogger.instance.error('ui.restore.error', error, stackTrace);
      _showError(_localError(error));
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  void _upsertAccount(MailAccount value) {
    final int index = accounts.indexWhere(
      (MailAccount item) => item.email == value.email,
    );
    if (index == -1) {
      accounts.add(value);
    } else {
      accounts[index] = value;
    }
  }

  Future<void> _addAccount() async {
    if (authenticating) {
      return;
    }

    await AppLogger.instance.log(
      'ui.add_account.start',
      fields: <String, Object?>{
        'had_current_account': account != null,
      },
    );
    setState(() => authenticating = true);
    try {
      final MailAccount added = await widget.gmail.authenticateAccount();
      if (!mounted) {
        return;
      }
      await AppLogger.instance.log(
        'ui.add_account.success',
        fields: <String, Object?>{
          'email': AppLogger.maskEmail(added.email),
        },
      );
      setState(() {
        _upsertAccount(added);
        account = added;
        messages = const <MailMessage>[];
      });
      await _refresh();
    } catch (error, stackTrace) {
      await AppLogger.instance.error('ui.add_account.error', error, stackTrace);
      _showError(_localError(error));
    } finally {
      if (mounted) {
        setState(() => authenticating = false);
      }
    }
  }

  Future<void> _selectAccount(MailAccount selected) async {
    Navigator.pop(context);

    if (selected.email == account?.email) {
      return;
    }

    setState(() {
      account = selected;
      messages = const <MailMessage>[];
    });

    await _refresh();
  }

  Future<void> _refresh() async {
    final MailAccount? selected = account;
    if (selected == null || !mounted) {
      return;
    }

    setState(() => loading = true);
    try {
      final List<MailMessage> result = await widget.gmail.loadInbox(
        selected.email,
      );
      if (mounted) {
        setState(() => messages = result);
      }
    } catch (error) {
      _showError(_localError(error));
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> _deleteAll() async {
    final MailAccount? selected = account;
    if (selected == null) {
      return;
    }

    setState(() => loading = true);
    try {
      await widget.gmail.deleteAllMessages(selected.email);
      if (mounted) {
        setState(() => messages = const <MailMessage>[]);
      }
    } catch (error) {
      _showError(_localError(error));
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> _deleteMessage(MailMessage message) async {
    final MailAccount? selected = account;
    if (selected == null) {
      return;
    }

    try {
      await widget.gmail.deleteMessage(selected.email, message.id);
      if (mounted) {
        setState(
          () =>
              messages =
                  messages
                      .where((MailMessage item) => item.id != message.id)
                      .toList(),
        );
      }
    } catch (error) {
      _showError(_localError(error));
    }
  }

  Future<void> _signOut() async {
    try {
      await widget.gmail.signOutCurrent();
      if (mounted) {
        setState(() {
          account = null;
          accounts.clear();
          messages = const <MailMessage>[];
        });
        Navigator.pop(context);
      }
    } catch (error) {
      _showError(_localError(error));
    }
  }

  String _localError(Object error) {
    final String logSuffix =
        AppLogger.instance.logPath == null
            ? ''
            : ' Log: $AppLogger.instance.logPath!';
    if (error is GoogleSignInException) {
      final String description = error.description ?? error.code.name;
      return tr(
        'Google sign-in failed: $description.$logSuffix',
        'فشل تسجيل الدخول إلى Google: $description.$logSuffix',
      );
    }
    return error.toString().replaceFirst('Bad state: ', '') + logSuffix;
  }

  void _showError(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final MailAccount? selected = account;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Mail',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        actions: <Widget>[
          IconButton(
            tooltip: tr('Accounts', 'الحسابات'),
            onPressed: _accountPopup,
            icon: AccountAvatar(account: selected, radius: 14),
          ),
          IconButton(
            tooltip: tr('Delete all messages', 'حذف كل الرسائل'),
            onPressed: selected == null ? null : _confirmDeleteAll,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: _buildBody(),
      floatingActionButton:
          selected == null
              ? FloatingActionButton.extended(
                onPressed: authenticating ? null : _addAccount,
                backgroundColor: widget.pureBlack ? Colors.white : Colors.black,
                foregroundColor: widget.pureBlack ? Colors.black : Colors.white,
                icon: const Icon(Icons.add),
                label: Text(
                  authenticating
                      ? tr('Signing in...', 'جاري تسجيل الدخول...')
                      : tr('Add email', 'إضافة بريد إلكتروني'),
                ),
              )
              : null,
    );
  }

  Widget _buildBody() {
    if (loading && messages.isEmpty) {
      return Center(child: Text(tr('Loading...', 'جاري التحميل...')));
    }

    if (account == null) {
      return Center(
        child: Text(
          tr('Add a Google account to start.', 'أضف حساب Google للبدء.'),
          textAlign: TextAlign.center,
        ),
      );
    }

    if (messages.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          children: <Widget>[
            const SizedBox(height: 220),
            Center(child: Text(tr('No messages', 'لا توجد رسائل'))),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        itemCount: messages.length,
        itemBuilder:
            (BuildContext context, int index) => _messageTile(messages[index]),
      ),
    );
  }

  Widget _messageTile(MailMessage message) {
    final String subject =
        message.subject == '(No subject)'
            ? tr('(No subject)', '(بدون موضوع)')
            : message.subject;

    return ListTile(
      title: Text(message.sender, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(subject, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: IconButton(
        tooltip: tr('Delete message', 'حذف الرسالة'),
        onPressed: () => _deleteMessage(message),
        icon: const Icon(Icons.delete_outline),
      ),
      onTap:
          () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder:
                  (_) => MessagePage(message: message, locale: widget.locale),
            ),
          ),
    );
  }

  void _accountPopup() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: widget.pureBlack ? Colors.black : Colors.white,
      builder: (BuildContext context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (account != null)
                ListTile(
                  leading: AccountAvatar(account: account),
                  title: Text(account!.email),
                  subtitle: Text(tr('Current account', 'الحساب الحالي')),
                ),
              ...accounts.map(
                (MailAccount item) => ListTile(
                  leading: AccountAvatar(account: item),
                  title: Text(item.email),
                  selected: item.email == account?.email,
                  onTap: () => _selectAccount(item),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.add),
                title: Text(tr('Add email', 'إضافة بريد إلكتروني')),
                onTap: () {
                  Navigator.pop(context);
                  unawaited(_addAccount());
                },
              ),
              ListTile(
                leading: const Icon(Icons.settings_outlined),
                title: Text(tr('Settings', 'الإعدادات')),
                onTap: () {
                  Navigator.pop(context);
                  _settings();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _confirmDeleteAll() {
    showDialog<void>(
      context: context,
      builder:
          (BuildContext context) => AlertDialog(
            title: Text(tr('Delete all messages?', 'حذف كل الرسائل؟')),
            content: Text(
              tr(
                'Do you want to delete all the messages?',
                'هل تريد حذف كل الرسائل؟',
              ),
            ),
            actions: <Widget>[
              TextButton(
                style: TextButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.pop(context),
                child: Text(tr('Cancel', 'إلغاء')),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  Navigator.pop(context);
                  unawaited(_deleteAll());
                },
                child: Text(tr('Delete', 'حذف')),
              ),
            ],
          ),
    );
  }

  void _settings() {
    Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder:
            (_) => SettingsPage(
              locale: widget.locale,
              pureBlack: widget.pureBlack,
              notificationsOn: widget.notificationsOn,
              onTheme: widget.onTheme,
              onLanguage: widget.onLanguage,
              onNotifications: widget.onNotifications,
              onSignOut: _signOut,
            ),
      ),
    );
  }
}

class AccountAvatar extends StatelessWidget {
  const AccountAvatar({super.key, required this.account, this.radius = 20});

  final MailAccount? account;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final String fallback =
        account?.email.trim().isNotEmpty == true
            ? account!.email.trim()[0].toUpperCase()
            : 'M';

    if (account?.photoUrl != null && account!.photoUrl!.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundImage: NetworkImage(account!.photoUrl!),
      );
    }

    return CircleAvatar(
      radius: radius,
      backgroundColor: Theme.of(context).colorScheme.onSurface,
      foregroundColor: Theme.of(context).colorScheme.surface,
      child: Text(
        fallback,
        style: TextStyle(fontSize: radius, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class MessagePage extends StatelessWidget {
  const MessagePage({super.key, required this.message, required this.locale});

  final MailMessage message;
  final Locale locale;

  String tr(String en, String ar) => locale.languageCode == 'ar' ? ar : en;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mail')),
      body: SelectionArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: <Widget>[
            Text(
              message.subject == '(No subject)'
                  ? tr('(No subject)', '(بدون موضوع)')
                  : message.subject,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            SelectableText(message.sender),
            const SizedBox(height: 20),
            SelectableText(
              message.body.isEmpty
                  ? tr('(No text)', '(بدون نص)')
                  : message.body,
            ),
          ],
        ),
      ),
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.locale,
    required this.pureBlack,
    required this.notificationsOn,
    required this.onTheme,
    required this.onLanguage,
    required this.onNotifications,
    required this.onSignOut,
  });

  final Locale locale;
  final bool pureBlack;
  final bool notificationsOn;
  final ValueChanged<bool> onTheme;
  final ValueChanged<Locale> onLanguage;
  final ValueChanged<bool> onNotifications;
  final VoidCallback onSignOut;

  String tr(String en, String ar) => locale.languageCode == 'ar' ? ar : en;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Settings', 'الإعدادات'))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          Text(
            tr('Color', 'اللون'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          RadioGroup<bool>(
            groupValue: pureBlack,
            onChanged: (bool? value) {
              if (value != null) {
                onTheme(value);
              }
            },
            child: Column(
              children: <Widget>[
                ListTile(
                  leading: const Radio<bool>(value: true),
                  title: Text(tr('Pure Black', 'أسود نقي')),
                  onTap: () => onTheme(true),
                ),
                ListTile(
                  leading: const Radio<bool>(value: false),
                  title: Text(tr('White', 'أبيض')),
                  onTap: () => onTheme(false),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            title: Text(tr('Notifications', 'الإشعارات')),
            value: notificationsOn,
            onChanged: onNotifications,
          ),
          const SizedBox(height: 16),
          Text(
            tr('Language', 'اللغة'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          RadioGroup<String>(
            groupValue: locale.languageCode,
            onChanged: (String? value) {
              if (value != null) {
                onLanguage(Locale(value));
              }
            },
            child: Column(
              children: <Widget>[
                ListTile(
                  leading: const Radio<String>(value: 'ar'),
                  title: const Text('العربية'),
                  onTap: () => onLanguage(const Locale('ar')),
                ),
                ListTile(
                  leading: const Radio<String>(value: 'en'),
                  title: const Text('English'),
                  onTap: () => onLanguage(const Locale('en')),
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: onSignOut,
            child: Text(tr('Sign out', 'تسجيل الخروج')),
          ),
        ],
      ),
    );
  }
}
