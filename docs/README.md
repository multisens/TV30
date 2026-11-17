# Documentação do TV30

Site de documentação do testbed, em Astro Starlight. As páginas ficam em `src/content/docs/`, uma por
arquivo Markdown, e o menu lateral em `astro.config.mjs`.

| Comando (nesta pasta) | Efeito |
|---|---|
| `npm ci` | Instala as dependências fixadas em `package-lock.json` |
| `npm run dev` | Servidor local com recarga, em `http://localhost:4321/TV30/` |
| `npm run build` | Gera o site em `dist/` |
| `npm run preview` | Serve o `dist/` gerado |

O workflow `.github/workflows/docs.yml` gera e publica o site no GitHub Pages a cada push em `main` que toque
`docs/`. Em *Settings → Pages*, a fonte do repositório tem de ser *GitHub Actions*.

O mapa de unidades (`src/content/docs/mapa-unidades.mdx`) lê `src/data/aop-units.yml` e
`src/data/aop-groups.yml`; a página explica os campos.
