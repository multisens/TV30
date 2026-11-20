// Steps of the scene "Do sinal à tela" of the page "Camada de transporte
// simulada" (components/transport-scene.astro): service 1002 of the example,
// from the scan to the Esc of the viewer. Each step has the messages that run
// between the blocks, in order, and what the TV screen shows at its end.

export type SceneNode = 'bcast' | 'acquisition' | 'proxy' | 'lifecycle' | 'broker' | 'shell' | 'app';

export type SceneChannel = 'http' | 'mqtt' | 'internal';

export interface SceneHop {
    from: SceneNode;
    to: SceneNode;
    label: string;
    channel: SceneChannel;
}

export interface SceneScreen {
    view: 'search' | 'catalog' | 'bootstrap' | 'application';
    selected: boolean;
    carousel: 'none' | 'passing' | 'passed';
    key: boolean;
}

export interface SceneStep {
    id: string;
    title: string;
    detail: string;
    hops: SceneHop[];
    screen: SceneScreen;
}

const CATALOG: SceneScreen = { view: 'catalog', selected: false, carousel: 'none', key: false };

export const SCENE_STEPS: SceneStep[] = [
    {
        id: 'lls',
        title: 'Varredura da LLS',
        detail: 'A cada <code>llsCyclePeriod</code> do canal (5 s no exemplo), a aquisição busca a SLT e '
            + 'a BAMT de todos os canais RF. É a varredura que, no receptor, percorre as frequências e '
            + 'lê a LLS de cada uma. A TV ainda não conhece nenhum serviço.',
        hops: [
            { from: 'acquisition', to: 'bcast', label: 'GET /signaling/lls', channel: 'http' },
            { from: 'bcast', to: 'acquisition', label: 'SLT e BAMT', channel: 'http' },
        ],
        screen: { view: 'search', selected: false, carousel: 'none', key: false },
    },
    {
        id: 'lls-topics',
        title: 'A LLS na mensageria',
        detail: 'Cada tabela cuja <code>LLS_table_version</code> mudou vai para o tópico dela, retida. '
            + 'A casca assina os tópicos e monta o catálogo com os serviços da SLT e a aplicação '
            + 'bootstrap de cada um, descrita na BAMT.',
        hops: [
            { from: 'acquisition', to: 'broker', label: 'tlm/lls/10/slt, bamt', channel: 'mqtt' },
            { from: 'broker', to: 'shell', label: 'tlm/lls/10/slt, bamt', channel: 'mqtt' },
        ],
        screen: CATALOG,
    },
    {
        id: 'sls',
        title: 'A SLS de cada serviço',
        detail: 'Para cada serviço da SLT, a aquisição pede o descritor de emissão. O 1002 tem '
            + 'carrossel: a SLS chega como objeto dele, e a aquisição a pede à comporta no fim de cada '
            + 'passagem do canal de sinalização (a cada 3 s no exemplo). Os fragmentos — USBD, S-TSID, '
            + 'MPD e BALD — vão cada um para o seu tópico.',
        hops: [
            { from: 'acquisition', to: 'bcast', label: 'GET /signaling/emission/1002', channel: 'http' },
            { from: 'acquisition', to: 'proxy', label: 'GET /svc/1002/sls', channel: 'internal' },
            { from: 'proxy', to: 'bcast', label: 'pacote SLS', channel: 'http' },
            { from: 'acquisition', to: 'broker', label: 'tlm/sls/1002/…', channel: 'mqtt' },
        ],
        screen: CATALOG,
    },
    {
        id: 'tuned',
        title: 'A sintonia',
        detail: 'O espectador escolhe o 1002 no catálogo. A casca publica '
            + '<code>{serviceId, rfChannelId, tunedAt}</code>. Daí em diante, a comporta só serve o '
            + 'serviço sintonizado, e só o que passou inteiro no carrossel depois de '
            + '<code>tunedAt</code>.',
        hops: [
            { from: 'shell', to: 'broker', label: 'tlm/tuned', channel: 'mqtt' },
            { from: 'broker', to: 'proxy', label: 'tlm/tuned', channel: 'mqtt' },
            { from: 'broker', to: 'lifecycle', label: 'tlm/tuned', channel: 'mqtt' },
        ],
        screen: { view: 'catalog', selected: true, carousel: 'none', key: false },
    },
    {
        id: 'video',
        title: 'A aplicação bootstrap e o vídeo',
        detail: 'A casca abre a aplicação bootstrap do serviço, que toca o vídeo. O reprodutor DASH lê '
            + 'a MPD que veio na SLS e pede os segmentos à comporta, que os busca no '
            + '<code>bcast-sim</code>. No serviço de banda larga, os segmentos vêm direto do '
            + '<code>bcast-sim</code>.',
        hops: [
            { from: 'shell', to: 'proxy', label: 'GET /svc/1002/live/…', channel: 'http' },
            { from: 'proxy', to: 'bcast', label: 'segmentos', channel: 'http' },
            { from: 'proxy', to: 'shell', label: 'segmentos', channel: 'http' },
        ],
        screen: { view: 'bootstrap', selected: true, carousel: 'none', key: false },
    },
    {
        id: 'carousel',
        title: 'O pacote da aplicação passa no carrossel',
        detail: 'A BALD do 1002 traz uma aplicação <code>AUTOSTART</code> no pacote <code>app.pkg</code>, '
            + 'que passa no carrossel a cada 10 s. Quem sintonizou no meio de uma passagem espera a '
            + 'seguinte: a comporta conta as passagens pelo relógio, e até o fim de uma passagem '
            + 'completa o pacote responde 404.',
        hops: [
            { from: 'bcast', to: 'proxy', label: 'passagem de app.pkg', channel: 'internal' },
        ],
        screen: { view: 'bootstrap', selected: true, carousel: 'passing', key: false },
    },
    {
        id: 'available',
        title: 'O pacote chegou',
        detail: 'No fim da primeira passagem completa de <code>app.pkg</code> depois da sintonia, a '
            + 'comporta anuncia o objeto. O gerente de ciclo de vida, que esperava o ponto de entrada da '
            + 'aplicação <code>AUTOSTART</code>, decide lançá-la.',
        hops: [
            { from: 'proxy', to: 'broker', label: 'tlm/object/1002/available', channel: 'mqtt' },
            { from: 'broker', to: 'lifecycle', label: 'tlm/object/1002/available', channel: 'mqtt' },
        ],
        screen: { view: 'bootstrap', selected: true, carousel: 'passed', key: false },
    },
    {
        id: 'launch',
        title: 'O lançamento',
        detail: 'O gerente grava a origem em <code>origins:associated</code> e publica '
            + '<code>{serviceContextId, appId, origin, url}</code>. A casca fecha a aplicação bootstrap, '
            + 'põe o vídeo em tela cheia e carrega a URL na camada de gráficos.',
        hops: [
            { from: 'lifecycle', to: 'broker', label: 'graphics-application', channel: 'mqtt' },
            { from: 'broker', to: 'shell', label: 'graphics-application', channel: 'mqtt' },
            { from: 'shell', to: 'app', label: 'carrega a URL', channel: 'internal' },
        ],
        screen: { view: 'application', selected: true, carousel: 'passed', key: false },
    },
    {
        id: 'document',
        title: 'A aplicação, na origem dela',
        detail: 'O navegador pede o documento à comporta, na origem do contexto da aplicação '
            + '(<code>ctx-&lt;h&gt;</code>). O arquivo sai do pacote <code>app.pkg</code>, com a ponte de '
            + 'teclas <code>/.tv30/bridge.js</code> inserida antes de <code>&lt;/head&gt;</code>.',
        hops: [
            { from: 'app', to: 'proxy', label: 'GET ctx-<h>…/index.html', channel: 'http' },
            { from: 'proxy', to: 'app', label: 'index.html + ponte', channel: 'http' },
        ],
        screen: { view: 'application', selected: true, carousel: 'passed', key: false },
    },
    {
        id: 'back',
        title: 'O Esc do espectador',
        detail: 'A casca captura o Esc e o entrega à aplicação como <code>BrowserBack</code>, por '
            + '<code>postMessage</code>. A aplicação não cancela a tecla, e a ponte a devolve à casca, '
            + 'que pede o encerramento ao gerente. O gerente publica <code>ended</code> e a '
            + '<code>graphics-application</code> vazia, e a aplicação bootstrap volta.',
        hops: [
            { from: 'shell', to: 'app', label: 'BrowserBack', channel: 'internal' },
            { from: 'app', to: 'shell', label: 'tv30-aop-back', channel: 'internal' },
            { from: 'shell', to: 'broker', label: 'end-request', channel: 'mqtt' },
            { from: 'broker', to: 'lifecycle', label: 'end-request', channel: 'mqtt' },
            { from: 'lifecycle', to: 'broker', label: 'ended', channel: 'mqtt' },
            { from: 'broker', to: 'shell', label: 'graphics-application vazia', channel: 'mqtt' },
        ],
        screen: { view: 'bootstrap', selected: true, carousel: 'passed', key: true },
    },
];
