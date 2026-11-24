#!/usr/bin/env bash
# Static checks, the same locally and in CI. Usage: validate.sh yaml|chart|manifests|all
# Needs yamllint, helm and kubeconform. SCHEMAS replaces the kubeconform schema locations (offline runs).
set -euo pipefail
cd "$(dirname "$0")/../.."

K8S_VERSION="${K8S_VERSION:-1.36.0}"
CRD_CATALOG='https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
read -r -a schemas <<< "${SCHEMAS:--schema-location default -schema-location $CRD_CATALOG}"

kubeconform() {
  command kubeconform -strict -summary -kubernetes-version "$K8S_VERSION" "${schemas[@]}" "$@"
}

check_yaml() {
  echo "::group::yamllint"
  yamllint -c .yamllint.yaml apps bootstrap argocd platform .github \
    charts/growpath/Chart.yaml charts/growpath/values.yaml charts/growpath/ci
  echo "::endgroup::"
}

check_chart() {
  local file env base service
  echo "::group::helm lint"
  for file in charts/growpath/ci/*.yaml; do
    helm lint --strict charts/growpath -f "$file"
  done
  echo "::endgroup::"

  echo "::group::render and validate the chart test values"
  for file in charts/growpath/ci/*.yaml; do
    echo "$file"
    helm template ci charts/growpath -f "$file" | kubeconform
  done
  echo "::endgroup::"

  echo "::group::render and validate every service in every environment"
  for env in apps/*/; do
    env="$(basename "$env")"
    [ "$env" = base ] && continue
    for base in apps/base/*.yaml; do
      service="$(basename "$base" .yaml)"
      echo "$env/$service"
      helm template "$service" charts/growpath \
        -f "$base" -f "apps/$env/common.yaml" -f "apps/$env/$service.yaml" | kubeconform
    done
  done
  echo "::endgroup::"
}

check_manifests() {
  echo "::group::Argo CD and platform manifests"
  kubeconform bootstrap/root-app.yaml argocd platform/apps platform/karpenter platform/external-secrets
  echo "::endgroup::"
}

case "${1:-all}" in
  yaml) check_yaml ;;
  chart) check_chart ;;
  manifests) check_manifests ;;
  all) check_yaml; check_chart; check_manifests ;;
  *) echo "usage: $0 yaml|chart|manifests|all" >&2; exit 2 ;;
esac
