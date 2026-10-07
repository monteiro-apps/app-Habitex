import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:habitex/services/auth_service.dart';

const _iosBlue = Color(0xFF007AFF);
const _iosBg = Color(0xFFF2F2F7);
const _iosCard = Color(0xFFFFFFFF);
const _iosGray = Color(0xFF8E8E93);

class CadastroPage extends StatefulWidget {
  const CadastroPage({super.key, required this.nextPage, this.onAuthenticated});

  final Widget nextPage;
  final Future<void> Function()? onAuthenticated;

  @override
  State<CadastroPage> createState() => _CadastroPageState();
}

class _CadastroPageState extends State<CadastroPage> {
  final _auth = AuthService();
  final _apelidoController = TextEditingController();
  final _emailController = TextEditingController();
  final _senhaController = TextEditingController();
  final _confirmarSenhaController = TextEditingController();
  bool _carregando = false;
  bool _senhaVisivel = false;
  bool _confirmarSenhaVisivel = false;

  @override
  void dispose() {
    _apelidoController.dispose();
    _emailController.dispose();
    _senhaController.dispose();
    _confirmarSenhaController.dispose();
    super.dispose();
  }

  Future<void> _cadastrar() async {
    final apelido = _apelidoController.text.trim();
    final email = _emailController.text.trim();
    final senha = _senhaController.text;
    final confirmarSenha = _confirmarSenhaController.text;

    if (apelido.isEmpty) {
      _mostrarAlerta('Informe um apelido.');
      return;
    }
    if (!email.contains('@')) {
      _mostrarAlerta('E-mail inválido.');
      return;
    }
    if (senha.length < 6) {
      _mostrarAlerta('Senha com mínimo 6 caracteres.');
      return;
    }
    if (senha != confirmarSenha) {
      _mostrarAlerta('As senhas não coincidem.');
      return;
    }

    setState(() => _carregando = true);
    final result = await _auth.cadastrar(
      apelido: apelido,
      email: email,
      senha: senha,
    );
    if (!mounted) return;
    setState(() => _carregando = false);

    if (result.sucesso) {
      await widget.onAuthenticated?.call();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        CupertinoPageRoute<void>(builder: (_) => widget.nextPage),
        (_) => false,
      );
    } else {
      _mostrarAlerta(result.erro ?? 'Erro ao cadastrar.');
    }
  }

  void _mostrarAlerta(String mensagem) {
    showCupertinoDialog<void>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Cadastro'),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _iosBg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: () => Navigator.pop(context),
                  child: const Icon(
                    CupertinoIcons.chevron_left,
                    color: _iosBlue,
                    size: 26,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Criar conta',
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Preencha seus dados para começar',
                style: TextStyle(
                  color: _iosGray,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 32),
              _CadastroField(
                label: 'APELIDO',
                controller: _apelidoController,
                enabled: !_carregando,
              ),
              const SizedBox(height: 12),
              _CadastroField(
                label: 'E-MAIL',
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                enabled: !_carregando,
              ),
              const SizedBox(height: 12),
              _CadastroField(
                label: 'SENHA',
                controller: _senhaController,
                obscureText: !_senhaVisivel,
                enabled: !_carregando,
                suffixIcon: _PasswordVisibilityButton(
                  visible: _senhaVisivel,
                  onTap: () => setState(() => _senhaVisivel = !_senhaVisivel),
                ),
              ),
              const SizedBox(height: 12),
              _CadastroField(
                label: 'CONFIRMAR SENHA',
                controller: _confirmarSenhaController,
                obscureText: !_confirmarSenhaVisivel,
                enabled: !_carregando,
                suffixIcon: _PasswordVisibilityButton(
                  visible: _confirmarSenhaVisivel,
                  onTap: () => setState(
                    () => _confirmarSenhaVisivel = !_confirmarSenhaVisivel,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Ao criar sua conta, você concorda com nossos Termos de Uso',
                style: TextStyle(
                  color: _iosGray,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 24),
              CupertinoButton(
                color: _iosBlue,
                borderRadius: BorderRadius.circular(12),
                onPressed: _carregando ? null : _cadastrar,
                child: _carregando
                    ? const CupertinoActivityIndicator(color: Colors.white)
                    : const Text(
                        'Criar conta',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CadastroField extends StatelessWidget {
  const _CadastroField({
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
