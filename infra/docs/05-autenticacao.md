# Fluxos de Autenticação TV 3.0

O CCWS implementa o protocolo de autenticação TV 3.0 com dois fluxos distintos
dependendo de onde o cliente está: na rede local ou em rede remota.

## Decisão do fluxo

```mermaid
flowchart TD
    CLIENT["Dispositivo\nPOST /tv3/authorize"]
    CHK{"Cliente é\nlocal?"}
    LOCAL["Fluxo Local\nToken imediato"]
    REMOTE["Fluxo Remoto\nChallenge-Response"]

    CLIENT --> CHK
    CHK -->|"IP na rede local"| LOCAL
    CHK -->|"IP externo"| REMOTE
```

---

## Fluxo Local (cliente na mesma rede)

```mermaid
sequenceDiagram
    participant C as Dispositivo Local
    participant CCWS as CCWS
    participant REDIS as Redis

    C->>CCWS: POST /tv3/authorize\n{ clientId, scope }
    CCWS->>CCWS: Verifica IP local
    CCWS->>REDIS: Salva sessão/refresh token
    CCWS-->>C: 200 OK\n{ access_token, refresh_token, expires_in }
    Note over C: Usa access_token nas próximas chamadas

    C->>CCWS: GET /tv3/current-service/users\nAuthorization: Bearer <token>
    CCWS->>CCWS: Valida JWT
    CCWS-->>C: 200 OK\n{ users: [...] }
```

---

## Fluxo Remoto — QRCode (cliente fora da rede)

```mermaid
sequenceDiagram
    participant C as Dispositivo Remoto
    participant CCWS as CCWS
    participant AOP as AoP (receptor)
    participant USER as Usuário (TV)

    C->>CCWS: POST /tv3/authorize\n{ clientId, scope, method: "qrcode" }
    CCWS->>CCWS: Gera código de challenge
    CCWS-->>C: 202 Accepted\n{ challenge_code, qrcode_url }

    CCWS->>AOP: MQTT — exibe QRCode na TV\n{ qrcode: "..." }
    USER->>AOP: Usuário escaneia QRCode / confirma na TV

    AOP->>CCWS: MQTT — confirmação do usuário
    CCWS->>CCWS: Gera tokens JWT

    C->>CCWS: POST /tv3/token\n{ challenge_code }
    CCWS-->>C: 200 OK\n{ access_token, refresh_token }
```

---

## Fluxo Remoto — KEX / ECDH (troca de chaves)

```mermaid
sequenceDiagram
    participant C as Dispositivo Remoto
    participant CCWS as CCWS

    C->>CCWS: POST /tv3/authorize\n{ clientId, method: "kex", publicKey (ECDH) }
    CCWS->>CCWS: Gera par de chaves ECDH
    CCWS->>CCWS: Deriva chave compartilhada (ECDH)
    CCWS-->>C: 200 OK\n{ serverPublicKey, encryptedChallenge (AES-128-ECB) }

    C->>C: Deriva chave compartilhada
    C->>C: Decifra challenge com AES-128-ECB
    C->>CCWS: POST /tv3/token\n{ challenge_response (cifrado) }
    CCWS->>CCWS: Valida resposta
    CCWS-->>C: 200 OK\n{ access_token, refresh_token }
```

---

## Renovação de token

```mermaid
sequenceDiagram
    participant C as Dispositivo
    participant CCWS as CCWS
    participant REDIS as Redis

    C->>CCWS: POST /tv3/token\n{ grant_type: "refresh_token", refresh_token }
    CCWS->>REDIS: Valida refresh_token
    REDIS-->>CCWS: Token válido + dados da sessão
    CCWS->>CCWS: Gera novo access_token (JWT)
    CCWS-->>C: 200 OK\n{ access_token, expires_in }
```

---

## Descoberta SSDP

Antes de autenticar, dispositivos na rede local descobrem o receptor via SSDP (UPnP):

```mermaid
sequenceDiagram
    participant C as Dispositivo na rede local
    participant SSDP as CCWS SSDP Server :1900
    participant CCWS as CCWS

    C->>SSDP: M-SEARCH * HTTP/1.1\nST: urn:schemas-upnp-org:device:TV3Receiver:1
    SSDP-->>C: 200 OK\nLOCATION: http://<ip>:44642/description.xml\nFRIENDLY-NAME: <nome do receptor>

    C->>CCWS: GET /description.xml
    CCWS-->>C: Device descriptor (brand, model, UDN, endpoints)
    Note over C: Agora sabe o IP e porta do receptor\npara iniciar o fluxo de autenticação
```
