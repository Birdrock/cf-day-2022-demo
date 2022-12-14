#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../korifi" && pwd)"
SCRIPT_DIR="${ROOT_DIR}/scripts"

function usage_text() {
  cat <<EOF
Usage:
  $(basename "$0") <kind cluster name>

flags:
  -r, --use-custom-registry
      Instead of using the default local registry, use the registry
      described by the follow set of env vars:
      - DOCKER_SERVER
      - DOCKER_USERNAME
      - DOCKER_PASSWORD
      - PACKAGE_REPOSITORY_PREFIX
      - DROPLET_REPOSITORY_PREFIX
      - KPACK_BUILDER_REPOSITORY

  -v, --verbose
      Verbose output (bash -x).

  -D, --debug
      Builds controller and api images with debugging hooks and
      wires up ports for remote debugging:
        localhost:30051 (controllers)
        localhost:30052 (api)
        localhost:30053 (kpack-image-builder)
        localhost:30054 (statefulset-runner)
        localhost:30055 (job-task-runner)

EOF
  exit 1
}

cluster=""
use_custom_registry=""
debug=""

while [[ $# -gt 0 ]]; do
  i=$1
  case $i in
    -r | --use-custom-registry)
      use_custom_registry="true"
      # blow up if required vars not set
      echo "$DOCKER_SERVER $DOCKER_USERNAME $DOCKER_PASSWORD $PACKAGE_REPOSITORY_PREFIX $DROPLET_REPOSITORY_PREFIX $KPACK_BUILDER_REPOSITORY" >/dev/null
      shift
      ;;
    -D | --debug)
      debug="true"
      shift
      ;;
    -v | --verbose)
      set -x
      shift
      ;;
    -h | --help | help)
      usage_text >&2
      exit 0
      ;;
    *)
      if [[ -n "${cluster}" ]]; then
        echo -e "Error: Unexpected argument: ${i/=*/}\n" >&2
        usage_text >&2
        exit 1
      fi
      cluster=$1
      shift
      ;;
  esac
done

if [[ -z "${cluster}" ]]; then
  echo -e "Error: missing argument <kind cluster name>" >&2
  usage_text >&2
  exit 1
fi

function deploy_korifi() {
  pushd "${ROOT_DIR}" >/dev/null
  {

    if [[ -z "${SKIP_DOCKER_BUILD:-}" ]]; then
      echo "Building korifi values file..."

      make generate manifests

      kbld_file="scripts/assets/korifi-kbld.yml"
      if [[ -n "$debug" ]]; then
        kbld_file="scripts/assets/korifi-debug-kbld.yml"
      fi

      kbld \
        -f "$kbld_file" \
        -f "scripts/assets/values-template.yaml" \
        --images-annotation=false >"scripts/assets/values.yaml"

      awk '/image:/ {print $2}' scripts/assets/values.yaml | while read -r img; do
        kind load docker-image --name "$cluster" "$img"
      done
    fi

    echo "Deploying korifi..."
    helm dependency update helm/korifi

    doDebug="false"
    secLevel="restricted"
    if [[ -n "${debug}" ]]; then
      doDebug="true"
      secLevel="privileged"
    fi

    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  labels:
    pod-security.kubernetes.io/enforce: $secLevel
  name: korifi
EOF

    if [[ -n "$use_custom_registry" ]]; then
      helm upgrade --install korifi helm/korifi \
        --namespace korifi \
        --values=scripts/assets/values.yaml \
        --set=global.debug="$doDebug" \
        --set=api.packageRepositoryPrefix="$PACKAGE_REPOSITORY_PREFIX" \
        --set=kpack-image-builder.dropletRepositoryPrefix="$DROPLET_REPOSITORY_PREFIX" \
        --set=kpack-image-builder.builderRepository="$KPACK_BUILDER_REPOSITORY" \
        --wait
    else
      helm upgrade --install korifi helm/korifi \
        --namespace korifi \
        --values=scripts/assets/values.yaml \
        --set=global.debug="$doDebug" \
        --wait
    fi
  }
  popd >/dev/null
}

function create_registry_secret() {
  if [[ -z "${use_custom_registry}" ]]; then
    DOCKER_SERVER="localregistry-docker-registry.default.svc.cluster.local:30050"
    DOCKER_USERNAME="user"
    DOCKER_PASSWORD="password"
  fi

  if [[ -n "${DOCKER_SERVER:=}" && -n "${DOCKER_USERNAME:=}" && -n "${DOCKER_PASSWORD:=}" ]]; then
    if kubectl get -n cf secret image-registry-credentials >/dev/null 2>&1; then
      kubectl delete -n cf secret image-registry-credentials
    fi

    kubectl create secret -n cf docker-registry image-registry-credentials \
      --docker-server=${DOCKER_SERVER} \
      --docker-username=${DOCKER_USERNAME} \
      --docker-password="${DOCKER_PASSWORD}"
  fi
}

deploy_korifi
create_registry_secret
