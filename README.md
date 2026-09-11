# Habitex

Habitex e um app Flutter para organizar rotina, anotacoes rapidas e habitos em uma experiencia simples, visual e inspirada em interfaces iOS.

O objetivo do app e ajudar a acompanhar pequenas praticas do dia a dia: criar tarefas, registrar notas e medir o progresso de habitos com metas semanais.

## Funcionalidades

- **Rotina**
  - Criacao de tarefas rapidas.
  - Escolha do dia em que a tarefa sera adicionada.
  - Repeticao da tarefa em mais de um dia da semana.
  - Marcacao de tarefa concluida.
  - Exclusao de tarefas com botao de lixeira.

- **Notas**
  - Criacao de anotacoes rapidas.
  - Edicao de notas existentes.
  - Exibicao em grade com titulo, data e resumo do conteudo.

- **Habitos**
  - Cadastro de habitos com nome, icone, frequencia, meta e unidade.
  - Campo **Registro por toque** para definir quanto cada toque no botao `+` registra.
  - Exemplo: meta de `3000 ml` de agua, com registro de `500 ml` por toque.
  - Controle diario por botao de adicionar/remover progresso.
  - Calendario semanal visual:
    - verde: meta batida;
    - vermelho: pendente;
    - cinza claro: dia livre.
  - Exclusao de habitos ao deslizar o card para o lado, com confirmacao.

## Tecnologias

- Flutter
- Dart
- Shared Preferences para persistencia local
- Material/Cupertino widgets

## Como Rodar

Instale as dependencias:

```bash
flutter pub get
```

Rode o app:

```bash
flutter run
```

Para rodar no Chrome:

```bash
flutter run -d chrome
```

## Qualidade

Formatar o codigo:

```bash
dart format lib test
```

Analisar o projeto:

```bash
flutter analyze
```

Rodar testes:

```bash
flutter test
```

## Estrutura Principal

```text
lib/main.dart          # App, telas, modelos e persistencia local
test/widget_test.dart  # Testes de interface e regras principais
pubspec.yaml           # Configuracao do projeto Flutter
```

## Status

O app esta em desenvolvimento ativo. As proximas melhorias podem incluir edicao de habitos, historico detalhado por dia, melhores filtros por periodo e imagens oficiais das telas.
