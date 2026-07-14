# Auditoria e refatoracao - relatorio de integracao

Data: 2026-07-14

## Resultado por frente

| Frente | Resultado integrado | Evidencia |
|---|---|---|
| Desempenho | log segmentado, cache LRU de expressoes, indices de UI/notifier e export HART em tres consultas | `performance_*_test.dart` |
| Seguranca | limites e validacao de HART, Modbus, XLSX e settings; bind loopback por padrao | `security_*_test.dart` |
| Arquitetura | registries HART injetaveis, codec comum e catalogo persistente de equipamentos | `architecture_extensibility_test.dart`, `hart_registry_integration_test.dart`, `sqlite_equipment_repository_test.dart` |
| Limpeza | evaluator duplicado removido e dependencias diretas sem uso retiradas | analyzer e diff |
| Testes | caracterizacao de frames, transmissor, Modbus, TF e regressao dos achados | suite Flutter |
| Integracao | providers possuem lifecycle explicito; API antiga preservada por adapter | analyzer, suite e coverage |

## Achados consolidados

`PERF-01 | log_notifier.dart:_add | alto | copia de ate 2000 entradas por log | perfil do append | lista imutavel segmentada | performance_log_notifier_test.dart`

`PERF-02 | sqlite_datasource.dart:exportToXls | alto | consultas D*C | inspecao do loop | indice em memoria e tres consultas | suite de import/export`

`SEC-01 | hart_frame.dart:HartFrameDecoder | alto | frame adulterado/truncado e buffer ilimitado | frames negativos | checksum, tamanho e limite | security_protocol_test.dart`

`SEC-02 | modbus_server.dart:_processRequest | alto | escritas parciais e quantidades excessivas | ADUs controladas | validacao integral antes de mutar | security_protocol_test.dart`

`SEC-03 | sqlite_datasource.dart:importFromXls | alto | import invalido podia mutar parcialmente | workbook invalido | pre-validacao e transacao unica | security_import_validation_test.dart`

`ARCH-01 | hart_transmitter.dart:process | alto | extensao exigia editar dispatcher monolitico | switch legado | registry/handler/codec injetados; API estatica virou adapter | hart_registry_integration_test.dart`

`ARCH-02 | hart_table_notifier.dart:addDevice/removeDevice | alto | UI acoplada ao CRUD HART concreto | chamadas diretas ao repositorio | EquipmentCatalog e SQLiteEquipmentRepository | sqlite_equipment_repository_test.dart`

`LIFE-01 | app_providers.dart | medio | DB e simulacao podiam sobreviver ao container | ausencia de onDispose | close idempotente e stop registrados | analyzer/suite`

`CLEAN-01 | modbus_table_screen.dart | medio | evaluator duplicado divergia do runtime | duas implementacoes | uso do engine canonico | hart_transmitter_test.dart`

## Riscos residuais

- O schema Modbus nao define identidade de equipamento, `unit-id` ou relacao entre ponto e equipamento. Equipamentos Modbus sao persistidos como definicao/perfil, sem associar pontos automaticamente.
- Os comandos padrao continuam encapsulando a implementacao legada para preservar os goldens. O dispatcher de runtime e o registry; comandos novos nao alteram esse legado.
- Serial e viewer 3D dependem de hardware/plataforma e nao possuem smoke real nesta execucao.
- Politica de exposicao LAN/autenticacao e semantica externa de comandos configuraveis continuam sem requisito confirmado.

## Validacao final

- Analyzer: limpo.
- Suite integrada: 82/82 aprovada tres vezes consecutivas.
- Suite ampliada: 96/96 aprovada.
- Cobertura total: 2014/2362 linhas, 85,27%.
- `HartTransmitter`: 98,86%; `SqliteDatasource`: 96,49%.
- Domain: 83,14%; application: 66,17%; infrastructure: 87,17%; data: 86,81%.
- Branch coverage nao foi registrada pelo LCOV usado nesta execucao.

O alvo global de 80% foi atingido. Os alvos aspiracionais de 90% por camada
nao foram atingidos em domain/application; os numeros reais ficam expostos
para orientar a proxima rodada, sobretudo testes de notifiers e bootstrap.

## Riscos externos e proximas decisoes

- Confirmar a identidade/unit-id e o agrupamento de pontos para equipamentos
  Modbus. Hoje o catalogo persiste o equipamento/perfil sem criar pontos.
- Confirmar regra PACTware para address 0; frames sem dispositivo conhecido
  sao descartados para impedir escrita no equipamento errado.
- `0.0.0.0` habilita LAN explicitamente para HART/Modbus, mas autenticacao e
  allowlist dependem de politica operacional ainda nao fornecida.
- O picker ainda anuncia `.xls`, enquanto o decoder utilizado e XLSX; suporte
  binario real exige biblioteca/conversao definida.
- O limite comprimido de 10 MiB reduz risco, mas quota de expansao contra ZIP
  bomb requer decoder que exponha controle da descompressao ou isolate.
- Serial e viewer 3D exigem smoke em hardware/plataforma alvo.
