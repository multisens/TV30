// Layered map of the current architecture (components/component-map.astro),
// for the page Arquitetura: who uses the receiver on top; the SSDP announcer
// as a band above the edge; the shell, the tv3ws and the edge side by side;
// messaging and storage as the base; the infrastructure (edge, broker and
// Redis) as one inverted-L group; the simulated broadcaster beside the
// receiver.
import type { Block, ComponentMap, Link, RowLabel, Zone } from './component-map.ts';

const zones: Zone[] = [
    { id: 'users', title: 'Quem usa', x: 10, y: 10, width: 980, height: 95 },
    { id: 'broadcaster', title: 'Emissora', subtitle: 'simulada', x: 10, y: 120, width: 140, height: 295 },
    { id: 'receiver', title: 'Receptor', subtitle: 'TV 3.0 AoP', x: 165, y: 120, width: 825, height: 295 },
];

const rowLabels: RowLabel[] = [
    { text: 'componentes', x: 175, y: 220 },
    { text: 'base', x: 175, y: 360 },
];

const blocks: Block[] = [
    {
        id: 'ssdp',
        kind: 'bus',
        tone: 'discovery',
        title: 'Anunciante SSDP',
        titleX: 820,
        x: 530,
        y: 130,
        width: 430,
        height: 32,
        detailTitle: 'Anunciante SSDP',
        detail: 'A descoberta da C.3.4: anuncia na rede local, em UDP 1900, o endereço '
            + '<code>http://&lt;IP&gt;:44642/manifest</code>, servido pelo <code>tv3ws</code> atrás '
            + 'da borda. Roda no computador, e não em container, porque o multicast não sai do Docker '
            + 'fora do Linux nativo. O <code>./tv30 up</code> o sobe, e o <code>./tv30 down</code> o '
            + 'encerra.',
    },
    {
        id: 'viewer',
        kind: 'node',
        tone: 'screen',
        title: 'Espectador',
        subtitle: 'a TV no navegador',
        x: 150,
        y: 30,
        width: 170,
        height: 55,
        detailTitle: 'Espectador',
        detail: 'Vê a TV numa página do navegador, em <code>http://localhost:8080</code>, e a controla '
            + 'pelo teclado.',
    },
    {
        id: 'app',
        kind: 'node',
        tone: 'app',
        title: 'App de emissora',
        subtitle: 'na camada de gráficos',
        x: 690,
        y: 30,
        width: 140,
        height: 55,
        detailTitle: 'Aplicação de emissora',
        detail: 'Cliente local associado. Roda na camada de gráficos, servida pela casca num nome de host '
            + 'próprio (<code>&lt;app&gt;.apps.localhost:8080</code>), e chama as APIs pela 44642 da '
            + 'borda, que a reconhece pelo <code>Origin</code>.',
    },
    {
        id: 'device',
        kind: 'node',
        title: 'Aparelho na rede',
        subtitle: 'cliente não local',
        x: 850,
        y: 30,
        width: 130,
        height: 55,
        detailTitle: 'Aparelho na rede',
        detail: 'Celular, tablet ou computador. Acha a TV pelo anúncio SSDP, pede autorização pela '
            + '44642 e usa as demais APIs pela 44643, em HTTPS.',
    },
    {
        id: 'remote',
        kind: 'node',
        title: 'Dispositivo remoto',
        subtitle: 'efeitos, NCL 360 VR',
        x: 340,
        y: 30,
        width: 330,
        height: 55,
        detailTitle: 'Dispositivo remoto',
        detail: 'Registra-se pela API de dispositivos remotos, que passa pela borda, e recebe um endereço '
            + 'WebSocket. Daí em diante troca mensagens direto com o <code>tv3ws</code>.',
    },
    {
        id: 'bcast',
        kind: 'node',
        title: 'bcast',
        subtitle: 'quatro serviços',
        x: 22,
        y: 205,
        width: 116,
        height: 66,
        detailTitle: 'Emissora simulada (bcast)',
        detail: 'Publica na mensageria a sinalização dos serviços (BAMT, ESG e BALD, retidas) e os '
            + 'eventos do vídeo, e serve por HTTP as aplicações de emissora e o vídeo em HLS. Cada '
            + 'serviço de exemplo é um módulo dele. Está planejado o caminho da norma, em que a '
            + 'emissora serve a sinalização e o receptor vai buscá-la.',
    },
    {
        id: 'shell',
        kind: 'node',
        tone: 'platform',
        title: 'Casca · aop-shell',
        subtitle: 'perfis, catálogo, camadas',
        x: 265,
        y: 205,
        width: 155,
        height: 66,
        detailTitle: 'Casca da plataforma (aop-shell)',
        detail: 'Na porta 8080: as telas (perfis, catálogo, Bootstrap Application), as camadas de vídeo, '
            + 'de gráficos e de interface e o nome de host próprio de cada aplicação de emissora, cuja '
            + 'origem ela grava na lista de origens associadas enquanto a aplicação roda. Recebe a '
            + 'sinalização e mantém a lista dos serviços anunciados.',
    },
    {
        id: 'infra',
        kind: 'group',
        tone: 'infra',
        title: 'infra',
        titleX: 895,
        x: 630,
        y: 180,
        width: 340,
        height: 225,
        outline: 'M630 180 H970 V405 H255 V305 H630 Z',
        detailTitle: 'Infraestrutura do testbed',
        detail: 'As peças que ligam os componentes e que a norma não especifica: a borda, a mensageria '
            + 'e o armazenamento, em <code>infra/</code>. A conferência das credenciais e as APIs que a '
            + 'borda responde sozinha rodam dentro dela, mas são componentes da norma.',
    },
    {
        id: 'edge',
        kind: 'node',
        parent: 'infra',
        title: 'Borda · edgegateway',
        subtitle: '44642 HTTP · 44643 HTTPS',
        x: 640,
        y: 205,
        width: 320,
        height: 66,
        detailTitle: 'Borda (edgegateway)',
        detail: 'A entrada única das APIs: dois KrakenD, o interno na 44642, porta fixada pela norma, e '
            + 'o externo na 44643, que termina o TLS com o certificado do receptor. O plugin '
            + '<code>tv30-auth</code> confere as credenciais, negocia a versão de cada rota e responde '
            + 'ele mesmo a C.6.8 e a C.6.7.8/C.6.7.9; o resto vai ao <code>tv3ws</code>. A documentação '
            + 'das rotas fica numa porta escolhida pelo Docker (<code>docker port edgegateway '
            + '8085</code>).',
    },
    {
        id: 'tv3ws',
        kind: 'node',
        tone: 'webservices',
        title: 'tv3ws',
        subtitle: 'TV 3.0 WebServices',
        x: 440,
        y: 205,
        width: 160,
        height: 66,
        detailTitle: 'TV 3.0 WebServices (tv3ws)',
        detail: 'As APIs do Anexo C, menos as que a borda responde. Emite o accessToken e serve o '
            + '<code>/manifest</code>, mas não confere a credencial: isso é da borda. As portas dele '
            + '(44652 e 44653) só existem dentro da rede do Docker; os WebSockets dos dispositivos '
            + 'remotos ficam na faixa 45000 a 45199.',
    },
    {
        id: 'broker',
        kind: 'bus',
        parent: 'infra',
        tone: 'mqtt',
        title: 'Mensageria · broker MQTT',
        titleX: 450,
        x: 265,
        y: 315,
        width: 695,
        height: 30,
        detailTitle: 'Mensageria: broker MQTT (mqtt-broker)',
        detail: 'Na porta 1883. Um plugin confere cada publicação contra o esquema declarado do tópico; '
            + 'não há controle de acesso a tópicos. As mensagens retidas (sinalização e estado) '
            + 'sobrevivem a um reinício do broker.',
    },
    {
        id: 'redis',
        kind: 'bus',
        parent: 'infra',
        tone: 'state',
        title: 'Armazenamento · Redis',
        titleX: 480,
        x: 265,
        y: 365,
        width: 695,
        height: 30,
        detailTitle: 'Armazenamento: Redis',
        detail: 'Na porta 6379, só em <code>127.0.0.1</code> e sem senha. Na primeira subida, recebe a '
            + 'carga inicial (o perfil de exemplo). A escrita passa por funções do próprio Redis, que '
            + 'conferem o esquema. Uma interface de inspeção, com login, fica numa porta escolhida pelo '
            + 'Docker (<code>docker port redis 18081</code>).',
    },
];

const links: Link[] = [
    {
        id: 'arch-viewer',
        channel: 'http',
        ends: ['viewer', 'shell'],
        path: 'M290 85 V205',
        detailTitle: 'Espectador → casca',
        detail: 'A página da TV vem da casca, na porta 8080. Ela também assina a mensageria, por '
            + 'WebSocket, no caminho <code>/mqtt</code> da casca, que repassa a conexão ao broker.',
    },
    {
        id: 'arch-app',
        channel: 'http',
        ends: ['app', 'edge'],
        path: 'M740 85 V205',
        detailTitle: 'Aplicação de emissora → borda',
        detail: 'Pela 44642, sem credencial: a borda a reconhece pelo <code>Origin</code>.',
    },
    {
        id: 'arch-device',
        channel: 'http',
        ends: ['device', 'edge'],
        path: 'M950 85 V205',
        detailTitle: 'Aparelho na rede → borda',
        detail: 'A autorização pela 44642; as demais APIs pela 44643, em HTTPS, com o accessToken.',
    },
    {
        id: 'arch-remote-http',
        channel: 'http',
        ends: ['remote', 'edge'],
        path: 'M650 85 V205',
        detailTitle: 'Dispositivo remoto → borda',
        detail: 'O registro do dispositivo, que devolve o endereço WebSocket.',
    },
    {
        id: 'arch-ssdp',
        channel: 'discovery',
        ends: ['ssdp', 'device'],
        path: 'M900 85 V130',
        detailTitle: 'Anunciante SSDP → aparelho na rede',
        detail: 'O anúncio por multicast, a cada intervalo e em resposta a uma busca; o '
            + '<code>./tv30 down</code> manda o <code>ssdp:byebye</code>. O endereço anunciado acompanha '
            + 'a troca de rede, e <code>SSDP_ADVERTISE_HOST</code> o fixa.',
    },
    {
        id: 'arch-remote-ssdp',
        channel: 'discovery',
        ends: ['ssdp', 'remote'],
        path: 'M560 85 V130',
        detailTitle: 'Anunciante SSDP → dispositivo remoto',
        detail: 'O mesmo anúncio: o dispositivo remoto acha a TV pela descoberta antes de se registrar '
            + 'pela borda.',
    },
    {
        id: 'arch-remote-ws',
        channel: 'websocket',
        ends: ['remote', 'tv3ws'],
        path: 'M500 85 V205',
        detailTitle: 'Dispositivo remoto ↔ tv3ws, por WebSocket',
        detail: 'Fora da borda, na faixa 45000 a 45199, só pelo endereço que o registro devolveu. O '
            + 'ponto de entrada do dispositivo remoto sai em <code>wss://</code>, com o certificado do '
            + 'receptor.',
    },
    {
        id: 'arch-edge',
        channel: 'http',
        ends: ['edge', 'tv3ws'],
        path: 'M640 238 H600',
        detailTitle: 'Borda → tv3ws',
        detail: 'As rotas que a borda não responde, já com a credencial conferida: a interna repassa à '
            + '44652, e a externa, à 44653, em HTTPS.',
    },
    {
        id: 'arch-proxy',
        channel: 'http',
        ends: ['shell', 'bcast'],
        path: 'M265 238 H138',
        detailTitle: 'Casca → bcast, por HTTP',
        detail: 'A casca busca no bcast as aplicações de emissora, no endereço que a BALD de cada serviço '
            + 'anuncia, e o vídeo, no endereço que vem na BAMT.',
    },
    {
        id: 'arch-bcast-mqtt',
        channel: 'mqtt',
        ends: ['bcast', 'broker'],
        path: 'M80 271 V330 H265',
        detailTitle: 'bcast → mensageria',
        detail: 'A sinalização dos serviços, retida no broker (<code>tlm/lls/…</code>, '
            + '<code>tlm/sls/…</code>), e os eventos do vídeo (<code>video/event</code>).',
    },
    {
        id: 'arch-shell-mqtt',
        channel: 'mqtt',
        ends: ['shell', 'broker'],
        path: 'M300 271 V315',
        detailTitle: 'Casca ↔ mensageria',
        detail: 'Assina a sinalização e o que mostrar em cada camada; publica o serviço e o usuário '
            + 'correntes, o estado da aplicação de emissora e a lista dos serviços anunciados.',
    },
    {
        id: 'arch-shell-state',
        channel: 'state',
        ends: ['shell', 'redis'],
        path: 'M330 271 V365',
        detailTitle: 'Casca ↔ Redis',
        detail: 'Perfis, a lista de origens das aplicações associadas e os serviços anunciados.',
    },
    {
        id: 'arch-edge-state',
        channel: 'state',
        ends: ['edge', 'redis'],
        path: 'M700 271 V365',
        detailTitle: 'Borda ↔ Redis',
        detail: 'O que a decisão de credencial precisa consultar, e as chaves do bind-token, que ela '
            + 'grava quando a emissora as registra. A borda não usa a mensageria.',
    },
    {
        id: 'arch-tv3ws-mqtt',
        channel: 'mqtt',
        ends: ['tv3ws', 'broker'],
        path: 'M470 271 V315',
        detailTitle: 'tv3ws ↔ mensageria',
        detail: 'Assina o serviço, o usuário e a aplicação correntes; publica os pedidos de autorização e '
            + 'de pareamento que a TV mostra e os dispositivos remotos registrados.',
    },
    {
        id: 'arch-tv3ws-state',
        channel: 'state',
        ends: ['tv3ws', 'redis'],
        path: 'M570 271 V365',
        detailTitle: 'tv3ws ↔ Redis',
        detail: 'Atributos de perfil, credenciais dos clientes, sessão (serviço e usuário correntes) e '
            + 'dispositivos remotos registrados.',
    },
];

export const architectureMap: ComponentMap = {
    width: 1000,
    height: 425,
    zones,
    rowLabels,
    blocks,
    links,
};
