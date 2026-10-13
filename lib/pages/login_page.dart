import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:habitex/pages/cadastro_page.dart';
import 'package:habitex/services/auth_service.dart';
import 'package:habitex/theme/habitex_design.dart';
import 'package:habitex/widgets/habitex_auth_field.dart';

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
      backgroundColor: HabitexColors.background,
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
                        color: HabitexColors.primary,
                        fontSize: 32,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'O app que te ajuda a não esquecer de você.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: HabitexColors.textSecondary,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 40),
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
                            color: HabitexColors.primary,
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    CupertinoButton(
                      color: HabitexColors.primary,
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
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                    ),
                    const SizedBox(height: 16),
                    const _DividerOu(),
                    const SizedBox(height: 16),
                    Container(
                      decoration: BoxDecoration(
                        color: HabitexColors.surface,
                        borderRadius: BorderRadius.circular(
                          HabitexRadii.compact,
                        ),
                      ),
                      child: CupertinoButton(
                        borderRadius: BorderRadius.circular(
                          HabitexRadii.compact,
                        ),
                        onPressed: _carregando ? null : _abrirCadastro,
                        child: const Text(
                          'Criar conta',
                          style: TextStyle(
                            color: HabitexColors.primary,
                            fontWeight: FontWeight.w500,
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
        Expanded(child: Divider(color: HabitexColors.surfaceElevated)),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'ou',
            style: TextStyle(
              color: HabitexColors.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(child: Divider(color: HabitexColors.surfaceElevated)),
      ],
    );
  }
}
