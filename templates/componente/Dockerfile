# Image of the EXAMPLE component of the template (see README.md). Same base
# as the Dockerfiles of infra/dockerfiles/. The example has no npm
# dependencies; a real component copies package*.json and runs
# `npm ci --omit=dev` here, before copying the code.
ARG NODE_IMAGE=node:23-alpine
FROM ${NODE_IMAGE}
WORKDIR /app
COPY package.json index.js ./
USER node
EXPOSE 8090
CMD ["node", "index.js"]
