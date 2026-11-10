import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../emby/api.dart';
import '../session_controller.dart';
import '../storage/session_store.dart';
import '../theme.dart';
import 'downloads_page.dart';

class LoginInput {
  const LoginInput({
    required this.server,
    required this.username,
    required this.password,
    required this.allowBadCertificate,
  });

  final String server;
  final String username;
  final String password;
  final bool allowBadCertificate;
}

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    return LoginForm(
      banner: session.authMessage,
      savedAccounts: session.accounts,
      onSwitch: (id) => session.switchTo(id),
      onOpenDownloads: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const DownloadsPage()),
        );
      },
      onSubmit: (input) {
        return session.login(
          server: input.server,
          username: input.username,
          password: input.password,
          allowBadCertificate: input.allowBadCertificate,
        );
      },
    );
  }
}

class LoginForm extends StatefulWidget {
  const LoginForm({
    super.key,
    required this.onSubmit,
    this.onOpenDownloads,
    this.banner,
    this.savedAccounts = const [],
    this.onSwitch,
  });

  final Future<void> Function(LoginInput input) onSubmit;
  final VoidCallback? onOpenDownloads;
  final String? banner;
  final List<SavedAccount> savedAccounts;
  final ValueChanged<String>? onSwitch;

  @override
  State<LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<LoginForm> {
  final _server = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  var _obscure = true;
  var _trust = false;
  var _busy = false;
  String? _error;

  @override
  void dispose() {
    _server.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final server = _server.text.trim();
    final username = _username.text.trim();
    if (server.isEmpty || username.isEmpty) {
      setState(() => _error = '请填写服务器地址和用户名');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final navigator = Navigator.of(context);
    try {
      await widget.onSubmit(
        LoginInput(
          server: server,
          username: username,
          password: _password.text,
          allowBadCertificate: _trust,
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
    } finally {
      final leave = mounted && _error == null && navigator.canPop();
      if (mounted && !leave) setState(() => _busy = false);
      if (leave) navigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: brass.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.movie_filter, color: brass),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Emby 下载',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '从你自己的服务器保存原始文件。登录后可以浏览资料库、整季下载，并在本地播放。',
                    style: TextStyle(color: muted, height: 1.45),
                  ),
                  if (widget.banner != null) ...[
                    const SizedBox(height: 16),
                    Text(widget.banner!, style: const TextStyle(color: brass)),
                  ],
                  if (widget.savedAccounts.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Text('已保存的账号', style: TextStyle(fontWeight: FontWeight.w700)),
                    for (final account in widget.savedAccounts)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(account.session.serverName),
                        subtitle: Text(
                          account.needsReauth
                              ? '${account.session.username} · 需要重新登录'
                              : account.session.username,
                        ),
                        trailing: Icon(account.needsReauth ? Icons.key : Icons.swap_horiz),
                        onTap: () {
                          if (!account.needsReauth) {
                            widget.onSwitch?.call(account.id);
                            return;
                          }
                          setState(() {
                            _server.text = account.session.base;
                            _username.text = account.session.username;
                            _trust = account.session.allowBadCertificate;
                            _password.clear();
                            _error = null;
                          });
                        },
                      ),
                  ],
                  const SizedBox(height: 28),
                  TextField(
                    controller: _server,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: '服务器地址',
                      hintText: 'http://192.168.1.10:8096',
                    ),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _username,
                    autocorrect: false,
                    decoration: const InputDecoration(labelText: '用户名'),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    obscureText: _obscure,
                    decoration: InputDecoration(
                      labelText: '密码',
                      helperText: '没有密码的用户可以留空',
                      suffixIcon: IconButton(
                        tooltip: _obscure ? '显示密码' : '隐藏密码',
                        onPressed: () => setState(() => _obscure = !_obscure),
                        icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      ),
                    ),
                    onSubmitted: (_) => _busy ? null : _submit(),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _trust,
                    onChanged: _busy ? null : (value) => setState(() => _trust = value),
                    title: const Text('信任自签名证书'),
                    subtitle: const Text(
                      '只影响登录和浏览。系统下载器不会跳过证书校验，自签名 HTTPS 下载请改用 http，或在系统里信任该证书。',
                      style: TextStyle(color: muted, fontSize: 12, height: 1.35),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(_error!, style: const TextStyle(color: danger, height: 1.35)),
                  ],
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.4),
                          )
                        : const Text('登录'),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: TextButton(
                      onPressed: widget.onOpenDownloads,
                      child: const Text('查看已下载的文件'),
                    ),
                  ),
                  if (width < 700) const SizedBox(height: 12),
                  const Text(
                    '服务器上需要允许这个用户下载媒体。地址可以是局域网 http。',
                    style: TextStyle(color: muted, fontSize: 12, height: 1.4),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
