// Layered version of the component map (components/component-map.astro): who
// uses the receiver on top, the two entries (shell and edge) below it, the new
// component and the others under them, and messaging and storage as the base.
import type { Block, ComponentMap, Link, RowLabel, Zone } from './component-map.ts';

const zones: Zone[] = [
    { id: 'users', title: 'Quem usa', x: 10, y: 10, width: 980, height: 95 },
    { id: 'receiver', title: 'Receptor', subtitle: 'TV 3.0 AoP', x: 10, y: 120, width: 980, height: 370 },
];

const rowLabels: RowLabel[] = [
    { text: 'entradas', y: 190 },
    { text: 'componentes', y: 312 },
    { text: 'base', y: 442 },
];

const blocks: Block[] = [
    {
        id: 'viewer',
        kind: 'node',
        tone: 'screen',
        title: 'Espectador',
        subtitle: 'a TV no navegador',
        x: 160,
        y: 30,
        width: 240,
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
        x: 460,
        y: 30,
        width: 240,
        height: 55,
        detailTitle: 'Aplicação de emissora',
        detail: 'Cliente local associado: veio do sinal, roda na camada de gráficos da casca e chama as '
            + 'APIs pela porta 44642 da borda.',
    },
    {
        id: 'device',
        kind: 'node',
        title: 'Aparelho na rede',
        subtitle: 'celular, tablet, dispositivo remoto',
        x: 740,
        y: 30,
        width: 220,
        height: 55,
        detailTitle: 'Aparelho na rede',
        detail: 'Um celular, tablet ou computador da rede, ou um dispositivo remoto. Acha a TV pela '
            + 'descoberta SSDP e chama as APIs pela borda.',
    },
    {
        id: 'shell',
        kind: 'node',
        tone: 'platform',
        title: 'Casca da plataforma · aop-shell',
        subtitle: 'camadas de vídeo, gráficos e interface',
        x: 160,
        y: 150,
        width: 360,
        height: 70,
        detailTitle: 'Casca da plataforma (aop-shell)',
        detail: 'Monta a tela: as camadas de vídeo, de gráficos e de interface da plataforma, cada uma '
            + 'um quadro que mostra uma URL. Assina na mensageria o que mostrar em cada camada e guarda '
            + 'no Redis os perfis. É por ela que algo visual chega ao espectador.',
    },
    {
        id: 'edge',
        kind: 'node',
        title: 'Borda · edgegateway',
        subtitle: 'APIs da norma · 44642 e 44643',
        x: 600,
        y: 150,
        width: 360,
        height: 70,
        detailTitle: 'Borda (edgegateway)',
        detail: 'A entrada única das APIs da norma: 44642 em HTTP, porta fixada pela norma, e 44643 em '
            + 'HTTPS. Confere as credenciais e encaminha a rota ao serviço que a responde. É por ela '
            + 'que uma API chega a quem usa.',
    },
    {
        id: 'component',
        kind: 'new',
        title: 'Seu componente',
        x: 260,
        y: 250,
        width: 440,
        height: 115,
        detailTitle: 'Seu componente',
        detail: 'Um serviço novo, criado a partir de <code>templates/componente/</code>. Apoia-se na '
            + 'mensageria e no armazenamento e chega a quem usa por uma das entradas: pela casca, se '
            + 'mostra algo na tela; pela borda, se implementa uma API da norma.',
    },
    {
        id: 'screen',
        kind: 'node',
        parent: 'component',
        tone: 'screen',
        title: 'Tela',
        subtitle: 'página HTTP',
        x: 280,
        y: 290,
        width: 190,
        height: 55,
        detailTitle: 'Tela do componente',
        detail: 'Uma página HTTP servida pelo componente, numa porta que o navegador alcança. A casca '
            + 'a mostra numa das camadas.',
    },
    {
        id: 'api',
        kind: 'node',
        parent: 'component',
        tone: 'webservices',
        title: 'API',
        subtitle: 'rota do Anexo C',
        x: 500,
        y: 290,
        width: 180,
        height: 55,
        detailTitle: 'API do componente',
        detail: 'Uma API dos TV 3.0 WebServices que o componente responde. Quem usa a chama pela borda, '
            + 'que confere a credencial antes de encaminhar.',
    },
    {
        id: 'others',
        kind: 'node',
        title: 'Outros componentes',
        subtitle: 'tv3ws e os demais',
        x: 770,
        y: 280,
        width: 190,
        height: 65,
        detailTitle: 'Outros componentes',
        detail: 'Os serviços que já existem, como os TV 3.0 WebServices (<code>tv3ws</code>). O seu '
            + 'componente fala com eles só pela mensageria e pelo armazenamento, nunca diretamente.',
    },
    {
        id: 'broker',
        kind: 'bus',
        tone: 'mqtt',
        title: 'Mensageria · broker MQTT (mqtt-broker)',
        titleX: 380,
        x: 150,
        y: 395,
        width: 820,
        height: 30,
        detailTitle: 'Mensageria: broker MQTT (mqtt-broker)',
        detail: 'Avisa que algo aconteceu: quem quer saber assina o tópico, e quem publica não sabe quem '
            + 'assina. Os componentes o alcançam pelo nome <code>mqtt-broker</code>, na porta 1883. Um '
            + 'plugin confere cada publicação contra o esquema declarado do tópico.',
    },
    {
        id: 'redis',
        kind: 'bus',
        tone: 'state',
        title: 'Armazenamento · Redis',
        titleX: 380,
        x: 150,
        y: 445,
        width: 820,
        height: 30,
        detailTitle: 'Armazenamento: Redis',
        detail: 'Guarda o dado que alguém precisa consultar, num armazenamento único para todo o '
            + 'testbed. Cada família de chaves tem um dono e um esquema declarado, e a escrita passa '
            + 'por funções do próprio Redis, que conferem o formato.',
    },
];

const links: Link[] = [
    {
        id: 'layers-viewer',
        channel: 'http',
        ends: ['viewer', 'shell'],
        path: 'M280 85 V150',
        detailTitle: 'Espectador → casca',
        detail: 'A página da TV, com as camadas, vem da casca, na porta 8080. A página também assina a '
            + 'mensageria, pelo caminho <code>/mqtt</code> da casca.',
    },
    {
        id: 'layers-app',
        channel: 'http',
        ends: ['app', 'edge'],
        path: 'M650 85 V150',
        detailTitle: 'Aplicação de emissora → borda',
        detail: 'Pela 44642, sem credencial: a borda a reconhece pelo <code>Origin</code>.',
    },
    {
        id: 'layers-device',
        channel: 'http',
        ends: ['device', 'edge'],
        path: 'M850 85 V150',
        detailTitle: 'Aparelho na rede → borda',
        detail: 'A autorização pela 44642; as demais APIs pela 44643, em HTTPS, com o accessToken.',
    },
    {
        id: 'layers-screen',
        channel: 'http',
        ends: ['shell', 'screen'],
        path: 'M400 220 V290',
        detailTitle: 'Casca → tela do componente: uma URL numa camada',
        detail: 'O componente publica a URL da página em <code>aop/display/layers/rxgui</code> (camada '
            + 'de interface) ou <code>aop/display/layers/graphics</code> (camada de gráficos), e a casca '
            + 'a abre nessa camada. Quem busca a página é o navegador, direto na porta do componente. '
            + 'Hoje as teclas não chegam a uma página de outra origem na camada de interface.',
    },
    {
        id: 'layers-api',
        channel: 'http',
        ends: ['edge', 'api'],
        path: 'M640 220 V290',
        planned: true,
        label: { text: 'ainda não', x: 600, y: 268 },
        detailTitle: 'Borda → API do componente: ainda não',
        detail: 'Hoje a borda entrega todas as rotas ao <code>tv3ws</code>, e uma API nova entra nele. '
            + 'Os princípios do testbed preveem que a borda encaminhe cada rota ao serviço que responde '
            + 'por ela.',
    },
    {
        id: 'layers-shell-mqtt',
        channel: 'mqtt',
        ends: ['shell', 'broker'],
        path: 'M175 220 V395',
        detailTitle: 'Casca ↔ mensageria',
        detail: 'Assina o que mostrar em cada camada e a sinalização dos serviços; publica o serviço e o '
            + 'usuário correntes e o estado da aplicação de emissora.',
    },
    {
        id: 'layers-shell-state',
        channel: 'state',
        ends: ['shell', 'redis'],
        path: 'M200 220 V445',
        detailTitle: 'Casca ↔ Redis',
        detail: 'Perfis, a lista de origens das aplicações associadas e os serviços anunciados.',
    },
    {
        id: 'layers-edge-state',
        channel: 'state',
        ends: ['edge', 'redis'],
        path: 'M730 220 V445',
        detailTitle: 'Borda ↔ Redis',
        detail: 'As chaves do bind-token: gravadas quando a emissora as registra e lidas a cada '
            + 'validação. A borda não usa a mensageria.',
    },
    {
        id: 'layers-component-mqtt',
        channel: 'mqtt',
        ends: ['component', 'broker'],
        path: 'M420 365 V395',
        detailTitle: 'Seu componente ↔ mensageria',
        detail: 'Assina só os tópicos que lhe interessam e publica nos seus, com o esquema declarado. '
            + 'É também por aqui que ele pede à casca para mostrar a sua tela.',
    },
    {
        id: 'layers-component-state',
        channel: 'state',
        ends: ['component', 'redis'],
        path: 'M560 365 V445',
        detailTitle: 'Seu componente ↔ Redis',
        detail: 'As chaves da família que ele declara como dono, gravadas pelas funções do Redis.',
    },
    {
        id: 'layers-others-mqtt',
        channel: 'mqtt',
        ends: ['others', 'broker'],
        path: 'M820 345 V395',
        detailTitle: 'Outros componentes ↔ mensageria',
        detail: 'O que eles publicam, o seu componente pode assinar, e vice-versa.',
    },
    {
        id: 'layers-others-state',
        channel: 'state',
        ends: ['others', 'redis'],
        path: 'M900 345 V445',
        detailTitle: 'Outros componentes ↔ Redis',
        detail: 'Cada um grava só as famílias de que é dono, e qualquer um pode ler.',
    },
];

export const layeredMap: ComponentMap = {
    width: 1000,
    height: 500,
    zones,
    rowLabels,
    blocks,
    links,
};
