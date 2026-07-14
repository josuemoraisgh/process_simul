# Guia de migracao

## Comandos HART

Antes, um comando novo exigia editar o `switch` de `HartTransmitter.process`.

Agora, implemente `HartCommandHandler` (ou use `FunctionalHartCommandHandler`) e registre-o:

```dart
final transmitter = HartTransmitter(
  commands: HartTransmitter.standardCommandRegistry(),
  functions: HartFunctionRegistry(),
);

transmitter.registerCommand(FunctionalHartCommandHandler(
  0x7E,
  (context) => [0, 0, ...context.requestBody],
));
transmitter.removeCommand(0x7E);
```

Funcoes reutilizaveis implementam `HartFunction` e ficam disponiveis a todos os handlers por `context.interpret<T>(nome)`. Todo payload entra pelo `HartPayloadCodec`; truncamento e limites geram `HartPayloadException`.

Em Riverpod, sobrescreva `hartCommandRegistryProvider` ou `hartFunctionRegistryProvider` no composition root. TCP e serial recebem o mesmo transmissor, sem registry global oculto. Chamadas antigas a `HartTransmitter.process(...)` continuam validas.

`removeCommand(codigo)` agora tambem impede que o adaptador legado atenda esse
codigo. Para restaura-lo, registre novamente um `HartCommandHandler` com o
mesmo codigo. Isso torna remocao de comandos padrao e customizados simetrica.

## Equipamentos

Antes:

```dart
await repository.addHartDevice('FIT200');
```

Agora:

```dart
await catalog.register(EquipmentDefinition(
  id: EquipmentId('FIT200'),
  protocols: const {EquipmentProtocol.hart, EquipmentProtocol.modbus},
  profile: EquipmentProfile(key: 'generic'),
));

await catalog.remove(EquipmentId('FIT200'));
```

Definicoes HART, Modbus e mistas sao persistidas na tabela `equipment_catalog`. HART tambem cria/remove suas celulas legadas na mesma transacao. Modbus nao cria pontos nem presume `unit-id`: essa associacao deve ser adicionada quando o contrato externo for definido, usando `ModbusEquipmentAssociation`.

Os botoes existentes continuam chamando `HartTableNotifier.addDevice/removeDevice`; internamente eles agora usam o catalogo.

## Endereco de bind dos servidores

O campo persistido `hartTcpHost` tinha rotulo legado de destino de cliente e
nao era consumido. Ele agora e o endereco de bind comum dos servidores HART TCP
e Modbus: `127.0.0.1` mantem acesso local; `0.0.0.0` e o opt-in explicito para
LAN. Somente enderecos IP validos sao aceitos.

## Importacao e exportacao

O formato suportado e `.xlsx`. Chamadas de UI ou automacao que ofereciam
`.xls` devem restringir o filtro para `.xlsx`; o formato binario antigo nunca
foi decodificado pelo runtime. O schema valido permanece compativel.
