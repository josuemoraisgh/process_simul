# Changelog

## Auditoria 2026-07-14

- Otimizados logging, avaliacao de expressoes, export SQLite e rebuilds da UI.
- Endurecidos parsers HART/Modbus, limites de rede, importacao XLSX e settings.
- Adicionados `HartCommandRegistry`, `HartFunctionRegistry` e `HartPayloadCodec`.
- Injetado um `HartTransmitter` unico no composition root, TCP e serial.
- Mantida a API estatica `HartTransmitter.process` como compatibilidade.
- Adicionado catalogo SQLite para equipamentos HART, Modbus e mistos; HART e provisionado atomicamente e Modbus permanece metadata-only.
- Migrado o CRUD de dispositivos HART da UI para `EquipmentCatalog`.
- Adicionado lifecycle explicito para datasource, simulacao, sockets, serial e listeners.
- Ampliada a suite com caracterizacao, seguranca, desempenho e extensibilidade.
- Reaproveitado o campo legado `hartTcpHost` como bind comum HART/Modbus:
  loopback por padrao e `0.0.0.0` como opt-in LAN.
- Sincronizado rename de equipamento HART/misto entre tabela HART e catalogo.
- Garantido `dispose` de prepared statements do import XLSX tambem em falhas.
- Validacao final ampliada: 179 testes e 5010/5010 linhas executaveis (100%).
- Isolados adaptadores serial, Win32 e ModelViewer/WebView para testes sem
  hardware, preservando os adapters reais em producao.
- Corrigidos leak de timer e uso duplo de `ScrollController` no viewer/tabela.
- Endurecido XLSX antes da descompressao contra ZIP bomb, ZIP64 e criptografia;
  picker agora anuncia somente `.xlsx`.
- Remover um comando HART padrao agora bloqueia o fallback legado ate que o
  comando seja explicitamente registrado novamente.
- Falhas de cleanup de sockets/servidores sao contidas e registradas.
