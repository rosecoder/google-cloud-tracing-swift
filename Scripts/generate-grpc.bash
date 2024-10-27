SOURCES_ROOT="$(pwd)/Sources"

rm -rf ${SOURCES_ROOT}/*/gRPC_generated/*

cd googleapis/

protoc google/devtools/cloudtrace/v2/*.proto google/rpc/status.proto \
  --swift_out=${SOURCES_ROOT}/GoogleCloudTracing/gRPC_generated/ \
  --grpc-swift_opt=Client=true,Server=false \
  --grpc-swift_out=${SOURCES_ROOT}/GoogleCloudTracing/gRPC_generated/
