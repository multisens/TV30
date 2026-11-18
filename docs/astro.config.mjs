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
        '/apis-tv3ws': '/TV30/tv3ws/',
        '/mqtt-topicos': '/TV30/mensageria/',
        '/broker-mqtt': '/TV30/mensageria/',
        '/ssdp': '/TV30/instalacao/#descoberta-na-rede',
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
                PageSidebar: './src/components/page-sidebar.astro',
                TwoColumnContent: './src/components/two-column-content.astro',
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
                        'apis-de-outro-aparelho',
                        'estender-com-componente',
                    ],
                },
                {
                    label: 'Referência',
                    items: [
                        {
                            label: 'Operar',
                            items: [
                                'instalacao',
                                'dev-local',
                                'como-testar',
                            ],
                        },
                        {
                            label: 'Por dentro',
                            items: [
                                'arquitetura',
                                'emissora-simulada',
                                'borda-credenciais',
                                'modelo-redis',
                                'mensageria',
                                'mapas-componentes',
                            ],
                        },
                        {
                            label: 'Componentes',
                            items: [
                                'tv3ws',
                                'aop',
                            ],
                        },
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
