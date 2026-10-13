import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:habitex/pages/login_page.dart';
import 'package:habitex/services/auth_service.dart';
import 'package:habitex/theme/habitex_design.dart';

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
      backgroundColor: HabitexColors.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'HABITEX',
              style: TextStyle(
                color: HabitexColors.primary,
                fontSize: 36,
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'sua rotina, seus hábitos',
              style: TextStyle(
                color: HabitexColors.textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
