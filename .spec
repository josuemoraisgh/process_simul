# Auditoria e Refatoracao Completa — Especificacao

Status: implementacao e integracao concluidas em 2026-07-14, com riscos
residuais externos documentados em `docs/audit/README.md`.

## Objetivo

Auditar e refatorar o simulador Flutter HART/Modbus, preservando toda a
funcionalidade observavel pelo usuario e priorizando, nesta ordem:
desempenho, seguranca e manutenibilidade.

## Baseline

- `flutter analyze`: sem ocorrencias.
- `flutter test`: 33 testes aprovados.
- Camadas atuais: presentation, application/Riverpod, domain, data/SQLite e
  infrastructure para HART, Modbus, simulacao e WebView 3D.
- Efeitos externos: SQLite/WAL, XLSX, SharedPreferences, sockets TCP, porta
  serial, timers, listeners, WebView/JavaScript, FFI Win32 e filesystem.

## Funcionalidade intocavel

- Rotas `/tank3d`, `/hart`, `/modbus`, `/settings` e `/logs`.
- Iniciar/parar TF, HART TCP/serial e Modbus TCP.
- CRUD HART, Modbus, ENUM, BIT_ENUM e comandos.
- Alternancia humano/hex, filtros, ordenacao, logs, camera e fullscreen 3D.
- Importacao/exportacao XLSX e compatibilidade wire para requisicoes validas.
- Modo de teste exclusivo do Modbus: todos os pontos HR, IR, coil e discrete
  input alternam juntos entre 0 e 1 a cada segundo, sem alterar HART, formulas
  ou persistencia; ao desativar, os mapas anteriores sao restaurados.

## Extensibilidade obrigatoria de equipamentos e HART

- Inserir ou remover um equipamento HART e/ou Modbus deve ser um caso de uso
  simples, atomico e independente de widgets, SQL e transportes.
- Equipamentos sao descritos por definicoes/perfis e persistidos por uma porta
  `EquipmentRepository`; a UI apenas envia um comando de aplicacao.
- O modelo atual de pontos Modbus permanece compativel. Como ele nao possui
  identidade explicita de equipamento, a nova camada deve permitir agrupar
  pontos por `EquipmentId`/perfil sem impor uma regra externa nao confirmada.
- Um comando HART deve ser inserido ou removido registrando uma implementacao
  de `HartCommandHandler`; nao deve exigir editar um `switch` monolitico.
- Todos os comandos HART devem receber o mesmo `HartCommandContext` e usar um
  parser/codec compartilhado para campos e payloads.
- Funcoes reutilizaveis de interpretacao devem ser registradas em
  `HartFunctionRegistry` e estar disponiveis a qualquer comando, com tipos,
  limites e erros explicitos.
- O registro deve rejeitar codigos/funcoes duplicados e permitir testes
  unitarios de cada handler sem socket, serial, SQLite ou Riverpod.

## Frentes e entregaveis

1. Desempenho: benchmarks, relatorio e hot paths otimizados.
2. Seguranca: PoCs controladas, relatorio e hardening com testes negativos.
3. Arquitetura: portas segregadas, lifecycle explicito, failures tipadas e
   adaptadores para a API anterior; catalogo de equipamentos e registry de
   comandos/funcoes HART desacoplados.
4. Limpeza: inventario justificado, remocao de duplicacoes e codigo morto
   comprovado, sem remover assets ambiguos.
5. Testes: caracterizacao antes das mudancas, regressao por bug, widgets,
   contratos e integracao, com cobertura publicada.
6. Integracao: versao unica, changelog e guia de migracao antes/depois.

## Contratos entre frentes

- Testes congelam comportamento valido antes de mudancas comportamentais.
- Arquitetura define portas; Desempenho define a implementacao final do motor
  de expressoes, cache, scheduler e parsers quando houver conflito.
- Seguranca define limites e validacoes em conjunto com parsers de alto
  desempenho.
- Limpeza remove apenas depois de contratos e call sites estabilizados.
- Integracao ocorre por ultimo e executa toda a matriz de validacao.

## Criterios globais de conclusao

- Nenhuma funcionalidade observavel removida.
- `flutter analyze` limpo e suite total aprovada tres vezes consecutivas.
- Linhas >= 80%; domain/application/protocolos >= 90%; branches >= 75%.
- Todo achado alto/critico possui teste de regressao.
- Adicionar/remover equipamento nao exige alterar datasource concreto ou UI;
  adicionar/remover comando HART nao exige alterar dispatcher central.
- Um comando HART de fixture consegue usar uma funcao registrada no parser
  comum e ser registrado/removido em teste sem infraestrutura externa.
- Nenhum timer, subscription, socket, serial ou DB permanece vivo apos
  `stop`/`dispose`.
- Buffers e entradas externas possuem limites; importacao invalida e atomica.
- Benchmark do tick/logging demonstra alvo de pelo menos 50% de reducao nas
  avaliacoes/alocacoes do cenario de referencia.
- Changelog, relatorios e guia de migracao entregues.

## Ordem de integracao

`baseline -> caracterizacao -> contratos -> desempenho/seguranca -> limpeza -> regressao -> integracao`

## Resultado final verificado

- `flutter analyze`: sem ocorrencias.
- `flutter test --coverage`: 179/179 aprovados.
- Cobertura de linhas instrumentadas: 5083/5083 = 100% apos inclusao do modo
  de teste Modbus.
- 51 arquivos Dart auditados: 46 possuem linhas executaveis e estao no LCOV;
  5 contem somente constantes, enums ou contratos abstratos e nao geram `DA`.
- Domain, application, infrastructure, data, presentation e bootstrap: 100%
  das linhas executaveis instrumentadas.
- LCOV desta ferramenta nao registrou branches (`BRF/BRH` ausentes), portanto
  cobertura de branches continua nao mensuravel nesta configuracao.
- Registry HART, parser/funcoes comuns e catalogo persistente HART/Modbus/misto
  estao ligados ao runtime e protegidos por testes de socket/SQLite.
- Remover comando HART padrao cria bloqueio explicito contra o fallback legado;
  o comando so volta a executar apos novo registro.

## Ambiguidades bloqueadas contra suposicao

- Regras PACTware/HART para address 0 e fallback de dispositivo.
- Exposicao LAN desejada e eventual politica de acesso.
- Schema oficial de custom commands e compatibilidade XLSX externa.
- Identidade, unit-id e fronteiras de um "equipamento Modbus" no dominio atual.
- Semantica exata das funcoes configuraveis usadas por comandos HART.
- Plataformas oficialmente suportadas e testes que exigem hardware serial/3D.
- Uso externo de assets e propriedades publicas aparentemente mortas.

Na ausencia de resposta, comportamentos ambiguos permanecem preservados por
adaptador ou sao desabilitados apenas quando representam risco e existe modo
legado explicito, opt-in e documentado.
