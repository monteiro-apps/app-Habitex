import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:habitex/pages/login_page.dart';
import 'package:habitex/services/auth_service.dart';

const _iosBlue = Color(0xFF007AFF);
const _iosBg = Color(0xFFF2F2F7);
const _iosGray = Color(0xFF8E8E93);

class SplashPage extends StatefulWidget {
  const SplashPage({super.key, required this.app, this.onAuthenticated});

  final Widget app;
  final Future<void> Function()? onAuthenticated;

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  final _auth = AuthService();

  @override
  void initState() {
    super.initState();
    _verificarSessao();
  }

  Future<void> _verificarSessao() async {
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    final logado = await _auth.isLogado();
    if (logado) {
      await widget.onAuthenticated?.call();
    }
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      CupertinoPageRoute<void>(
        builder: (_) => logado
            ? widget.app
            : LoginPage(
                nextPage: widget.app,
                onAuthenticated: widget.onAuthenticated,
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: _iosBg,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'HABITEX',
              style: TextStyle(
                color: _iosBlue,
                fontSize: 36,
                fontWeight: FontWeight.w900,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'sua rotina, seus hábitos',
              style: TextStyle(
                color: _iosGray,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
