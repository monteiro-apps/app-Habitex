import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

// v0: autenticação simulada com shared_preferences (sem banco de dados)
// v1: substituir o conteúdo de cada método pelo equivalente do Firebase Auth
//     sem alterar nenhuma tela ou chamada externa.
class AuthService {
  static const _keyEmail = 'habitex.auth.email';
  static const _keySenha = 'habitex.auth.senha';
  static const _keyApelido = 'habitex.auth.apelido';
  static const _keyLogado = 'habitex.auth.logado';

  // v0: lê a flag de sessão salva localmente em shared_preferences.
  // v1: substituir por → FirebaseAuth.instance.currentUser != null
  Future<bool> isLogado() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyLogado) ?? false;
  }

  // v0: valida e salva uma conta local em shared_preferences.
  // v1: substituir por → FirebaseAuth.instance.createUserWithEmailAndPassword(...)
  //                       + Firestore para salvar apelido
  Future<AuthResult> cadastrar({
    required String apelido,
    required String email,
    required String senha,
  }) async {
    try {
      if (apelido.trim().isEmpty) {
        return AuthResult.erro('Informe um apelido.');
      }
      if (!email.contains('@') || !email.contains('.')) {
        return AuthResult.erro('E-mail inválido.');
      }
      if (senha.length < 6) {
        return AuthResult.erro('A senha deve ter no mínimo 6 caracteres.');
      }

      final prefs = await SharedPreferences.getInstance();
      final emailExistente = prefs.getString(_keyEmail) ?? '';
      final emailNormalizado = email.trim().toLowerCase();

      if (emailExistente == emailNormalizado) {
        return AuthResult.erro('Este e-mail já está cadastrado.');
      }

      await prefs.setString(_keyApelido, apelido.trim());
      await prefs.setString(_keyEmail, emailNormalizado);
      // v0: senha em texto puro apenas para protótipo local/offline.
      // v1: não salvar senha; Firebase Auth gerencia credenciais com segurança.
      await prefs.setString(_keySenha, senha);
      await prefs.setBool(_keyLogado, true);
      await _syncProfilePrefs(
        prefs: prefs,
        apelido: apelido.trim(),
        email: emailNormalizado,
      );

      return AuthResult.sucesso(
        apelido: apelido.trim(),
        email: emailNormalizado,
      );
    } catch (_) {
      return AuthResult.erro('Erro ao cadastrar. Tente novamente.');
    }
  }

  // v0: compara email/senha com os dados locais em shared_preferences.
  // v1: substituir por → FirebaseAuth.instance.signInWithEmailAndPassword(...)
  Future<AuthResult> login({
    required String email,
    required String senha,
  }) async {
    try {
      if (email.trim().isEmpty || senha.isEmpty) {
        return AuthResult.erro('Preencha todos os campos.');
      }

      final prefs = await SharedPreferences.getInstance();
      final emailSalvo = prefs.getString(_keyEmail) ?? '';
      final senhaSalva = prefs.getString(_keySenha) ?? '';
      final apelido = prefs.getString(_keyApelido) ?? '';

      if (email.trim().toLowerCase() != emailSalvo || senha != senhaSalva) {
        return AuthResult.erro('E-mail ou senha incorretos.');
      }

      await prefs.setBool(_keyLogado, true);
      await _syncProfilePrefs(
        prefs: prefs,
        apelido: apelido,
        email: emailSalvo,
      );
      return AuthResult.sucesso(apelido: apelido, email: emailSalvo);
    } catch (_) {
      return AuthResult.erro('Erro ao entrar. Tente novamente.');
    }
  }

  // v0: desativa a flag de sessão local e mantém credenciais para login futuro.
  // v1: substituir por → FirebaseAuth.instance.signOut()
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyLogado, false);
  }

  // v0: recupera apelido/email locais do usuário logado.
  // v1: substituir por → FirebaseAuth.instance.currentUser + Firestore
  Future<UsuarioLogado?> getUsuario() async {
    final prefs = await SharedPreferences.getInstance();
    final logado = prefs.getBool(_keyLogado) ?? false;
    if (!logado) return null;
    return UsuarioLogado(
      apelido: prefs.getString(_keyApelido) ?? '',
      email: prefs.getString(_keyEmail) ?? '',
    );
  }

  // v0: simula envio e apenas valida o e-mail, sem servidor.
  // v1: substituir por → FirebaseAuth.instance.sendPasswordResetEmail(email: email)
  Future<AuthResult> esqueceuSenha({required String email}) async {
    if (!email.contains('@') || !email.contains('.')) {
      return AuthResult.erro('Informe um e-mail válido.');
    }
    return AuthResult.sucesso(
      apelido: '',
      email: email,
      mensagem:
          'Se este e-mail estiver cadastrado, você receberá as instruções.',
    );
  }

  // v0: espelha os dados de auth nas chaves de perfil usadas pela UI atual.
  // v1: substituir por → leitura do perfil do Firestore após autenticação.
  Future<void> _syncProfilePrefs({
    required SharedPreferences prefs,
    required String apelido,
    required String email,
  }) async {
    await prefs.setString('habitex.apelido', apelido);
    await prefs.setString('habitex.email', email);
    await prefs.setString(
      'habitex.profile',
      jsonEncode({'nickname': apelido, 'email': email}),
    );
  }
}

class AuthResult {
  AuthResult._({
    required this.sucesso,
    this.erro,
    this.apelido,
    this.email,
    this.mensagem,
  });

  final bool sucesso;
  final String? erro;
  final String? apelido;
  final String? email;
  final String? mensagem;

  factory AuthResult.sucesso({
    required String apelido,
    required String email,
    String? mensagem,
  }) {
    return AuthResult._(
      sucesso: true,
      apelido: apelido,
      email: email,
      mensagem: mensagem,
    );
  }

  factory AuthResult.erro(String mensagem) {
    return AuthResult._(sucesso: false, erro: mensagem);
  }
}

class UsuarioLogado {
  const UsuarioLogado({required this.apelido, required this.email});

  final String apelido;
  final String email;
}
