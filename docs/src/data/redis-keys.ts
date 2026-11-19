// The Redis key families of the testbed, for the tree of the Redis page.
import type { TreeEntry, NameTree } from './name-tree.ts';

const OUT_OF_SCHEMA = 'fora do esquema';
const DIRECT_WRITE = 'nenhuma: escrita direta, fora do esquema';
const NO_WRITER = 'sem escritor';
const DECLARED_ONLY = 'nenhuma: família só declarada, sem escritor no testbed';
const NONE = '—';

interface KeyFacts {
    name: string;
    type: string;
    writer: string;
    reader: string;
    // Empty for a key outside the schema or only declared.
    functions: string[];
    // In the schema, with its owner outside the testbed.
    declaredOnly?: boolean;
    holds: string;
}

function family(facts: KeyFacts): TreeEntry {
    const badges = [facts.type];
    const inSchema = facts.functions.length > 0;
    let functions = facts.functions.map((name) => `<code>${name}</code>`).join(', ');
    if (facts.declaredOnly === true) {
        badges.push(NO_WRITER);
        functions = DECLARED_ONLY;
    } else if (!inSchema) {
        badges.push(OUT_OF_SCHEMA);
        functions = DIRECT_WRITE;
    }
    return {
        name: facts.name,
        badges,
        facts: [
            { label: 'Tipo', value: facts.type },
            { label: 'Escreve', value: facts.writer },
            { label: 'Lê', value: facts.reader },
            { label: 'Funções', value: functions },
        ],
        detail: facts.holds,
    };
}

export const redisKeys: NameTree = {
    separator: ':',
    entries: [
        family({
            name: 'session:current-user',
            type: 'STRING',
            writer: '<code>tv3ws</code>',
            reader: '<code>tv3ws</code>',
            functions: ['tv30_session_user'],
            holds: 'O id do perfil corrente, espelho do tópico <code>aop/currentUser</code>; vazio, '
                + 'nenhum. Até 64 caracteres.',
        }),
        family({
            name: 'session:current-service-id',
            type: 'STRING',
            writer: '<code>tv3ws</code>',
            reader: '<code>tv3ws</code>; borda, no bind-token e na C.6.8; casca, na criação de perfil',
            functions: ['tv30_session_service_id'],
            holds: 'O id do serviço corrente, espelho do tópico <code>aop/currentService</code>; '
                + 'vazio, nenhum. Até 256 caracteres.',
        }),
        family({
            name: 'session:current-service',
            type: 'HASH',
            writer: '<code>tv3ws</code>',
            reader: 'borda, na C.6.8.3',
            functions: ['tv30_session_service'],
            holds: 'Os cinco campos do serviço corrente (Tabela C.8), regravados a cada troca de '
                + 'serviço.',
        }),
        family({
            name: 'session:current-app',
            type: 'HASH',
            writer: '<code>aop-cc</code> (gerente de ciclo de vida)',
            reader: '<code>tv3ws</code>, na identidade do cliente local associado',
            functions: ['tv30_current_app'],
            holds: 'A aplicação de emissora em execução na camada de gráficos: '
                + '<code>serviceContextId</code>, <code>appId</code> e <code>origin</code>. Regravada a '
                + 'cada lançamento e apagada no fim; ausente, a Bootstrap Application ou nenhum serviço.',
        }),
        family({
            name: 'app:doc-nodes:{serviceContextId}',
            type: 'HASH',
            writer: 'o formatador Ginga-NCL, que não existe no testbed',
            reader: '<code>tv3ws</code>, quando a aplicação entra',
            functions: [],
            declaredOnly: true,
            holds: 'Os nós do documento de cada aplicação do contexto, por <code>appId</code>: uma '
                + 'lista JSON de <code>{id, type, mimeType, device}</code>. O <code>tv3ws</code> associa '
                + 'cada nó ao dispositivo remoto que o apresenta.',
        }),
        family({
            name: 'users:index',
            type: 'SET',
            writer: 'casca',
            reader: 'casca, <code>tv3ws</code>',
            functions: ['tv30_profile_write', 'tv30_profile_remove'],
            holds: 'Os ids dos perfis, em UUID, no máximo cinco (10.3.3): o sexto é recusado, sem '
                + 'despejar nenhum.',
        }),
        family({
            name: 'user:{id}',
            type: 'HASH',
            writer: 'casca',
            reader: 'casca, <code>tv3ws</code>',
            functions: ['tv30_profile_write', 'tv30_profile_last_access', 'tv30_profile_remove'],
            holds: 'Os atributos básicos do perfil (Tabela 7) e o <code>lastAccess</code>, em ms. O '
                + '<code>avatar</code> é o nome de um arquivo de miniatura, e não o desenho.',
        }),
        family({
            name: 'user:{id}:consent',
            type: 'SET',
            writer: 'casca',
            reader: '<code>tv3ws</code>',
            functions: ['tv30_profile_write', 'tv30_profile_remove'],
            holds: 'Os serviços para os quais o perfil é visível. É a visibilidade do perfil por '
                + 'serviço, e não o consentimento do Privacy Manager (8.8), que o testbed não '
                + 'implementa.',
        }),
        family({
            name: 'user:{id}:broadcaster-attrs:{scid}',
            type: 'HASH',
            writer: '<code>tv3ws</code> grava, na C.6.14.5; a casca remove, junto com o perfil',
            reader: '<code>tv3ws</code>',
            functions: ['tv30_broadcaster_attributes', 'tv30_profile_remove'],
            holds: 'Os atributos de emissora do perfil no serviço <code>{scid}</code>, até 20 MB, sem '
                + 'os básicos que a C.6.14.5 não deixa redefinir.',
        }),
        family({
            name: 'client:{id}',
            type: 'HASH',
            writer: '<code>tv3ws</code>',
            reader: '<code>tv3ws</code>',
            functions: ['tv30_client_write', 'tv30_client_authorize'],
            holds: 'A classe do cliente (<code>associated</code>, <code>standAlone</code> ou '
                + '<code>nonLocal</code>) e os tokens dele. Fica depois de um bloqueio.',
        }),
        family({
            name: 'clients:authorized',
            type: 'SET',
            writer: '<code>tv3ws</code>',
            reader: '<code>tv3ws</code>, borda',
            functions: ['tv30_client_authorize', 'tv30_client_block', 'tv30_client_add_authorized'],
            holds: 'Os clientes autorizados pelo espectador. A borda responde 107 ao access token de '
                + 'quem não está aqui.',
        }),
        family({
            name: 'clients:blocked',
            type: 'SET',
            writer: '<code>tv3ws</code>',
            reader: '<code>tv3ws</code>, borda',
            functions: ['tv30_client_block', 'tv30_client_authorize'],
            holds: 'Os clientes bloqueados pelo espectador (C.4.2.2). Nenhum id fica nos dois '
                + 'conjuntos.',
        }),
        family({
            name: 'origins:associated',
            type: 'HASH',
            writer: 'casca',
            reader: 'borda, <code>tv3ws</code>',
            functions: ['tv30_origin_register', 'tv30_origin_remove', 'tv30_origins_clear'],
            holds: 'A origem de cada aplicação de emissora em execução → o serviço que a lançou. É '
                + 'por ela que a borda reconhece o cliente local associado. A casca a limpa na partida.',
        }),
        family({
            name: 'services:announced',
            type: 'SET',
            writer: 'casca',
            reader: 'casca, borda',
            functions: ['tv30_announced_services'],
            holds: 'Os serviços anunciados na LLS, o mesmo conteúdo do tópico <code>aop/services</code>. '
                + 'A borda responde 304 ao serviço que não está aqui.',
        }),
        family({
            name: 'bind-context:{serviceId}',
            type: 'LIST',
            writer: 'borda, na C.6.8.2 e na C.6.8.4',
            reader: 'borda',
            functions: ['tv30_bind_register', 'tv30_bind_remove'],
            holds: 'As chaves de bind-token registradas pela emissora, cada uma '
                + '<code>{alg, key, registeredAt}</code>. Qualquer uma valida o bind-token do serviço.',
        }),
        family({
            name: 'v100.0:remote-device:{handle}',
            type: 'HASH',
            writer: '<code>tv3ws</code>',
            reader: NONE,
            functions: [
                'tv30_v100_remote_device_write',
                'tv30_v100_remote_device_remove',
                'tv30_v100_remote_devices_clear',
            ],
            holds: 'Os registros de dispositivo remoto da versão 100.0, regravados a cada mudança e '
                + 'limpos na partida do <code>tv3ws</code>.',
        }),
        family({
            name: 'remote-devices:index',
            type: 'SET',
            writer: '<code>tv3ws</code>',
            reader: '<code>tv3ws</code>, na limpeza da partida',
            functions: [],
            holds: 'Os <em>handles</em> dos dispositivos remotos da versão 2.0, espelho do que o '
                + '<code>tv3ws</code> guarda em memória.',
        }),
        family({
            name: 'remote-devices:class:{classe}',
            type: 'SET',
            writer: '<code>tv3ws</code>',
            reader: '<code>tv3ws</code>, na limpeza da partida',
            functions: [],
            holds: 'Os <em>handles</em> dos dispositivos remotos da versão 2.0 numa classe.',
        }),
        family({
            name: 'remote-device:{handle}',
            type: 'HASH',
            writer: '<code>tv3ws</code>',
            reader: '<code>tv3ws</code>, na limpeza da partida',
            functions: [],
            holds: 'A classe, os tipos, a <code>url</code> e quem registrou um dispositivo remoto da '
                + 'versão 2.0.',
        }),
        family({
            name: 'seed:done',
            type: 'STRING',
            writer: 'a partida do container <code>redis</code>',
            reader: 'a partida e o healthcheck do container',
            functions: [],
            holds: 'A marca de que a carga inicial já foi aplicada. Sem ela, a próxima partida aplica '
                + 'a carga.',
        }),
        family({
            name: 'tv30:<nome>:exemplo',
            type: 'STRING',
            writer: 'os testes do modelo de componente',
            reader: 'o exemplo do modelo de componente',
            functions: [],
            holds: 'O valor que o exemplo do '
                + '<a href="../estender-com-componente/">modelo de componente</a> devolve no '
                + '<code>pong</code>.',
        }),
    ],
};
