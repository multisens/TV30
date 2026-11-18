// Types of the component map (components/component-map.astro) and the
// first version of the map: the containers of the testbed, who uses them and
// the channel of each link. Coordinates are in the units of the SVG viewBox.

export type Channel = 'http' | 'mqtt' | 'state' | 'websocket';

export type BlockKind = 'node' | 'bus' | 'group' | 'new';

export type Tone = 'platform' | 'webservices' | 'screen' | 'app' | 'mqtt' | 'state';

export interface Zone {
    id: string;
    title: string;
    subtitle?: string;
    x: number;
    y: number;
    width: number;
    height: number;
}

export interface Block {
    id: string;
    kind: BlockKind;
    parent?: string;
    tone?: Tone;
    title: string;
    titleX?: number;
    subtitle?: string;
    x: number;
    y: number;
    width: number;
    height: number;
    detailTitle: string;
    detail: string;
}

export interface Link {
    id: string;
    channel: Channel;
    ends: [string, string];
    path: string;
    planned?: boolean;
    label?: { text: string; x: number; y: number };
    detailTitle: string;
    detail: string;
}


export const CHANNEL_LABELS: Record<Channel, string> = {
    http: 'HTTP',
    mqtt: 'mensageria (MQTT)',
    state: 'armazenamento (Redis)',
    websocket: 'WebSocket',
};

export interface RowLabel {
    text: string;
    y: number;
}

export interface ComponentMap {
    width: number;
    height: number;
    zones: Zone[];
    rowLabels: RowLabel[];
    blocks: Block[];
    links: Link[];
}

const zones: Zone[] = [
    { id: 'broadcaster', title: 'Emissora simulada', x: 10, y: 20, width: 155, height: 420 },
    { id: 'receiver', title: 'Receptor · TV 3.0 AoP', x: 185, y: 20, width: 610, height: 420 },
    { id: 'users', title: 'Quem usa', x: 815, y: 20, width: 175, height: 420 },
];

const blocks: Block[] = [
    {
        id: 'bcast',
        kind: 'node',
        title: 'bcast',
        subtitle: 'serviços de exemplo',
        x: 25,
        y: 220,
        width: 125,
        height: 70,
        detailTitle: 'Emissora simulada (bcast)',
        detail: 'Publica na mensageria a sinalização dos serviços (BAMT, ESG e BALD, retidas) e os '
            + 'eventos do vídeo, e serve por HTTP as aplicações de emissora e o vídeo em HLS. Não usa '
            + 'o Redis. Está planejado o caminho da norma, em que a emissora serve a sinalização e a '
            + 'plataforma vai buscá-la.',
    },
    {
        id: 'broker',
        kind: 'bus',
        tone: 'mqtt',
        title: 'Broker MQTT · mosquitto',
        x: 205,
        y: 120,
        width: 570,
        height: 30,
        detailTitle: 'Broker MQTT (mosquitto)',
        detail: 'A mensageria da plataforma: quem publica não sabe quem assina. Os componentes o '
            + 'alcançam pelo nome <code>mosquitto</code>, na porta 1883. Um plugin confere cada '
            + 'publicação contra o esquema declarado do tópico e recusa a que não o satisfaz; tópico '
            + 'sem esquema passa sem conferência.',
    },
    {
        id: 'aop',
        kind: 'node',
        tone: 'platform',
        title: 'aop',
        subtitle: 'casca da plataforma',
        x: 205,
        y: 220,
        width: 130,
        height: 70,
        detailTitle: 'Casca da plataforma (aop)',
        detail: 'Serve a página da TV na porta 8080 e monta as telas a partir do que lê na mensageria. '
            + 'Grava no Redis os perfis e as origens das aplicações em execução. Busca no bcast as aplicações e o vídeo e '
            + 'os entrega à página, cada aplicação na sua própria origem '
            + '(<code>&lt;app&gt;.apps.localhost:8080</code>).',
    },
    {
        id: 'component',
        kind: 'new',
        title: 'Seu componente',
        subtitle: 'a partir do modelo',
        x: 350,
        y: 220,
        width: 125,
        height: 70,
        detailTitle: 'Seu componente',
        detail: 'Um serviço novo, criado a partir de <code>templates/componente/</code>. Ele se liga '
            + 'ao broker e ao Redis como os outros e não chama nenhum deles diretamente. Hoje ainda '
            + 'não atende API pela borda.',
    },
    {
        id: 'tv3ws',
        kind: 'node',
        tone: 'webservices',
        title: 'tv3ws',
        subtitle: 'TV 3.0 WebServices',
        x: 490,
        y: 220,
        width: 120,
        height: 70,
        detailTitle: 'TV 3.0 WebServices (tv3ws)',
        detail: 'As APIs do Anexo C. Recebe HTTP só pela borda: as portas dele não são publicadas. '
            + 'Assina na mensageria o serviço corrente, o usuário corrente e o estado da aplicação, e '
            + 'publica os pedidos de autorização que a TV mostra. Guarda no Redis atributos de perfil, '
            + 'credenciais, sessão e dispositivos remotos.',
    },
    {
        id: 'edge',
        kind: 'node',
        title: 'Borda',
        subtitle: 'edgegateway',
        x: 640,
        y: 220,
        width: 135,
        height: 70,
        detailTitle: 'Borda (edgegateway)',
        detail: 'A entrada única das APIs: 44642 em HTTP, porta fixada pela norma, e 44643 em HTTPS. '
            + 'Confere as credenciais e encaminha as rotas ao <code>tv3ws</code>, menos as que ela '
            + 'mesma responde, como o registro das chaves do bind-token (C.6.8). Guarda essas chaves '
            + 'no Redis e as lê a cada validação. Não usa a mensageria.',
    },
    {
        id: 'redis',
        kind: 'bus',
        tone: 'state',
        title: 'Redis · estado da plataforma',
        x: 205,
        y: 400,
        width: 570,
        height: 30,
        detailTitle: 'Redis',
        detail: 'O armazenamento único da plataforma: o dado que alguém precisa consultar. Cada '
            + 'família de chaves tem um dono e um esquema declarado, e a escrita passa por funções '
            + 'do próprio Redis, que conferem o formato.',
    },
    {
        id: 'tv',
        kind: 'group',
        title: 'TV no navegador',
        x: 830,
        y: 45,
        width: 145,
        height: 150,
        detailTitle: 'A TV, no navegador',
        detail: 'Uma página em <code>http://localhost:8080</code>, servida pela casca. Nela ficam as '
            + 'telas da plataforma e, num quadro embutido, a aplicação da emissora.',
    },
    {
        id: 'screens',
        kind: 'node',
        tone: 'screen',
        parent: 'tv',
        title: 'Telas da casca',
        x: 840,
        y: 75,
        width: 125,
        height: 45,
        detailTitle: 'Telas da casca',
        detail: 'Perfis, catálogo e camadas de vídeo e de gráficos. A página fala com a casca por '
            + 'HTTP e assina a mensageria por WebSocket, pelo caminho <code>/mqtt</code> da casca: é '
            + 'assim que recebe as camadas a mostrar e os pedidos de autorização.',
    },
    {
        id: 'app',
        kind: 'node',
        tone: 'app',
        parent: 'tv',
        title: 'App de emissora',
        x: 840,
        y: 135,
        width: 125,
        height: 45,
        detailTitle: 'Aplicação de emissora',
        detail: 'Cliente local associado: veio do sinal e está atada ao serviço em uso. Chama as APIs '
            + 'pela porta 44642 da borda, que a reconhece pelo <code>Origin</code>, sem credencial.',
    },
    {
        id: 'device',
        kind: 'node',
        title: 'Aparelho na rede',
        subtitle: 'cliente não local',
        x: 830,
        y: 225,
        width: 145,
        height: 60,
        detailTitle: 'Aparelho na rede',
        detail: 'Um celular, tablet ou computador. Acha a TV pela descoberta SSDP, cujo anunciante '
            + 'roda no computador, fora dos containers; pede autorização pela 44642 e usa as demais '
            + 'APIs pela 44643, em HTTPS.',
    },
    {
        id: 'remote',
        kind: 'node',
        title: 'Dispositivo remoto',
        subtitle: 'efeitos, NCL 360 VR',
        x: 830,
        y: 315,
        width: 145,
        height: 60,
        detailTitle: 'Dispositivo remoto',
        detail: 'Registra-se pela API de dispositivos remotos, que passa pela borda, e recebe um '
            + 'endereço WebSocket. Daí em diante troca mensagens direto com o <code>tv3ws</code>.',
    },
];

const links: Link[] = [
    {
        id: 'link-screens-http',
        channel: 'http',
        ends: ['screens', 'aop'],
        path: 'M840 88 H270 V220',
        detailTitle: 'Página da TV → casca, por HTTP',
        detail: 'A página, os scripts das telas, as aplicações e o vídeo vêm todos da casca, na porta '
            + '8080.',
    },
    {
        id: 'link-screens-mqtt',
        channel: 'mqtt',
        ends: ['screens', 'aop'],
        path: 'M840 104 H300 V220',
        detailTitle: 'Página da TV ↔ mensageria, pela casca',
        detail: 'A página não alcança o broker direto: a casca repassa o caminho <code>/mqtt</code> '
            + 'ao WebSocket do <code>mosquitto</code>.',
    },
    {
        id: 'link-proxy',
        channel: 'http',
        ends: ['aop', 'bcast'],
        path: 'M205 255 H150',
        detailTitle: 'Casca → bcast, por HTTP',
        detail: 'A casca busca no bcast as aplicações de emissora e o vídeo e os entrega à página.',
    },
    {
        id: 'link-app',
        channel: 'http',
        ends: ['app', 'edge'],
        path: 'M840 165 H705 V220',
        detailTitle: 'Aplicação de emissora → borda',
        detail: 'Pela porta 44642. A borda confere a origem e encaminha ao <code>tv3ws</code>.',
    },
    {
        id: 'link-device',
        channel: 'http',
        ends: ['device', 'edge'],
        path: 'M830 255 H775',
        detailTitle: 'Aparelho na rede → borda',
        detail: 'A autorização pela 44642; as demais APIs pela 44643, em HTTPS, com o accessToken.',
    },
    {
        id: 'link-remote-http',
        channel: 'http',
        ends: ['remote', 'edge'],
        path: 'M830 335 H760 V290',
        detailTitle: 'Dispositivo remoto → borda',
        detail: 'O registro do dispositivo, que devolve o endereço WebSocket.',
    },
    {
        id: 'link-edge',
        channel: 'http',
        ends: ['edge', 'tv3ws'],
        path: 'M640 255 H610',
        detailTitle: 'Borda → tv3ws',
        detail: 'As rotas que a borda não responde chegam ao <code>tv3ws</code> por aqui, já com a '
            + 'credencial conferida.',
    },
    {
        id: 'link-planned',
        channel: 'http',
        ends: ['edge', 'component'],
        path: 'M670 290 V335 H440 V290',
        planned: true,
        label: { text: 'ainda não', x: 475, y: 352 },
        detailTitle: 'Borda → seu componente: ainda não',
        detail: 'Hoje a borda entrega todas as rotas ao <code>tv3ws</code>, e uma API nova entra '
            + 'nele. Os princípios do testbed preveem que a borda encaminhe cada rota ao serviço que '
            + 'responde por ela.',
    },
    {
        id: 'link-bcast-mqtt',
        channel: 'mqtt',
        ends: ['bcast', 'broker'],
        path: 'M87 220 V135 H205',
        detailTitle: 'bcast → mensageria',
        detail: 'A sinalização dos serviços, retida no broker (<code>tlm/lls/…</code>, '
            + '<code>tlm/sls/…</code>), e os eventos do vídeo (<code>video/event</code>).',
    },
    {
        id: 'link-aop-mqtt',
        channel: 'mqtt',
        ends: ['aop', 'broker'],
        path: 'M230 220 V150',
        detailTitle: 'Casca ↔ mensageria',
        detail: 'Assina a sinalização e publica o serviço corrente, o usuário corrente, o estado da '
            + 'aplicação e as camadas a mostrar (<code>aop/…</code>).',
    },
    {
        id: 'link-component-mqtt',
        channel: 'mqtt',
        ends: ['component', 'broker'],
        path: 'M385 220 V150',
        detailTitle: 'Seu componente ↔ mensageria',
        detail: 'Assina só os tópicos que lhe interessam e publica nos seus, com o esquema '
            + 'declarado.',
    },
    {
        id: 'link-tv3ws-mqtt',
        channel: 'mqtt',
        ends: ['tv3ws', 'broker'],
        path: 'M520 220 V150',
        detailTitle: 'tv3ws ↔ mensageria',
        detail: 'Assina o serviço, o usuário e a aplicação correntes; publica os pedidos de '
            + 'autorização e de pareamento e os dispositivos remotos registrados.',
    },
    {
        id: 'link-aop-state',
        channel: 'state',
        ends: ['aop', 'redis'],
        path: 'M250 290 V400',
        detailTitle: 'Casca ↔ Redis',
        detail: 'Perfis, a lista de origens das aplicações associadas e os serviços anunciados.',
    },
    {
        id: 'link-component-state',
        channel: 'state',
        ends: ['component', 'redis'],
        path: 'M400 290 V400',
        detailTitle: 'Seu componente ↔ Redis',
        detail: 'As chaves da família que ele declara como dono, gravadas pelas funções do Redis.',
    },
    {
        id: 'link-tv3ws-state',
        channel: 'state',
        ends: ['tv3ws', 'redis'],
        path: 'M550 290 V400',
        detailTitle: 'tv3ws ↔ Redis',
        detail: 'Atributos de perfil, credenciais dos clientes, sessão (serviço e usuário correntes) '
            + 'e dispositivos remotos registrados.',
    },
    {
        id: 'link-edge-state',
        channel: 'state',
        ends: ['edge', 'redis'],
        path: 'M710 290 V400',
        detailTitle: 'Borda ↔ Redis',
        detail: 'As chaves do bind-token: gravadas quando a emissora as registra e lidas a cada '
            + 'validação.',
    },
    {
        id: 'link-remote-ws',
        channel: 'websocket',
        ends: ['remote', 'tv3ws'],
        path: 'M830 360 H580 V290',
        detailTitle: 'Dispositivo remoto ↔ tv3ws, por WebSocket',
        detail: 'Fora da borda, nas portas 45000 a 45199, só pelo endereço que o registro devolveu.',
    },
];

export const currentMap: ComponentMap = {
    width: 1000,
    height: 460,
    zones,
    rowLabels: [],
    blocks,
    links,
};
