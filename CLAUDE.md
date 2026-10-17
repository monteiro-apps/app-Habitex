# HABITEX — Contexto do projeto

App Flutter de rotina, notas e hábitos, com visual iOS (Cupertino) e tema escuro. Desenvolvido por Jennyffer para uso pessoal e, depois, lançamento no TestFlight e nas lojas.

Este arquivo define como trabalhar neste repositório. Leia antes de qualquer alteração.

---

## Stack e estado atual

- Flutter (Dart), testado em iPhone físico (iPhone 13 e iOS 27 beta) e no simulador iOS.
- Persistência local com `shared_preferences`. O Firebase ainda NÃO está integrado.
- Estado global em `HabitexStore` (repositório de dados). Ele notifica a UI por um callback `onChanged`, não por `ChangeNotifier`.
- Autenticação simulada em `AuthService` (local). Comentários `// v0` e `// v1` marcam o que muda na migração para o Firebase.
- Dark mode é o padrão visual. Light mode existe no código, mas não é prioridade.

---

## Estrutura

- `lib/` — código do app. Verifique a estrutura atual antes de criar arquivos novos, porque o `main.dart` pode ter sido dividido em arquivos menores.
- `ios/` — projeto iOS. Não alterar configurações de assinatura (Team, Bundle ID `com.jennyffer.habitex`) sem pedir.
- `android/` — ainda não é prioridade. Não adaptar sem pedido explícito.

---

## Telas principais

- **Perfil** (tela inicial): saudação, resumo semanal, top hábito e lembretes de hoje.
- **Lembretes**: tarefas com data, horário e recorrência.
- **Hábitos**: progresso do dia, edição, calendário semanal.
- **Notas**: cards em grid, editor em modal.
- **Dados Gerais** (drawer): Perfil, Estatísticas, Notificações, Exportar Dados, Assinatura Premium, Sair.

### Telas em standby (desabilitadas, não excluir)

Login, cadastro (com a splash de verificação de sessão) e Habitex Premium estão desabilitados até o app ser validado pelos usuários. Eles vão voltar depois, então **não exclua esse código**.

- Controle pela constante `contasHabilitadas` em `lib/main.dart` (hoje `false`). Para reativar, troque para `true`.
- Com `false`: o app abre direto na aba Perfil, e ficam ocultos a seção ASSINATURA e o botão "Sair da conta" no drawer, além da seção SEGURANÇA ("Alterar senha") em Meu perfil.
- O e-mail continua obrigatório para salvar o perfil.
- Os testes que dependem dessas telas usam `skip: !contasHabilitadas` e voltam a rodar quando a flag for reativada.

---

## Regras de produto: lembretes (obrigatórias)

Estas regras já foram decididas. Não mude o comportamento sem pedido explícito.

- **A.** Tarefa rápida (campo "Adicionar tarefa rápida") sempre cria lembrete único no dia selecionado na barra da semana. Ela não tem seletor de dias nem opção de repetir.
- **B.** Lembrete único aparece só no dia marcado. Não aparece nos dias seguintes nem nas próximas semanas. Para vê-lo depois, o usuário volta pelas setas do calendário até a semana dele.
- **C.** Recorrência pode ser criada de duas formas:
  - pelo botão "Novo lembrete", com a opção "Repetir";
  - editando um lembrete já criado (arrastar o item abre o formulário) e trocando para "Repetir".
- **D.** Lembretes nunca são apagados por causa dessas regras. As tarefas rápidas antigas, que eram recorrentes e sem data, são convertidas em únicas ao carregar o app (`_migrateLegacyQuickTasks`).

Se alguma tarefa conflitar com essas regras, pare e pergunte antes de implementar.

---

## Regras de código

**Estado e persistência**
- Ao alterar dados, chame `onChanged()` antes de `await _save(...)`, para a UI responder imediatamente.
- Não coloque `save()` dentro de `dispose()`.
- Não acesse `shared_preferences` diretamente nas telas. Use os métodos do `HabitexStore` ou do `AuthService`.
- Ao editar um hábito, preserve sempre o `id`. O histórico de progresso depende dele.

**Tema e cores**
- Nunca use cores brancas ou pretas fixas em cards, fundos e textos. Use `Theme.of(context).colorScheme` e `scaffoldBackgroundColor`.
- Cores semânticas fixas permitidas: `iosBlue`, `iosGreen`, `iosRed`, `iosOrange`, `iosGray`.
- Paleta principal: azul `#007AFF`. Fundo preto `#000000`. Cards `#1C1C1E`.

**Responsividade**
- Não use valores fixos para fontes, padding e alturas que dependam da largura da tela. Use proporções de `MediaQuery.of(context).size.width`.
- Teste em pelo menos dois tamanhos (iPhone SE e um modelo grande) antes de dar uma tarefa por concluída.

**Estilo**
- Visual minimalista: pouco negrito, sem gradientes exagerados, sem emojis decorativos.
- Comentários de código em português.
- Mensagens de erro para o usuário em português, em `CupertinoAlertDialog`, não em `SnackBar`.

---

## Como verificar uma alteração

Antes de dar uma tarefa por concluída:

1. `flutter analyze` sem erros.
2. `flutter test` passando.
3. Hot restart (`R`) no terminal ao mudar modelos, classes ou ThemeData. Hot reload (`r`) só serve para mudanças visuais simples.
4. Se a mudança afetar a UI, peça para eu validar com print do iPhone.

---

## Limites

- Não execute `git push`, não apague arquivos do usuário e não rode `flutter clean` sem perguntar.
- Não adicione dependências novas sem explicar o motivo e pedir confirmação.
- Não altere preços, textos legais ou links de Termos e Política sem pedido explícito.
- Não crie integrações de pagamento reais. A tela de assinatura é só interface.
- Não implemente Firebase antes de o usuário pedir explicitamente a etapa.

---

## Ao terminar uma tarefa

Informe:
- quais arquivos foram alterados
- o que mudou em uma ou duas frases
- o resultado do `flutter analyze` e dos testes
- qualquer pendência ou decisão que o usuário precisa tomar
