#!/usr/bin/env bash
set -euo pipefail

SOURCES_ROOT="$(pwd)/Sources"

GOOGLEAPIS_COMMIT="${GOOGLEAPIS_COMMIT:-48d30c4966ef9ea31b897e13f75d8f94070cc8e9}"

if [ ! -d googleapis/.git ]; then
  git init -q googleapis
  git -C googleapis remote add origin https://github.com/googleapis/googleapis.git
fi
echo "Fetching googleapis@${GOOGLEAPIS_COMMIT}..."
git -C googleapis fetch -q --depth 1 origin "${GOOGLEAPIS_COMMIT}"
git -C googleapis checkout -q --force FETCH_HEAD

rm -rf ${SOURCES_ROOT}/*/gRPC_generated/*

cd googleapis/

protoc google/devtools/cloudtrace/v2/*.proto google/rpc/status.proto \
  --swift_out=${SOURCES_ROOT}/GoogleCloudTracing/gRPC_generated/ \
  --grpc-swift_opt=Client=true,Server=false \
  --grpc-swift_out=${SOURCES_ROOT}/GoogleCloudTracing/gRPC_generated/
