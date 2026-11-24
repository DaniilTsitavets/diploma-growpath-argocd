#!/usr/bin/env bash
# One-shot Argo CD bootstrap for a freshly created cluster (needs Tailscale and AWS SSO login).
# Safe to re-run: the Helm install is skipped when the release already exists.
#
#   AWS_PROFILE=growpath-prod scripts/bootstrap.sh
#
# Env: CLUSTER_NAME (growpath), AWS_REGION (eu-north-1), UPDATE_KUBECONFIG (1; 0 keeps your context),
#      WAIT_SECONDS (900).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLUSTER_NAME="${CLUSTER_NAME:-growpath}"
AWS_REGION="${AWS_REGION:-eu-north-1}"
UPDATE_KUBECONFIG="${UPDATE_KUBECONFIG:-1}"
WAIT_SECONDS="${WAIT_SECONDS:-900}"

for cmd in kubectl helm; do
  command -v "$cmd" >/dev/null || { echo "missing: $cmd" >&2; exit 1; }
done

if [ "$UPDATE_KUBECONFIG" = "1" ]; then
  command -v aws >/dev/null || { echo "missing: aws" >&2; exit 1; }
  aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$AWS_REGION" >/dev/null
fi

# The chart version lives in Git so the manual install and the self-managed Application match.
VERSION="$(awk '/chart: argo-cd/{f=1} f && /targetRevision:/{print $2; exit}' "$ROOT/platform/apps/argocd.yaml")"
[ -n "$VERSION" ] || { echo "cannot read argo-cd version from platform/apps/argocd.yaml" >&2; exit 1; }

echo "==> waiting for nodes"
kubectl wait --for=condition=Ready nodes --all --timeout=10m

echo "==> argo-cd chart $VERSION"
helm repo add argo https://argoproj.github.io/argo-helm --force-update >/dev/null
helm repo update argo >/dev/null
if helm status argocd -n argocd >/dev/null 2>&1; then
  echo "release argocd already installed, skipping"
else
  helm install argocd argo/argo-cd --version "$VERSION" -n argocd --create-namespace \
    -f "$ROOT/bootstrap/argocd-values.yaml" --wait --timeout 10m
fi

echo "==> applying root Application"
kubectl apply -f "$ROOT/bootstrap/root-app.yaml"

echo "==> waiting for all Applications to be Synced and Healthy (up to ${WAIT_SECONDS}s)"
deadline=$((SECONDS + WAIT_SECONDS))
stable=0
while [ "$SECONDS" -lt "$deadline" ]; do
  status="$(kubectl -n argocd get applications \
    -o jsonpath='{range .items[*]}{.metadata.name} {.status.sync.status} {.status.health.status}{"\n"}{end}' 2>/dev/null || true)"
  total="$(printf '%s\n' "$status" | grep -c . || true)"
  bad="$(printf '%s\n' "$status" | grep -vc 'Synced Healthy' || true)"
  # Applications are created wave by wave, so require two clean polls in a row.
  if [ "$total" -ge 2 ] && [ "$bad" -eq 0 ]; then
    stable=$((stable + 1))
    [ "$stable" -ge 2 ] && break
  else
    stable=0
  fi
  sleep 20
done

kubectl -n argocd get applications
if [ "$stable" -lt 2 ]; then
  echo "Applications are not all Synced/Healthy yet; check the table above" >&2
  exit 1
fi

echo
echo "Done. UI: kubectl -n argocd port-forward svc/argocd-server 8080:443  ->  https://localhost:8080"
echo "Admin password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
