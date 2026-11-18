import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

const REPOSITORY_URL = 'https://github.com/multisens/TV30';

export default defineConfig({
    site: 'https://multisens.github.io',
    base: '/TV30',
    // Pages merged into others keep their published addresses.
    redirects: {
        '/decisoes': '/TV30/escopo/#decisões-do-projeto',
        '/nao-implementado': '/TV30/escopo/#fora-do-escopo',
        '/mapa-unidades': '/TV30/escopo/#o-escopo-no-mapa',
    },
    integrations: [
        starlight({
            title: 'Testbed TV 3.0',
            description: 'Testbed aberto da camada de Codificação de Aplicações '
                + 'da TV 3.0',
            defaultLocale: 'root',
            locales: {
                root: { label: 'Português', lang: 'pt-BR' },
            },
            social: [
                { icon: 'github', label: 'Repositório', href: REPOSITORY_URL },
            ],
            customCss: ['./src/styles/site.css'],
            components: {
                Footer: './src/components/footer.astro',
            },
            sidebar: [
                { label: 'Início', slug: 'index' },
                {
                    label: 'Entenda',
                    items: [
                        'aop-em-5-minutos',
                        'o-que-simula',
                        'escopo',
                    ],
                },
                {
                    label: 'Use',
                    items: [
                        'subir-e-passear',
                    ],
                },
                {
                    label: 'Referência',
                    items: [
                        'instalacao',
                        'arquitetura',
                        'apis-tv3ws',
                        'borda-credenciais',
                        'modelo-redis',
                        'mqtt-topicos',
                        'broker-mqtt',
                        'ssdp',
                        'dev-local',
                        'como-testar',
                    ],
                },
                {
                    label: 'Ajuda',
                    items: [
                        'troubleshooting',
                        'glossario',
                    ],
                },
            ],
        }),
    ],
});
