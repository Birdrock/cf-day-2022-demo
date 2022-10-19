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

function ensure_kind_cluster() {
  if ! kind get clusters | grep -q "${cluster}"; then
    kind create cluster --name "${cluster}" --wait 5m --config="$SCRIPT_DIR/assets/kind-config.yaml"
  fi

  kind export kubeconfig --name "${cluster}"
}

function ensure_local_registry() {
  if [[ -n "${use_custom_registry}" ]]; then return 0; fi

  helm repo add twuni https://helm.twun.io
  # the htpasswd value below is username: user, password: password encoded using `htpasswd` binary
  # e.g. `docker run --entrypoint htpasswd httpd:2 -Bbn user password`
  helm upgrade --install localregistry twuni/docker-registry \
    --set service.type=NodePort,service.nodePort=30050,service.port=30050 \
    --set persistence.enabled=true \
    --set secrets.htpasswd='user:$2y$05$Ue5dboOfmqk6Say31Sin9uVbHWTl8J1Sgq9QyAEmFQRnq1TPfP1n2'
}

function install_dependencies() {
  pushd "${ROOT_DIR}" >/dev/null
  {
    export INSECURE_TLS_METRICS_SERVER=true

    "${SCRIPT_DIR}/install-dependencies.sh"
  }
  popd >/dev/null
}

ensure_kind_cluster "${cluster}"
ensure_local_registry
install_dependencies
