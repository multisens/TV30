// Actors and messages of the sequence diagrams of the guide "Chamar as APIs
// de outro aparelho" (components/sequence-diagram.astro).

const VIEWER = { id: 'viewer', label: 'Espectador' };
const SCREEN = { id: 'screen', label: 'Tela da TV' };
const WEBSERVICES = { id: 'ws', label: 'WebServices' };

export const localAuthorization = {
    actors: [
        { id: 'client', label: 'Seu programa' },
        WEBSERVICES,
        SCREEN,
        VIEWER,
    ],
    messages: [
        {
            id: 'authorize',
            from: 'client',
            to: 'ws',
            label: 'GET /tv3/authorize',
            title: 'Pedido de autorização',
            detail: 'Na porta 44642, por HTTP, com um <code>clientid</code> novo (um UUID) e o '
                + '<code>display-name</code>, o nome que a TV vai mostrar. Sem <code>pm</code>: é '
                + 'isso que faz do cliente um local autônomo. A resposta só chega depois que o '
                + 'espectador responder.',
            channel: 'http',
        },
        {
            id: 'popup',
            from: 'ws',
            to: 'screen',
            label: 'pop-up Sim/Não',
            title: 'A TV pergunta ao espectador',
            detail: 'O pop-up mostra o <code>display-name</code> e fica 10 segundos na tela. Sem '
                + 'resposta nesse tempo, conta como recusa.',
            channel: 'internal',
        },
        {
            id: 'yes',
            from: 'viewer',
            to: 'screen',
            label: 'Sim',
            title: 'O espectador autoriza',
            detail: 'Com o Não, ou sem resposta, o cliente fica bloqueado: o mesmo '
                + '<code>clientid</code> recebe o erro 101 daí em diante.',
            channel: 'person',
        },
        {
            id: 'refresh',
            from: 'ws',
            to: 'client',
            label: 'refreshToken',
            title: 'O refresh token',
            detail: 'Guarde-o junto com o <code>clientid</code>: é com ele que o cliente obtém '
                + 'tokens nas próximas vezes, sem pedir autorização de novo.',
            channel: 'http',
        },
        {
            id: 'token',
            from: 'client',
            to: 'ws',
            label: 'GET /tv3/token',
            title: 'Pedido do access token',
            detail: 'Com o <code>clientid</code> e o <code>refresh-token</code>.',
            channel: 'http',
        },
        {
            id: 'access',
            from: 'ws',
            to: 'client',
            label: 'accessToken',
            title: 'O access token',
            detail: 'Vale 24 horas. A resposta traz também um refresh token novo, que substitui o '
                + 'anterior: guarde sempre o último.',
            channel: 'http',
        },
        {
            id: 'call',
            from: 'client',
            to: 'ws',
            label: 'GET /tv3/current-service',
            title: 'Chamada a uma API',
            detail: 'Com o cabeçalho <code>Authorization: Bearer &lt;access token&gt;</code>. Sem '
                + 'ele, ou com um token vencido, a resposta é o erro 107.',
            channel: 'http',
        },
    ],
};

export const nonLocalPairing = {
    actors: [
        { id: 'client', label: 'Seu aparelho' },
        WEBSERVICES,
        SCREEN,
        VIEWER,
    ],
    messages: [
        {
            id: 'manifest',
            from: 'client',
            to: 'ws',
            label: 'GET /manifest',
            title: 'Achar a TV',
            detail: 'O aparelho acha a TV na rede por SSDP e lê o manifesto em '
                + '<code>http://&lt;ip da TV&gt;:44642/manifest</code>. Os cabeçalhos da resposta '
                + 'dão os endereços HTTP e HTTPS e os métodos de pareamento: '
                + '<code>qrcode,kex</code>.',
            channel: 'http',
        },
        {
            id: 'authorize',
            from: 'client',
            to: 'ws',
            label: 'GET /tv3/authorize, pm=kex',
            title: 'Pedido de autorização com pareamento',
            detail: 'Com <code>pm=kex</code> e, em <code>key</code>, a chave parcial do aparelho '
                + '(ECDH na curva P-256). Pedir pareamento é o que faz do cliente um não local.',
            channel: 'http',
        },
        {
            id: 'popup',
            from: 'ws',
            to: 'screen',
            label: 'pop-up Sim/Não',
            title: 'A TV pergunta ao espectador',
            detail: 'O mesmo pop-up do cliente local, com 10 segundos para responder.',
            channel: 'internal',
        },
        {
            id: 'yes',
            from: 'viewer',
            to: 'screen',
            label: 'Sim',
            title: 'O espectador autoriza',
            detail: 'A autorização só fica gravada quando o pareamento termina, no passo 9.',
            channel: 'person',
        },
        {
            id: 'challenge',
            from: 'ws',
            to: 'client',
            label: 'challenge + key',
            title: 'A chave da TV e o desafio',
            detail: 'A TV responde com a chave parcial dela e um desafio cifrado. Cada lado combina '
                + 'a própria chave com a do outro e chega ao mesmo segredo, que nunca passa pela '
                + 'rede.',
            channel: 'http',
        },
        {
            id: 'pin',
            from: 'ws',
            to: 'screen',
            label: 'PIN',
            title: 'A TV mostra o PIN',
            detail: 'Quatro dígitos, calculados do segredo. O PIN fica na tela até o fim do '
                + 'pareamento, por no máximo 2 minutos.',
            channel: 'internal',
        },
        {
            id: 'typed',
            from: 'viewer',
            to: 'client',
            label: 'digita o PIN',
            title: 'O espectador confere',
            detail: 'O aparelho calcula o PIN do lado dele. Se for igual ao que o espectador '
                + 'digitou, os dois lados têm o mesmo segredo e ninguém está no meio.',
            channel: 'person',
        },
        {
            id: 'token',
            from: 'client',
            to: 'ws',
            label: 'GET /tv3/token',
            title: 'A resposta ao desafio',
            detail: 'Em <code>challenge-response</code>: o desafio decifrado, passado por SHA-256 e '
                + 'cifrado de novo com o segredo.',
            channel: 'http',
        },
        {
            id: 'tokens',
            from: 'ws',
            to: 'client',
            label: 'tokens + certificado',
            title: 'A primeira resposta, cifrada',
            detail: 'Cifrada com o segredo (AES-128): access token, refresh token e '
                + '<code>serverCert</code>, o certificado da TV. A TV tira o PIN da tela.',
            channel: 'cipher',
        },
        {
            id: 'call',
            from: 'client',
            to: 'ws',
            label: 'GET /tv3/current-service',
            title: 'Chamada a uma API, por HTTPS',
            detail: 'Daí em diante, só HTTPS, na porta 44643, confiando no certificado recebido, e '
                + 'só nele. Por HTTP, a TV responde o erro 106.',
            channel: 'https',
        },
    ],
};
