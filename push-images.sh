#!/usr/bin/env bash
# push-images.sh — Builda, tageia e publica todas as imagens TV30 no Docker Hub.
#
# Pre-requisitos:
#   docker login (ou docker login -u <namespace>)
#
# Uso:
#   ./push-images.sh <DOCKERHUB_NS> [TAG]
#   ./push-images.sh multisens                  # tag default: latest
#   ./push-images.sh multisens 1.0.0
#   ./push-images.sh multisens 1.0.0 --no-build # so retag+push (assume imagens ja buildadas)

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

# (apps tv30) name: ctx-dir, dockerfile-relative-to-ROOT
declare -a APPS=(
    "tv30-ccws|ccws|infra/dockerfiles/ccws.Dockerfile"
    "tv30-aop|aop|infra/dockerfiles/aop.Dockerfile"
    "tv30-bcast|bcast|infra/dockerfiles/bcast.Dockerfile"
)

# (infra customs) name: context (relative-to-ROOT) | dockerfile (relative-to-ROOT)
declare -a INFRA=(
    "tv30-mosquitto|infra/mosquitto_plugin|infra/mosquitto_plugin/infra/Dockerfile"
    "tv30-validation-middleware|infra/middleware|infra/middleware/Dockerfile"
    "tv30-middleware-internal|infra/middleware_internal|infra/middleware_internal/Dockerfile"
    "tv30-swagger|infra/swagger|infra/swagger/Dockerfile"
)

# --- 1. Build (skipavel) ---
# tv30-aop e tv30-ccws usam contextos adicionais (template de user-files +
# entrypoint compartilhado). Demais apps usam build simples.
if [ "$NO_BUILD" != "--no-build" ]; then
    step "Buildando ${#APPS[@]} apps + ${#INFRA[@]} infra customs..."
    for entry in "${APPS[@]}" "${INFRA[@]}"; do
        IFS='|' read -r name ctx df <<< "$entry"
        echo
        echo "  -> ${NS}/${name}:${TAG}"
        if [ "$name" = "tv30-aop" ] || [ "$name" = "tv30-ccws" ]; then
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

# --- 2. Verifica login ---
step "Verificando autenticacao no Docker Hub..."
if ! docker info 2>/dev/null | grep -qi "username"; then
    err "Voce nao esta autenticado. Rode: docker login"
    exit 1
fi
ok "Autenticado"

# --- 3. Push ---
step "Pushing imagens para docker.io/${NS}/..."
for entry in "${APPS[@]}" "${INFRA[@]}"; do
    IFS='|' read -r name _ _ <<< "$entry"
    echo
    echo "  -> ${NS}/${name}:${TAG}"
    docker push "${NS}/${name}:${TAG}"
done

# Tambem tag :latest se TAG != latest
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
