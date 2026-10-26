#!/usr/bin/env bash
# push-images.sh: builds, tags and publishes every TV30 image on Docker Hub.
#
# Prerequisite:
#   docker login (or docker login -u <namespace>)
#
# Usage:
#   ./push-images.sh <DOCKERHUB_NS> [TAG]
#   ./push-images.sh multisens                  (default tag: latest)
#   ./push-images.sh multisens 1.0.0
#   ./push-images.sh multisens 1.0.0 --no-build (only retag and push, with
#                                                the images already built)

set -euo pipefail

NS="${1:-}"
TAG="${2:-latest}"
NO_BUILD="${3:-}"

if [ -z "$NS" ]; then
    echo "Uso: $0 <DOCKERHUB_NS> [TAG] [--no-build]"
    echo "  ex.: $0 multisens 1.0.0"
    exit 1
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

c_cyan='\033[1;36m'; c_green='\033[1;32m'; c_red='\033[1;31m'; c_off='\033[0m'
step()   { echo -e "\n${c_cyan}==> $*${c_off}"; }
ok()     { echo -e "    ${c_green}[OK]${c_off} $*"; }
err()    { echo -e "    ${c_red}[ERRO]${c_off} $*"; }

# (TV30 applications) name|context dir|dockerfile relative to ROOT
declare -a APPS=(
    "tv30-tv3ws|tv3ws|infra/dockerfiles/tv3ws.Dockerfile"
    "tv30-aop|aop|infra/dockerfiles/aop.Dockerfile"
    "tv30-bcast|bcast|infra/dockerfiles/bcast.Dockerfile"
)

# (infrastructure) name|context relative to ROOT|dockerfile relative to ROOT
declare -a INFRA=(
    "tv30-mosquitto|infra/mqtt-broker|infra/mqtt-broker/infra/Dockerfile"
    "tv30-edgegateway|infra/edgegateway|infra/edgegateway/Dockerfile"
    "tv30-redis|infra|infra/redis/Dockerfile"
)

# tv30-aop and tv30-tv3ws use additional contexts (user-files template and
# shared entrypoint). The other applications use a plain build.
if [ "$NO_BUILD" != "--no-build" ]; then
    step "Buildando ${#APPS[@]} apps + ${#INFRA[@]} infra customs..."
    for entry in "${APPS[@]}" "${INFRA[@]}"; do
        IFS='|' read -r name ctx df <<< "$entry"
        echo
        echo "  -> ${NS}/${name}:${TAG}"
        if [ "$name" = "tv30-aop" ] || [ "$name" = "tv30-tv3ws" ]; then
            docker build -t "${NS}/${name}:${TAG}" \
                -f "${ROOT}/${df}" \
                --build-context tv30-data="${ROOT}/infra/user-files-template" \
                --build-context tv30-scripts="${ROOT}/infra/dockerfiles" \
                "${ROOT}/${ctx}"
        else
            docker build -t "${NS}/${name}:${TAG}" -f "${ROOT}/${df}" "${ROOT}/${ctx}"
        fi
    done
    ok "Build concluido"
fi

step "Verificando autenticacao no Docker Hub..."
if ! docker info 2>/dev/null | grep -qi "username"; then
    err "Voce nao esta autenticado. Rode: docker login"
    exit 1
fi
ok "Autenticado"

step "Pushing imagens para docker.io/${NS}/..."
for entry in "${APPS[@]}" "${INFRA[@]}"; do
    IFS='|' read -r name _ _ <<< "$entry"
    echo
    echo "  -> ${NS}/${name}:${TAG}"
    docker push "${NS}/${name}:${TAG}"
done

if [ "$TAG" != "latest" ]; then
    step "Tageando tambem como :latest"
    for entry in "${APPS[@]}" "${INFRA[@]}"; do
        IFS='|' read -r name _ _ <<< "$entry"
        docker tag "${NS}/${name}:${TAG}" "${NS}/${name}:latest"
        docker push "${NS}/${name}:latest"
    done
fi

echo
ok "Push completo. Imagens publicadas em https://hub.docker.com/u/${NS}"
echo
echo "Pra subir em outra maquina Linux:"
echo "  git clone <repo>/TV30 && cd TV30"
echo "  export DOCKERHUB_NS=${NS}"
echo "  export IMAGE_TAG=${TAG}"
echo "  docker compose --profile mqtt --profile linux pull"
echo "  docker compose --profile mqtt --profile linux up -d"
