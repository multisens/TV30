// The MQTT topics of the testbed, for the tree of the Mensageria page.
import type { TreeEntry, NameTree } from './name-tree.ts';

const RETAINED = 'retido';
const NO_SCHEMA = 'sem esquema';
const NO_PUBLISHER = 'sem publicador';
const NONE = '—';
const SCHEMA_YES = 'sim: o broker recusa a mensagem fora dele';
const SCHEMA_NO = 'não: o broker não confere a mensagem';
const TV_PAGE = 'página da TV';
const CC = '<code>aop-cc</code>';

interface TopicFacts {
    name: string;
    publisher: string;
    subscriber: string;
    retained: string;
    schema: boolean;
    carries: string;
}

function topic(facts: TopicFacts): TreeEntry {
    const badges: string[] = [];
    if (facts.retained === 'sim') {
        badges.push(RETAINED);
    }
    if (!facts.schema) {
        badges.push(NO_SCHEMA);
    }
    if (facts.publisher.startsWith(NONE)) {
        badges.push(NO_PUBLISHER);
    }
    return {
        name: facts.name,
        badges,
        facts: [
            { label: 'Publica', value: facts.publisher },
            { label: 'Assina', value: facts.subscriber },
            { label: 'Retido', value: facts.retained },
            { label: 'Esquema', value: facts.schema ? SCHEMA_YES : SCHEMA_NO },
        ],
        detail: facts.carries,
    };
}

export const mqttTopics: NameTree = {
    separator: '/',
    entries: [
        topic({
            name: 'aop/currentUser',
            publisher: 'casca; <code>tv3ws</code>, na C.6.14.4',
            subscriber: 'casca, <code>tv3ws</code>',
            retained: 'sim',
            schema: true,
            carries: 'O id do perfil corrente. Fica vazio depois da remoção do perfil corrente, até a '
                + 'escolha no seletor.',
        }),
        topic({
            name: 'aop/removedUser',
            publisher: 'casca',
            subscriber: NONE,
            retained: 'não',
            schema: true,
            carries: 'O id do perfil que o espectador removeu no seletor, publicado depois da remoção.',
        }),
        topic({
            name: 'aop/currentService',
            publisher: 'casca',
            subscriber: 'casca, <code>tv3ws</code>',
            retained: 'sim',
            schema: true,
            carries: 'O <code>globalServiceId</code> do serviço DTV corrente.',
        }),
        topic({
            name: 'aop/services',
            publisher: 'casca',
            subscriber: NONE,
            retained: 'sim',
            schema: true,
            carries: 'Os serviços anunciados na LLS, um '
                + '<code>{"serviceContextId": "&lt;globalServiceId&gt;"}</code> por serviço; '
                + '<code>[]</code>, nenhum. O mesmo conteúdo de <code>services:announced</code>, '
                + 'no Redis.',
        }),
        topic({
            name: 'aop/display/layers/rxgui',
            publisher: 'casca',
            subscriber: TV_PAGE,
            retained: 'não',
            schema: true,
            carries: 'A tela da camada de interface.',
        }),
        topic({
            name: 'aop/display/layers/graphics',
            publisher: 'casca',
            subscriber: TV_PAGE,
            retained: 'não',
            schema: true,
            carries: 'A URL da aplicação na camada de gráficos, no host próprio da aplicação. Vazio '
                + 'encerra a aplicação.',
        }),
        topic({
            name: 'aop/display/layers/video/url',
            publisher: 'casca',
            subscriber: TV_PAGE,
            retained: 'não',
            schema: true,
            carries: 'A URL do vídeo.',
        }),
        topic({
            name: 'aop/display/layers/video/size',
            publisher: 'casca',
            subscriber: TV_PAGE,
            retained: 'não',
            schema: true,
            carries: 'A posição e o tamanho do vídeo.',
        }),
        topic({
            name: 'aop/display/layers/popup/yesno/message',
            publisher: '<code>tv3ws</code>',
            subscriber: TV_PAGE,
            retained: 'não',
            schema: false,
            carries: 'O pedido de autorização de um cliente ao espectador.',
        }),
        topic({
            name: 'aop/display/layers/popup/yesno/response',
            publisher: TV_PAGE,
            subscriber: '<code>tv3ws</code>',
            retained: 'não',
            schema: false,
            carries: 'A resposta do espectador: <code>true</code>, ou <code>false</code> no "Não" e '
                + 'no tempo esgotado.',
        }),
        topic({
            name: 'aop/display/layers/popup/qrcode',
            publisher: '<code>tv3ws</code>',
            subscriber: TV_PAGE,
            retained: 'não',
            schema: false,
            carries: 'O QR code do pareamento do cliente não local (C.4.3): '
                + '<code>{value, timeout}</code> abre, <code>{"close":true}</code> fecha.',
        }),
        topic({
            name: 'aop/display/layers/popup/pin',
            publisher: '<code>tv3ws</code>',
            subscriber: TV_PAGE,
            retained: 'não',
            schema: false,
            carries: 'O PIN do pareamento do cliente não local (C.4.3): '
                + '<code>{value, timeout}</code> abre, <code>{"close":true}</code> fecha.',
        }),
        topic({
            name: 'aop/display/layers/popup/info',
            publisher: '<code>tv3ws</code>',
            subscriber: TV_PAGE,
            retained: 'não',
            schema: false,
            carries: 'O aviso de que a emissora gravou atributos do perfil (C.6.14.5): '
                + '<code>{value, timeout}</code>. Não pede resposta.',
        }),
        topic({
            name: 'aop/application-lifecycle-manager/application-state',
            publisher: '<code>aop-cc</code>',
            subscriber: '<code>tv3ws</code>',
            retained: 'não',
            schema: true,
            carries: '<code>{serviceContextId, appId, origin, state}</code>, com <code>state</code> '
                + 'em <code>started</code> ou <code>ended</code>. Numa troca, o <code>ended</code> da '
                + 'aplicação que sai vem antes do <code>started</code> da que entra.',
        }),
        topic({
            name: 'aop/application-lifecycle-manager/graphics-application',
            publisher: '<code>aop-cc</code>',
            subscriber: 'casca',
            retained: 'sim',
            schema: true,
            carries: 'A aplicação de emissora da camada de gráficos: '
                + '<code>{serviceContextId, appId, origin, url}</code>. Vazio: a Bootstrap Application '
                + 'do serviço sintonizado volta.',
        }),
        topic({
            name: 'aop/application-lifecycle-manager/present-applications',
            publisher: '<code>aop-cc</code>',
            subscriber: NONE,
            retained: 'sim',
            schema: true,
            carries: 'As aplicações <code>PRESENT</code> e <code>STORED_PRESENT</code> do serviço '
                + 'sintonizado, que o espectador poderia iniciar pelo Access Panel, que não existe.',
        }),
        topic({
            name: 'aop/application-lifecycle-manager/end-request',
            publisher: 'casca',
            subscriber: '<code>aop-cc</code>',
            retained: 'não',
            schema: true,
            carries: 'O pedido do espectador para encerrar a aplicação de emissora: o Back que a aplicação '
                + 'não cancelou, ou a tecla Home. <code>{serviceContextId, appId}</code>.',
        }),
        topic({
            name: 'aop/access-panel/client-blocked',
            publisher: '— (o painel de acesso não existe; os testes publicam)',
            subscriber: '<code>tv3ws</code>',
            retained: 'não',
            schema: true,
            carries: 'O <code>clientid</code> do cliente bloqueado pelo espectador (C.4.2.2). O '
                + '<code>tv3ws</code> libera os recursos do cliente.',
        }),
        topic({
            name: 'aop/<sid>/<appId>/doc/…',
            publisher: '<code>tv3ws</code>',
            subscriber: '<code>tv3ws</code>',
            retained: 'misto: <code>.../user</code> e <code>.../value</code> retidos, '
                + '<code>.../eventNotification</code> não',
            schema: false,
            carries: 'O estado dos nós do documento da aplicação, trocado com os dispositivos remotos.',
        }),
        topic({
            name: 'aop/devices/<classe>',
            publisher: '<code>tv3ws</code>',
            subscriber: NONE,
            retained: 'sim',
            schema: false,
            carries: 'Os <em>handles</em> dos dispositivos remotos registrados na classe, regravados a '
                + 'cada registro e remoção. Vazio quando a classe fica sem dispositivo.',
        }),
        topic({
            name: 'tlm/lls/<bsid>/slt',
            publisher: CC,
            subscriber: 'casca, <code>aop-cc</code>',
            retained: 'sim',
            schema: true,
            carries: 'A SLT do canal RF <code>&lt;bsid&gt;</code>, como a emissora a serve, em JSON. '
                + 'Vazio: o canal saiu.',
        }),
        topic({
            name: 'tlm/lls/<bsid>/bamt',
            publisher: CC,
            subscriber: 'casca',
            retained: 'sim',
            schema: true,
            carries: 'A BAMT do canal, com um BAM por serviço. O catálogo se monta dela e da SLT.',
        }),
        topic({
            name: 'tlm/scan',
            publisher: CC,
            subscriber: 'casca',
            retained: 'sim',
            schema: true,
            carries: '<code>{completedAt, rfChannels}</code>: o fim de uma varredura da LLS e os canais '
                + 'achados.',
        }),
        topic({
            name: 'tlm/sls/<serviceId>/usbd',
            publisher: CC,
            subscriber: '<code>aop-cc</code>',
            retained: 'sim',
            schema: true,
            carries: 'A USBD do serviço, com os <code>BasePattern</code> de radiodifusão e de banda larga.',
        }),
        topic({
            name: 'tlm/sls/<serviceId>/stsid',
            publisher: CC,
            subscriber: '<code>aop-cc</code>, <code>tv3ws</code>',
            retained: 'sim',
            schema: true,
            carries: 'A S-TSID do serviço: os fluxos e os arquivos do carrossel, com o '
                + '<code>appContextIdList</code> e o tamanho de cada arquivo.',
        }),
        topic({
            name: 'tlm/sls/<serviceId>/mpd',
            publisher: CC,
            subscriber: 'casca, só a do serviço selecionado',
            retained: 'sim',
            schema: true,
            carries: 'A MPD do serviço, em XML, a única na forma da norma. Muda a cada segmento novo.',
        }),
        topic({
            name: 'tlm/sls/<serviceId>/bald',
            publisher: CC,
            subscriber: '<code>aop-cc</code>, <code>tv3ws</code>',
            retained: 'sim',
            schema: true,
            carries: 'A BALD do serviço: as aplicações de emissora, com o <code>controlCode</code> e os '
                + 'pontos de entrada de cada uma.',
        }),
        topic({
            name: 'tlm/sls/<serviceId>/prrd',
            publisher: CC,
            subscriber: NONE,
            retained: 'sim',
            schema: true,
            carries: 'A PRRD do serviço, quando declarada.',
        }),
        topic({
            name: 'tlm/emission/<serviceId>',
            publisher: CC,
            subscriber: '<code>aop-cc</code>',
            retained: 'sim',
            schema: true,
            carries: 'O descritor de emissão de um serviço com carrossel: o período e a ordem de cada '
                + 'objeto, de onde a comporta conta as passagens.',
        }),
        topic({
            name: 'tlm/tuned',
            publisher: 'casca',
            subscriber: '<code>aop-cc</code>, <code>tv3ws</code>',
            retained: 'sim',
            schema: true,
            carries: '<code>{serviceId, rfChannelId, tunedAt}</code>: o serviço sintonizado ao abrir a '
                + 'Bootstrap Application. Vazio: nenhum.',
        }),
        topic({
            name: 'tlm/object/<serviceId>/available',
            publisher: CC,
            subscriber: '<code>aop-cc</code>',
            retained: 'não',
            schema: true,
            carries: 'Um objeto do carrossel do serviço sintonizado ficou disponível, ou passou com '
                + '<code>lastModified</code> novo.',
        }),
        topic({
            name: 'tlm/object/<serviceId>/expired',
            publisher: CC,
            subscriber: '<code>aop-cc</code>',
            retained: 'não',
            schema: true,
            carries: 'Um objeto do carrossel do serviço sintonizado deixou de estar disponível.',
        }),
        topic({
            name: 'video/event',
            publisher: NONE,
            subscriber: TV_PAGE,
            retained: 'não',
            schema: true,
            carries: 'Um evento do fluxo, repassado à aplicação da camada de gráficos como '
                + '<code>stream_event</code>.',
        }),
        topic({
            name: 'errors/<client_id>',
            publisher: 'o plugin do broker',
            subscriber: NONE,
            retained: 'não',
            schema: false,
            carries: 'A recusa de uma publicação daquele cliente '
                + '(<a href="#erro-de-validação">Erro de validação</a>).',
        }),
        topic({
            name: 'tv30/<nome>/exemplo/ping',
            publisher: 'os testes do modelo de componente',
            subscriber: 'o exemplo do modelo de componente',
            retained: 'não',
            schema: false,
            carries: 'O pedido do exemplo do '
                + '<a href="../estender-com-componente/">modelo de componente</a>.',
        }),
        topic({
            name: 'tv30/<nome>/exemplo/pong',
            publisher: 'o exemplo do modelo de componente',
            subscriber: 'os testes do modelo de componente',
            retained: 'não',
            schema: false,
            carries: 'A resposta do exemplo, com o valor da chave <code>tv30:&lt;nome&gt;:exemplo</code> '
                + 'do Redis.',
        }),
    ],
};
