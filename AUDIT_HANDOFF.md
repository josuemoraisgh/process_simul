# Handoff — Auditoria e Refatoracao

Ultima atualizacao: 2026-07-14, apos fechamento integral da segunda onda.

Este documento e a fonte de continuidade para outro agente. Leia tambem
`.spec` (requisitos/DoD) e `.skill` (protocolo operacional) antes de editar.

## Baseline original

- Worktree estava limpo.
- `flutter analyze`: limpo.
- `flutter test`: 33 testes aprovados.
- Arquitetura original: Flutter/Riverpod, SQLite/Excel, HART TCP/serial,
  Modbus TCP, simulacao TF e viewer 3D/WebView.

## Requisito adicional do usuario

- Inserir/remover equipamento HART e/ou Modbus deve ser maximamente simples e
  desacoplado de UI, SQL e transportes.
- Inserir/remover comando HART nao pode exigir editar switch central.
- Todos os comandos devem usar parser/codec e funcoes de interpretacao comuns.
- O modelo legado nao define "equipamento Modbus"; nao inventar unit-id ou
  identidade. Usar perfil/associacao opcional ate haver requisito externo.

## Estado das frentes

### Fase 0 — concluida

- Mapa, plano detalhado, contratos, riscos, DoD e grafo de integracao foram
  entregues antes de qualquer alteracao.
- `.spec` e `.skill` foram criados porque nao existiam no repositorio/pai.

### Agente 1 — Desempenho

Primeira onda concluida e validada:

- `log_notifier.dart`: lista segmentada imutavel; custo cheio estimado caiu de
  ~4000 referencias copiadas para ~97 por append (~41x).
- `logs_screen.dart`: auto-scroll apenas quando tail muda.
- `sqlite_datasource.dart`: export HART de `2 + D*C` queries para 3 queries.
- `hart_table_notifier.dart`: ordem preferida indexada.
- `hart_table_screen.dart`: metadata de coluna indexada por build.
- `performance_log_notifier_test.dart`: limite, ordem, snapshot e clear.

Segunda onda em validacao no momento desta atualizacao:

- Novo `domain/expression/expression_engine.dart`, cache LRU e limites.
- `HartTransmitter.evaluateExpr` adaptado ao engine.
- `HartTableNotifier` indexa apenas celulas `func`.
- `performance_expression_engine_test.dart` inclui cache hits e limites.

Antes de aceitar a segunda onda, rodar os goldens HART/TF e a suite total.

### Agente 2 — Seguranca

Primeira onda concluida e validada em 63 testes:

- Modbus: MBAP/protocol ID/ADU, quantities normativas, byteCount, FC05,
  atomicidade de escritas, buffer/conexoes, loopback default e porta efemera.
- HART: decoder compartilhado TCP/serial, checksum, comprimento, ruido,
  fragmentacao/coalescencia, limite de buffer, endereco desconhecido sem
  fallback perigoso, loopback default.
- `security_protocol_test.dart`: 5 regressões.

Segunda onda em validacao no momento desta atualizacao:

- `xls_import_validator.dart`: limites e schema puro.
- `sqlite_datasource.dart`: validacao antes de mutar e transacao externa unica
  com savepoints por aba.
- `AppSettings`: validacao de portas e step; UI de settings ajustada.
- Testes `security_import_validation_test.dart` e
  `security_settings_test.dart`.

Revisar compatibilidade XLS valida e garantir dispose de statements em falha.

### Agente 3 — Arquitetura — concluida como esqueleto

Arquivos:

- `domain/equipment/equipment.dart`
- `application/equipment/equipment_catalog.dart`
- `domain/hart/hart_payload_parser.dart`
- `domain/hart/hart_command_registry.dart`
- `test/architecture_extensibility_test.dart`

Contratos:

```text
UI -> EquipmentCatalog -> EquipmentRepository -> adaptador
Transport -> HartCommandRegistry -> HartCommandHandler
          -> HartCommandContext -> HartFunctionRegistry + HartPayloadCodec
```

Coberto inicialmente: cadastro/remocao, duplicidade, handler/function registry,
parser truncado e associacao Modbus opcional. Todos os itens de wiring foram
resolvidos pelo Agente 6: transmissor/transportes/providers usam registries,
SQLite persiste equipamentos HART/Modbus/mistos e os botoes HART usam o
catalogo. O switch legado permanece apenas por tras dos handlers padrao.

### Agente 4 — Limpeza — concluida

- Removeu evaluator `HartTransmitter` duplicado da tela Modbus; usa canônico.
- Removeu deps diretas sem uso `intl` e `collection` (`collection` segue
  transitiva).
- Assets e APIs publicas ambiguos foram preservados.

### Agente 5 — Testes

Primeira onda concluida:

- `hart_frame_test.dart`: 7 caracterizacoes.
- `hart_transmitter_test.dart`: 10 caracterizacoes.
- Modbus cobre FC02/04/0F/10 e truncamento; portas efemeras/teardown.
- Placeholder virou teste de `ReactVar`.
- Antes das ondas 2, suite chegou a 67/67 com arquitetura extensivel.

Concluido: import rollback, lifecycle, registry por socket, equipamento por
SQLite, matriz de 59 comandos e CRUD/export/import. A segunda onda ampliou a
suite e fechou a cobertura executavel em 100%.

### Agente 6 — Integracao — concluida em 2026-07-14

- `HartTransmitter` recebe command/function registries e codec; TCP e serial
  usam a instancia injetada pelo provider. A API estatica foi preservada como
  adapter. Registro/remocao dinamicos coexistem com comandos padrao.
- Teste loopback prova comando custom atravessando framing, socket e registry.
- `equipment_catalog` persiste definicoes HART, Modbus e mistas. HART e
  provisionado atomicamente; Modbus permanece metadata-only, sem inventar
  unit-id ou associacao de pontos. CRUD da tela HART passa pelo catalogo.
- Datasource fecha idempotentemente e providers encerram DB e SimulTf.
- Relatorio consolidado: `docs/audit/README.md`; mudancas: `CHANGELOG.md`;
  migracao antes/depois: `MIGRATION.md`.
- Testes finais e cobertura devem ser lidos na secao "Validacao final" abaixo.

## Decisoes arquiteturais

- Desempenho vence conflitos de implementacao, mas nao pode violar goldens ou
  validacoes de seguranca.
- Bind de servidores agora e loopback por default; LAN exige endereco explicito.
- `port: 0` e permitido apenas como capacidade de API/teste; settings de usuario
  aceitam 1..65535.
- Frame HART invalido/desconhecido nao pode escrever nem cair em outro device.
- Import XLS deve validar integralmente antes de mutar e fazer commit atomico.
- APIs antigas permanecem por adapter ate migracao documentada.

## Ambiguidades abertas

- Regra PACTware/HART para address 0; fallback antigo foi removido por risco.
- Politica desejada de exposicao LAN/autenticacao.
- Schema oficial de custom commands e semantica das funcoes configuraveis HART.
- Identidade/unit-id/agregado de um equipamento Modbus.
- Compatibilidade XLS externa e volumes reais.
- Plataformas suportadas e smoke com hardware serial/3D.
- Uso externo de assets e propriedades publicas aparentemente mortas.

## Comandos de retomada

```powershell
git status --short
git diff --stat
flutter analyze
flutter test
flutter test --coverage
git diff --check
```

Nao use DB do usuario em testes. Use porta 0, arquivos temporarios, fakes para
serial/3D e encerre todo socket/timer/subscription/DB.

## Criterio de parada segura

Se houver falha futura, registre aqui: teste, arquivo/linha, causa provavel,
frente responsavel e proxima acao. Registry HART e EquipmentCatalog possuem
wiring real; nao regredir para parsing/comandos/CRUD acoplados.

## Validacao final

- `flutter analyze`: sem ocorrencias.
- `git diff --check`: sem erros; somente avisos informativos LF/CRLF.
- Suite integrada final: 179/179 aprovada.
- Coverage: 5010/5010 linhas executaveis = 100%.
- 51 arquivos Dart auditados: 46 registros LCOV em 100%; 5 arquivos apenas
  declarativos, sem linhas executaveis instrumentaveis.
- Todas as camadas e adaptadores serial, Win32 e WebView estao em 100% de
  linhas proprias mediante dependencias de plataforma injetaveis.
- Branch coverage nao foi emitida pelo LCOV nesta configuracao.
- Correcao final de arquitetura: remover comando HART padrao nao reativa mais
  o fallback legado; tombstone e teste permitem remover/re-registrar com
  semantica previsivel.
- Cleanup de sockets e `dispose` de servidores agora contem falhas de teardown.
- XLSX valida ZIP antes de descompactar (entradas, expansao, razao, ZIP64 e
  criptografia), valida schema antes de mutar e importa em transacao atomica.
