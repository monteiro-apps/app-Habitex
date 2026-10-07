import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:habitex/pages/cadastro_page.dart';
import 'package:habitex/services/auth_service.dart';

const _iosBlue = Color(0xFF007AFF);
const _iosBg = Color(0xFFF2F2F7);
const _iosCard = Color(0xFFFFFFFF);
const _iosGray = Color(0xFF8E8E93);

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.nextPage, this.onAuthenticated});

  final Widget nextPage;
  final Future<void> Function()? onAuthenticated;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _auth = AuthService();
  final _emailController = TextEditingController();
  final _senhaController = TextEditingController();
  final _recuperacaoEmailController = TextEditingController();
  bool _carregando = false;
  bool _senhaVisivel = false;

  @override
  void dispose() {
    _emailController.dispose();
    _senhaController.dispose();
    _recuperacaoEmailController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() => _carregando = true);
    final result = await _auth.login(
      email: _emailController.text,
      senha: _senhaController.text,
    );
    if (!mounted) return;
    setState(() => _carregando = false);

    if (result.sucesso) {
      await _abrirApp();
    } else {
      _mostrarAlerta(result.erro ?? 'Erro ao entrar.');
    }
  }

  Future<void> _abrirApp() async {
    await widget.onAuthenticated?.call();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      CupertinoPageRoute<void>(builder: (_) => widget.nextPage),
    );
  }

  Future<void> _esqueciSenha(String email) async {
    final result = await _auth.esqueceuSenha(email: email);
    if (!mounted) return;
    _mostrarAlerta(result.mensagem ?? result.erro ?? 'Tente novamente.');
  }

  void _abrirRecuperacaoSenha() {
    _recuperacaoEmailController.text = _emailController.text;
    showCupertinoDialog<void>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('Esqueci minha senha'),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: CupertinoTextField(
            controller: _recuperacaoEmailController,
            keyboardType: TextInputType.emailAddress,
            placeholder: 'seu@email.com',
            autocorrect: false,
            textInputAction: TextInputAction.done,
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () {
              final email = _recuperacaoEmailController.text;
              Navigator.pop(dialogContext);
              _esqueciSenha(email);
            },
            child: const Text('Enviar'),
          ),
        ],
      ),
    );
  }

  void _mostrarAlerta(String mensagem) {
    showCupertinoDialog<void>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('HABITEX'),
        content: Text(mensagem),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _abrirCadastro() {
    Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (_) => CadastroPage(
          nextPage: widget.nextPage,
          onAuthenticated: widget.onAuthenticated,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _iosBg,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 60),
                    const Text(
                      'HABITEX',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _iosBlue,
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'O app que te ajuda a não esquecer de você.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _iosGray,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 40),
                    _AuthField(
                      label: 'E-MAIL',
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      enabled: !_carregando,
                    ),
                    const SizedBox(height: 12),
                    _AuthField(
                      label: 'SENHA',
                      controller: _senhaController,
                      obscureText: !_senhaVisivel,
                      enabled: !_carregando,
                      suffixIcon: _PasswordVisibilityButton(
                        visible: _senhaVisivel,
                        onTap: () =>
                            setState(() => _senhaVisivel = !_senhaVisivel),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: CupertinoButton(
                        minimumSize: Size.zero,
                        padding: EdgeInsets.zero,
                        onPressed: _carregando ? null : _abrirRecuperacaoSenha,
                        child: const Text(
                          'Esqueci minha senha',
                          style: TextStyle(
                            color: _iosBlue,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    CupertinoButton(
                      color: _iosBlue,
                      borderRadius: BorderRadius.circular(12),
                      onPressed: _carregando ? null : _login,
                      child: _carregando
                          ? const CupertinoActivityIndicator(
                              color: Colors.white,
                            )
                          : const Text(
                              'Entrar',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                    const SizedBox(height: 16),
                    const _DividerOu(),
                    const SizedBox(height: 16),
                    Container(
                      decoration: BoxDecoration(
                        color: _iosCard,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: CupertinoButton(
                        borderRadius: BorderRadius.circular(12),
                        onPressed: _carregando ? null : _abrirCadastro,
                        child: const Text(
                          'Criar conta',
                          style: TextStyle(
                            color: _iosBlue,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _DividerOu extends StatelessWidget {
  const _DividerOu();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(child: Divider(color: Color(0xFFD1D1D6))),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'ou',
            style: TextStyle(
              color: _iosGray,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(child: Divider(color: Color(0xFFD1D1D6))),
      ],
    );
  }
}

class _AuthField extends StatelessWidget {
  const _AuthField({
    required this.label,
    required this.controller,
    this.keyboardType,
    this.obscureText = false,
    this.enabled = true,
    this.suffixIcon,
  });

  final String label;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final bool obscureText;
  final bool enabled;
  final Widget? suffixIcon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _iosCard,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: _iosGray,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  enabled: enabled,
                  keyboardType: keyboardType,
                  obscureText: obscureText,
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                  ),
                ),
              ),
              if (suffixIcon != null) ...[
                const SizedBox(width: 8),
                suffixIcon!,
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _PasswordVisibilityButton extends StatelessWidget {
  const _PasswordVisibilityButton({required this.visible, required this.onTap});

  final bool visible;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(
          visible ? CupertinoIcons.eye_slash : CupertinoIcons.eye,
          color: _iosGray,
          size: 20,
        ),
      ),
    );
  }
}
