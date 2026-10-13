import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

// v0: autenticação simulada com shared_preferences (sem banco de dados)
// v1: substituir o conteúdo de cada método pelo equivalente do Firebase Auth
//     sem alterar nenhuma tela ou chamada externa.
class AuthService {
  static const _keyEmail = 'habitex.auth.email';
  static const _keySenha = 'habitex.auth.senha';
  static const _keySenhaSalt = 'habitex.auth.senhaSalt';
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
      // v0: mantém apenas hash com salt da credencial local do protótipo.
      // v1: remover estas chaves; Firebase Auth gerencia a credencial.
      await _savePasswordHash(prefs, senha);
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
      final apelido = prefs.getString(_keyApelido) ?? '';

      if (email.trim().toLowerCase() != emailSalvo ||
          !await _passwordMatches(prefs, senha)) {
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

  // v0: atualiza apelido/e-mail da identidade local e espelha no perfil.
  // v1: substituir por → FirebaseAuth.currentUser.updateEmail(...)
  //                       + atualização do perfil no Firestore.
  Future<AuthResult> atualizarPerfil({
    required String apelido,
    required String email,
  }) async {
    final nickname = apelido.trim();
    final normalizedEmail = email.trim().toLowerCase();
    if (nickname.isEmpty) return AuthResult.erro('Informe um apelido.');
    if (!normalizedEmail.contains('@') || !normalizedEmail.contains('.')) {
      return AuthResult.erro('Informe um e-mail válido.');
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyApelido, nickname);
      await prefs.setString(_keyEmail, normalizedEmail);
      await _syncProfilePrefs(
        prefs: prefs,
        apelido: nickname,
        email: normalizedEmail,
      );
      return AuthResult.sucesso(apelido: nickname, email: normalizedEmail);
    } catch (_) {
      return AuthResult.erro('Não foi possível atualizar o perfil.');
    }
  }

  // v0: valida a credencial local atual e substitui pela nova senha.
  // v1: substituir por → reautenticar usuário + updatePassword(...).
  Future<AuthResult> alterarSenha({
    required String senhaAtual,
    required String novaSenha,
  }) async {
    if (senhaAtual.isEmpty) return AuthResult.erro('Informe a senha atual.');
    if (novaSenha.length < 6) {
      return AuthResult.erro('A nova senha deve ter no mínimo 6 caracteres.');
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!await _passwordMatches(prefs, senhaAtual)) {
        return AuthResult.erro('Senha atual incorreta.');
      }
      // v0: substitui somente o hash local com um salt novo.
      // v1: substituir por → FirebaseAuth.currentUser.updatePassword(...).
      await _savePasswordHash(prefs, novaSenha);
      return AuthResult.sucesso(
        apelido: prefs.getString(_keyApelido) ?? '',
        email: prefs.getString(_keyEmail) ?? '',
      );
    } catch (_) {
      return AuthResult.erro('Não foi possível alterar a senha.');
    }
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

  Future<void> _savePasswordHash(
    SharedPreferences prefs,
    String password,
  ) async {
    final random = Random.secure();
    final salt = base64UrlEncode(
      List<int>.generate(24, (_) => random.nextInt(256)),
    );
    await prefs.setString(_keySenhaSalt, salt);
    await prefs.setString(_keySenha, _hashPassword(password, salt));
  }

  Future<bool> _passwordMatches(
    SharedPreferences prefs,
    String password,
  ) async {
    final saved = prefs.getString(_keySenha) ?? '';
    final salt = prefs.getString(_keySenhaSalt);
    if (salt != null && salt.isNotEmpty) {
      return saved == _hashPassword(password, salt);
    }

    // Migração de contas criadas antes do armazenamento com hash.
    if (saved != password) return false;
    await _savePasswordHash(prefs, password);
    return true;
  }

  String _hashPassword(String password, String salt) {
    return sha256.convert(utf8.encode('$salt:$password')).toString();
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
