import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

const REPOSITORY_URL = 'https://github.com/multisens/TV30';

export default defineConfig({
    site: 'https://multisens.github.io',
    base: '/TV30',
    integrations: [
        starlight({
            title: 'TV30',
            description: 'Documentação técnica do testbed aberto da camada de '
                + 'Codificação de Aplicações da TV 3.0',
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
                    label: 'Primeiros passos',
                    items: [
                        { label: 'Visão geral', slug: 'primeiros-passos' },
                        'instalacao',
                        'dev-local',
                        'como-testar',
                        'glossario',
                    ],
                },
                {
                    label: 'Como funciona',
                    items: [
                        { label: 'Visão geral', slug: 'como-funciona' },
                        'arquitetura',
                        'apis-tv3ws',
                        'modelo-redis',
                        'mqtt-topicos',
                        'broker-mqtt',
                        'borda-credenciais',
                        'ssdp',
                        'decisoes',
                        'nao-implementado',
                        'mapa-unidades',
                    ],
                },
                'troubleshooting',
            ],
        }),
    ],
});
