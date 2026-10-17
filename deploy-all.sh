#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="expresso-shop"
ACTION="${1:-deploy}"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Required command not found: $1" >&2
    exit 1
  fi
}

require_command kubectl

usage() {
  echo "Usage: $0 [deploy|delete]" >&2
}

if (( $# > 1 )); then
  usage
  exit 2
fi

deploy() {
  echo "Deploying Espresso Shop to context: $(kubectl config current-context)"
  kubectl cluster-info >/dev/null

  echo "Applying application resources..."
  kubectl apply -f "${SCRIPT_DIR}/kubernetes/espresso-shop.yaml"

  echo "Waiting for persistent storage..."
  kubectl wait \
    --namespace "${NAMESPACE}" \
    --for=jsonpath='{.status.phase}'=Bound \
    persistentvolumeclaim/espresso-shop-data \
    --timeout=180s

  echo "Applying network policies..."
  kubectl apply -f "${SCRIPT_DIR}/kubernetes/network-policy.yaml"

  echo "Applying TLS certificate and Traefik route..."
  kubectl apply -f "${SCRIPT_DIR}/kubernetes/ingress-route.yaml"

  echo "Waiting for deployments..."
  for deployment in \
    espresso-shop-product-catalog \
    espresso-shop-reviews-v1 \
    espresso-shop-reviews-v2 \
    espresso-shop-web
  do
    kubectl rollout status \
      --namespace "${NAMESPACE}" \
      "deployment/${deployment}" \
      --timeout=180s
  done

  echo "Waiting for TLS certificate..."
  kubectl wait \
    --namespace "${NAMESPACE}" \
    --for=condition=Ready \
    certificate/espresso-shop-tls \
    --timeout=180s

  echo "Deployment status:"
  kubectl get pods,services,hpa,persistentvolumeclaim,networkpolicy \
    --namespace "${NAMESPACE}"
  kubectl get ingressroute.traefik.io,certificate \
    --namespace "${NAMESPACE}"

  echo "Espresso Shop is available at:"
  echo "https://espresso-shop.dev.webforxtech.com"
}

delete() {
  echo "Deleting Espresso Shop from context: $(kubectl config current-context)"
  echo "WARNING: This deletes the PVC and its dynamically provisioned Azure File data."
  kubectl cluster-info >/dev/null

  kubectl delete \
    --ignore-not-found=true \
    -f "${SCRIPT_DIR}/kubernetes/ingress-route.yaml"
  kubectl delete \
    --ignore-not-found=true \
    -f "${SCRIPT_DIR}/kubernetes/network-policy.yaml"
  kubectl delete \
    --ignore-not-found=true \
    --wait=true \
    -f "${SCRIPT_DIR}/kubernetes/espresso-shop.yaml"

  echo "Espresso Shop resources deleted."
}

case "${ACTION}" in
  deploy)
    deploy
    ;;
  delete)
    delete
    ;;
  *)
    usage
    exit 2
    ;;
esac
