# Imagem do componente de EXEMPLO do template (ver README.md). Mesma base
# dos Dockerfiles de infra/dockerfiles/. O exemplo nao tem dependencias npm;
# um componente real copia package*.json e roda `npm ci --omit=dev` aqui,
# antes de copiar o codigo.
ARG NODE_IMAGE=node:23-alpine
FROM ${NODE_IMAGE}
WORKDIR /app
COPY package.json index.js ./
USER node
EXPOSE 8090
CMD ["node", "index.js"]
