---
title: Como funciona
---


As peças do testbed, uma por página, na ordem em que uma depende da outra:

1. **[Arquitetura](../arquitetura/):** os módulos, os containers, as portas e os canais internos.
2. **[APIs do tv3ws](../apis-tv3ws/):** as rotas declaradas na borda, a seção da norma de cada uma, a autorização de cliente e o versionamento.
3. **[Modelo de dados Redis](../modelo-redis/):** as chaves, quem escreve e quem lê cada família.
4. **[Tópicos MQTT](../mqtt-topicos/):** quem publica e quem assina cada tópico.
5. **[Broker MQTT](../broker-mqtt/):** o plugin C do broker, a validação de esquema e o teste de latência.
6. **[Borda e credenciais](../borda-credenciais/):** as duas superfícies, o certificado da 44643, a decisão de credencial e de versão do plugin `tv30-auth` e os modos `enforce` e `warn`.
7. **[Descoberta SSDP](../ssdp/):** o anúncio da C.3.4, o anunciante nativo do host (`./tv30 up`), o firewall e as permissões.
8. **[Decisões](../decisoes/):** as decisões do projeto e o motivo de cada uma.
9. **[Não implementado](../nao-implementado/):** o que a norma especifica e o testbed não implementa ou implementa de outra forma.
10. **[Mapa de unidades](../mapa-unidades/):** as unidades de implementação da TV 3.0 AoP sobre a arquitetura da plataforma, com o estado de cada uma no testbed.

:::note[Norma × implementação]
Borda, mensageria e Redis são decisões de implementação deste testbed, não da ABNT NBR 25608. Onde uma página afirma conformidade, ela cita a seção da norma; onde descreve uma escolha do projeto, diz que é decisão do projeto.
:::
