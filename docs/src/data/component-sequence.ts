// Actors and messages of the sequence diagram of the guide "Estender o
// testbed com um componente" (components/sequence-diagram.astro): the
// ping of the example of templates/componente.

export const examplePing = {
    actors: [
        { id: 'you', label: 'Você' },
        { id: 'broker', label: 'Broker' },
        { id: 'component', label: 'Seu componente' },
        { id: 'redis', label: 'Redis' },
    ],
    messages: [
        {
            id: 'subscribe',
            from: 'component',
            to: 'broker',
            label: 'assina …/exemplo/ping',
            title: 'O componente assina o tópico',
            detail: 'Ao subir, o componente se conecta ao broker pelo nome do serviço '
                + '(<code>mosquitto</code>) e assina só o tópico que lhe interessa: '
                + '<code>tv30/&lt;nome&gt;/exemplo/ping</code>.',
            channel: 'mqtt',
        },
        {
            id: 'ping',
            from: 'you',
            to: 'broker',
            label: 'publica ping',
            title: 'Alguém publica no tópico',
            detail: 'Aqui é você, com <code>mosquitto_pub</code>. Na plataforma, é outro componente '
                + 'avisando que algo aconteceu.',
            channel: 'mqtt',
        },
        {
            id: 'deliver',
            from: 'broker',
            to: 'component',
            label: 'entrega ping',
            title: 'O broker entrega a quem assinou',
            detail: 'Quem publica não sabe quem vai receber: é o que deixa cada componente '
                + 'independente dos outros.',
            channel: 'mqtt',
        },
        {
            id: 'get',
            from: 'component',
            to: 'redis',
            label: 'GET tv30:<nome>:exemplo',
            title: 'O componente consulta o estado',
            detail: 'O dado que alguém precisa consultar fica no Redis, e não na mensagem. O '
                + 'componente o lê na hora em que precisa.',
            channel: 'state',
        },
        {
            id: 'value',
            from: 'redis',
            to: 'component',
            label: 'valor',
            title: 'O Redis responde',
            detail: 'Sem a chave, o valor vem vazio (<code>null</code> no pong).',
            channel: 'state',
        },
        {
            id: 'pong',
            from: 'component',
            to: 'broker',
            label: 'publica pong',
            title: 'O componente responde',
            detail: 'Publica em <code>tv30/&lt;nome&gt;/exemplo/pong</code> um JSON com o ping '
                + 'recebido, a chave e o valor lido.',
            channel: 'mqtt',
        },
        {
            id: 'receive',
            from: 'broker',
            to: 'you',
            label: 'entrega pong',
            title: 'Quem assinou o pong recebe',
            detail: 'Aqui, o seu <code>mosquitto_sub</code>.',
            channel: 'mqtt',
        },
    ],
};
