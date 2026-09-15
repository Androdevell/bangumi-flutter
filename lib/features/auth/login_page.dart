import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/auth/auth_models.dart';
import '../../core/auth/auth_service.dart';
import '../../widgets/common.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.authService});

  final AuthService authService;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _captchaController = TextEditingController();

  LoginChallenge? _challenge;
  Uint8List? _captcha;
  String? _error;
  bool _loading = true;
  bool _submitting = false;
  bool _passwordVisible = false;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController
      ..clear()
      ..dispose();
    _captchaController
      ..clear()
      ..dispose();
    super.dispose();
  }

  Future<void> _prepare() async {
    setState(() {
      _loading = true;
      _error = null;
      _captcha = null;
      _captchaController.clear();
    });
    try {
      final challenge = await widget.authService.beginLogin();
      if (!mounted) return;
      if (widget.authService.isLoggedIn) {
        Navigator.of(context).pop(true);
        return;
      }
      final captcha = await widget.authService.loadCaptcha();
      if (!mounted) return;
      setState(() {
        _challenge = challenge;
        _captcha = captcha;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _loading = false;
      });
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false) || _challenge == null) {
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.authService.login(
        email: _emailController.text,
        password: _passwordController.text,
        captcha: _captchaController.text,
        challenge: _challenge!,
      );
      _passwordController.clear();
      _captchaController.clear();
      if (mounted) Navigator.of(context).pop(true);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _submitting = false;
      });
      await _refreshCaptcha();
    }
  }

  Future<void> _refreshCaptcha() async {
    try {
      final challenge = await widget.authService.beginLogin();
      final captcha = await widget.authService.loadCaptcha();
      if (!mounted) return;
      setState(() {
        _challenge = challenge;
        _captcha = captcha;
        _captchaController.clear();
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error');
    }
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? '此项不能为空' : null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('登录 Bangumi')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child:
                    _loading
                        ? const Padding(
                          key: ValueKey('loading'),
                          padding: EdgeInsets.all(48),
                          child: Center(child: CircularProgressIndicator()),
                        )
                        : _buildForm(context),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    if (_challenge == null && _error != null) {
      return NetworkErrorView(
        key: const ValueKey('error'),
        error: AuthException(_error!),
        onRetry: _prepare,
      );
    }
    return AutofillGroup(
      key: const ValueKey('form'),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              Icons.account_circle_outlined,
              size: 56,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 18),
            TextFormField(
              controller: _emailController,
              autofillHints: const [
                AutofillHints.email,
                AutofillHints.username,
              ],
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              validator: _required,
              decoration: const InputDecoration(
                labelText: '邮箱',
                prefixIcon: Icon(Icons.mail_outline_rounded),
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _passwordController,
              autofillHints: const [AutofillHints.password],
              obscureText: !_passwordVisible,
              textInputAction: TextInputAction.next,
              validator: _required,
              decoration: InputDecoration(
                labelText: '密码',
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  tooltip: _passwordVisible ? '隐藏密码' : '显示密码',
                  onPressed:
                      () =>
                          setState(() => _passwordVisible = !_passwordVisible),
                  icon: Icon(
                    _passwordVisible
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _captchaController,
                    textInputAction: TextInputAction.done,
                    validator: _required,
                    onFieldSubmitted: (_) => _submitting ? null : _submit(),
                    decoration: const InputDecoration(
                      labelText: '验证码',
                      prefixIcon: Icon(Icons.verified_user_outlined),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Tooltip(
                  message: '刷新验证码',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: _submitting ? null : _refreshCaptcha,
                    child: Ink(
                      width: 126,
                      height: 56,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child:
                          _captcha == null
                              ? const Icon(Icons.refresh_rounded)
                              : ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.memory(
                                  _captcha!,
                                  fit: BoxFit.fill,
                                ),
                              ),
                    ),
                  ),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _submitting ? null : _submit,
              icon:
                  _submitting
                      ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Icon(Icons.login_rounded),
              label: const Text('登录'),
            ),
          ],
        ),
      ),
    );
  }
}
