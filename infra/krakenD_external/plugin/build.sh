#!/usr/bin/env bash
set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_DIR="$(cd "${PLUGIN_DIR}/.." && pwd)/plugins"

mkdir -p "$OUTPUT_DIR"

echo "Building consent-validator plugin..."

docker run --rm \
  -v "${PLUGIN_DIR}:/go/src/consent-validator" \
  -v "${OUTPUT_DIR}:/go/output" \
  -w /go/src/consent-validator \
  devopsfaith/krakend-plugin-builder:2.7 \
  go build -buildmode=plugin -o /go/output/consent-validator.so .

echo "Plugin compilado em: ${OUTPUT_DIR}/consent-validator.so"
