import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:habitex/services/auth_service.dart';
import 'package:habitex/theme/habitex_design.dart';
import 'package:habitex/widgets/habitex_auth_field.dart';

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
      backgroundColor: HabitexColors.background,
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
                    color: HabitexColors.primary,
                    size: 26,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Criar conta',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Preencha seus dados para começar',
                style: TextStyle(
                  color: HabitexColors.textSecondary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 32),
              HabitexAuthField(
                label: 'APELIDO',
                controller: _apelidoController,
                enabled: !_carregando,
              ),
              const SizedBox(height: 12),
              HabitexAuthField(
                label: 'E-MAIL',
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                enabled: !_carregando,
              ),
              const SizedBox(height: 12),
              HabitexAuthField(
                label: 'SENHA',
                controller: _senhaController,
                obscureText: !_senhaVisivel,
                enabled: !_carregando,
                suffixIcon: HabitexPasswordVisibilityButton(
                  visible: _senhaVisivel,
                  onTap: () => setState(() => _senhaVisivel = !_senhaVisivel),
                ),
              ),
              const SizedBox(height: 12),
              HabitexAuthField(
                label: 'CONFIRMAR SENHA',
                controller: _confirmarSenhaController,
                obscureText: !_confirmarSenhaVisivel,
                enabled: !_carregando,
                suffixIcon: HabitexPasswordVisibilityButton(
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
                  color: HabitexColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 24),
              CupertinoButton(
                color: HabitexColors.primary,
                borderRadius: BorderRadius.circular(HabitexRadii.compact),
                onPressed: _carregando ? null : _cadastrar,
                child: _carregando
                    ? const CupertinoActivityIndicator(color: Colors.white)
                    : const Text(
                        'Criar conta',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
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
