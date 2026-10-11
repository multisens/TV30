---
title: Como funciona
nav_order: 3
has_children: true
---

# Como funciona

As peças do testbed, uma por página, na ordem em que uma depende da outra:

1. **[Arquitetura]({{ site.baseurl }}/arquitetura):** os módulos, os containers, as portas e os canais internos.
2. **[APIs do tv3ws]({{ site.baseurl }}/apis-tv3ws):** as rotas declaradas na borda, a seção da norma de cada uma, a autorização de cliente e o versionamento.
3. **[Modelo de dados Redis]({{ site.baseurl }}/modelo-redis):** as chaves, quem escreve e quem lê cada família.
4. **[Tópicos MQTT]({{ site.baseurl }}/mqtt-topicos):** quem publica e quem assina cada tópico, e o plugin de validação de esquema do broker.
5. **[Borda e credenciais]({{ site.baseurl }}/borda-credenciais):** as duas superfícies, a decisão de credencial do plugin `tv30-auth` e os modos `warn` e `enforce`.
6. **[Descoberta SSDP]({{ site.baseurl }}/ssdp):** o anúncio da C.3.4, quem anuncia e como ligar.

{: .nota }
Borda, mensageria e Redis são decisões de implementação deste testbed, não da ABNT NBR 25608. Onde uma página afirma conformidade, ela cita a seção da norma; onde descreve uma escolha do projeto, diz que é decisão do projeto.
