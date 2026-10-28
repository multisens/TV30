---
title: Broker MQTT
parent: Como funciona
nav_order: 5
---

# Broker MQTT e validação de esquema

O broker é o Mosquitto do container `mqtt-broker` (serviço `mosquitto`), com um plugin C (`infra/mqtt-broker/plugin/`). O plugin valida o esquema do payload de cada publicação e responde ao teste de latência. Ele não consulta o Redis e não controla o acesso a tópicos: usa o evento `MOSQ_EVT_ACL_CHECK` do Mosquitto só para validar o PUBLISH e deixa passar todo o resto (`callback_acl_check`, em `plugin/src/mosquitto_plugin.c`). Mensageria e broker são decisões do projeto ([Decisões]({{ site.baseurl }}/decisoes)); os tópicos estão em [Tópicos MQTT]({{ site.baseurl }}/mqtt-topicos).

## Quando o validador roda

| Publicação | Validada |
|---|---|
| PUBLISH com payload num tópico com esquema declarado | sim |
| PUBLISH num tópico sem esquema | não |
| PUBLISH em `errors/*`, `PluginResponseTime*`, `PublisherResponseTime*` e `$SYS/*` | não |
| PUBLISH com payload vazio (por exemplo, a limpeza de uma mensagem retida) | não |
| SUBSCRIBE | não |

Os tópicos com esquema são os de `infra/mqtt-broker/plugin/config/schemas.json`: `aop/currentUser`, `aop/removedUser`, `aop/currentService`, `aop/services`, `aop/display/layers/rxgui`, `aop/display/layers/graphics`, `aop/display/layers/video/url`, `aop/display/layers/video/size`, `video/event`, `tlm/lls/+/bamt`, `tlm/sls/+/esg`, `tlm/sls/+/bald`, `aop/+/currentApp` e `aop/+/+/path`, mais três tópicos de teste fora da plataforma (`sensor/room1/temperature`, `sensor/room2/humidity` e `sensor/comprehensive/test`).

**Casamento do tópico** (`get_schema_for_topic` e `topic_matches`): primeiro a chave igual ao tópico; senão, a primeira chave com `+` ou `#` que casa, na ordem do arquivo, e não a mais específica.

**Leitura do payload** (`json_payload_parse`, em `plugin/src/json_payload.c`): o payload é lido inteiro, pelo comprimento, e só vale como JSON se for exatamente um texto JSON da RFC 8259 (seção 2), com o json-c no modo estrito. Dão `INVALID_JSON`: sobra depois do valor (`{"value":1}lixo`), NUL em qualquer posição, comentário, aspas simples, vírgula sobrando, `TRUE`, zero à esquerda e `\f` ou `\v` em volta do valor. O json-c estrito ainda aceita `NaN`, `Infinity`, `1.` e caractere de controle cru ou UTF-8 inválido dentro de string.

**Payload texto puro:** num tópico de esquema `"type": "string"`, o payload que não é texto JSON vale inteiro como string (um UUID, um caminho, um nome de tela), desde que não tenha NUL; com NUL, `INVALID_JSON`. O literal `null` também cai aqui. Um payload que é texto JSON vale pelo valor: `"abc"`, com aspas, é a string `abc`, e `42` é número.

## Palavras-chave do esquema

Subconjunto do JSON Schema Draft-07, em `plugin/src/schema_validator.c`.

| Palavra-chave | Tipos |
|---|---|
| `type` (`string`, `number`, `integer`, `boolean`, `array`, `object`, `null`) | todos |
| `minimum`, `maximum`, `exclusiveMinimum`, `exclusiveMaximum`, `multipleOf` | number, integer |
| `minLength`, `maxLength`, `pattern` (regex POSIX, sem flags) | string |
| `minItems`, `maxItems`, `uniqueItems`, `items` (um esquema por elemento, ou array posicional) | array |
| `minProperties`, `maxProperties`, `required`, `properties`, `additionalProperties` | object |
| `enum`, `const` | todos |

`description` e `$schema` são ignorados. Sem efeito, sem aviso: `oneOf`, `anyOf`, `allOf`, `not`, `if`/`then`/`else`, `format`, `contains`, `propertyNames`, `dependencies`, `definitions`/`$ref` e `$id`.

## Erro de validação

Payload recusado não é entregue aos assinantes. O plugin devolve `MOSQ_ERR_ACL_DENIED` ao broker, loga `Validation failed for topic <tópico>: <motivo>` e publica em `errors/<client_id>` (QoS 0, sem retenção):

```json
{"timestamp": "AAAA-MM-DDTHH:MM:SS", "topic": "...", "error_type": "INVALID_JSON | SCHEMA_VALIDATION_FAILED",
 "details": "...", "client_id": "...", "payload": "...", "truncated": true}
```

A mensagem (`error_json_build`, em `plugin/src/error_json.c`) é sempre JSON e UTF-8 válidos:
- o `timestamp` é UTC, sem fuso;
- aspas, barra invertida e U+0000 a U+001F saem escapados (RFC 8259, seção 7), e byte que não forma UTF-8 válido vira U+FFFD;
- o payload entra pelo comprimento: NUL no meio sai como `\u0000`;
- a mensagem tem no máximo 2047 bytes. Cada campo além do payload tem um teto em bytes escapados (`timestamp` 32, `topic` 512, `error_type` 64, `details` 768, `client_id` 256), e o payload fica com o resto. O corte é só entre unidades inteiras, e `"truncated":true` só aparece quando houve corte.

O tópico (`error_json_topic`) tem até 255 bytes. No `client_id`, cada `+`, `#`, `/`, controle (U+0000 a U+001F, U+007F a U+009F) e byte que não forma UTF-8 válido vira `_`; `client_id` vazio vira `_`. Dois clientes podem cair no mesmo tópico (`a+b` e `a_b`); o campo `client_id` da mensagem leva o original.

## Teste de latência

Uma publicação em `PublisherResponseTime<id>/iteration<N>` com `{testResponsetime, localtime, id, iteration}` é entregue e respondida em `PluginResponseTime<id>/iteration<N>` com `{localtime, id, iteration, diffTime}` (`plugin/src/response_time_tester.c`). A medição com interface web (porta 3000) e as rodadas sem interface ficam em `infra/mqtt-broker/brokertimetest/`.

## Acrescentar ou mudar um esquema

1. Edite `infra/mqtt-broker/plugin/config/schemas.json`: uma chave por tópico (exato ou com `+` e `#`), com o esquema como valor.
2. Reconstrua a imagem, na raiz do TV30. O arquivo é copiado para a imagem no build, e o plugin só o lê na partida (`mosquitto_plugin_init`); `docker compose restart` não basta.

   ```bash
   docker compose --profile mqtt build mosquitto
   docker compose --profile mqtt up -d mosquitto
   ```

3. Confira no log:

   ```bash
   docker logs mqtt-broker 2>&1 | grep -E "Schemas? loaded"
   ```

   Sai `Schemas loaded from file: <n> topics configured` e uma linha `Schema loaded for topic: <tópico>` por tópico. Arquivo com JSON inválido só loga `Invalid JSON in schemas file`, e o broker segue sem nenhum esquema.

Para conferir uma regra, assine `errors/#` e publique um payload que a viole:

```bash
mosquitto_sub -h localhost -p 1883 -t 'errors/#' -v &
mosquitto_pub -h localhost -p 1883 -i meu-cliente -t sensor/room1/temperature -m '{"value":"x"}'
```

| Para mudar | Arquivo |
|---|---|
| uma palavra-chave nova | `plugin/src/schema_validator.c` |
| os tópicos que nunca são validados | `plugin/src/mosquitto_plugin.c` (`callback_acl_check`) |
| a leitura do payload | `plugin/src/json_payload.c`; o texto puro dos tópicos `type: string`, em `validate_message` (`mosquitto_plugin.c`) |
| a mensagem ou o tópico de `errors/` | `plugin/src/error_json.c` e `plugin/include/error_json.h` |
| o casamento de tópico | `plugin/src/mosquitto_plugin.c` (`topic_matches`, `get_schema_for_topic`) |

Mudança no C também exige reconstruir a imagem.

## Container

O `entrypoint.sh` só sobe o Mosquitto (`infra/mqtt-broker/infra/entrypoint.sh`), que carrega o plugin e o `schemas.json` e escuta na 1883 e no WebSocket da 9001. O broker não usa o Redis; o `migrate_to_redis.py` fica na imagem, em `/usr/local/bin`, só para depuração manual.

O `infra/mqtt-broker/infra/docker-compose.yml` sobe o broker sozinho, fora da stack, numa rede `ginga_net` já criada: publica a 1883 e a 9001 em portas fixas e usa o mesmo nome de container da stack (`mqtt-broker`), então os dois não sobem juntos.

## Testes

Os testes do plugin estão em [Como testar]({{ site.baseurl }}/como-testar).
