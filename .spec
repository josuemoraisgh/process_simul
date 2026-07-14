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
- `flutter test`: 96/96 aprovados; matriz de integracao aprovada tres vezes
  antes da ampliacao final de cobertura, e suite final de cobertura aprovada.
- Cobertura de linhas instrumentadas: 2014/2362 = 85,27%.
- `HartTransmitter`: 346/350 = 98,86%.
- `SqliteDatasource`: 495/513 = 96,49%.
- Domain: 83,14%; application: 66,17%; infrastructure: 87,17%; data:
  86,81%. O alvo global de 80% foi atingido; os alvos aspiracionais de 90% por
  camada nao foram atingidos em application/domain e ficam registrados, sem
  alegacao de cobertura inexistente.
- LCOV desta ferramenta nao registrou branches (`BRF/BRH` ausentes), portanto
  a meta de branches nao pode ser comprovada nesta execucao.
- Registry HART, parser/funcoes comuns e catalogo persistente HART/Modbus/misto
  estao ligados ao runtime e protegidos por testes de socket/SQLite.

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
