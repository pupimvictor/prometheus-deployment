#!/usr/bin/env bash

function helm_test() {
  local cluster="${1}"
  local namespace="${2}"
  local release="${3}"

  pks get-credentials "${cluster}"

  switch_namespace "${cluster}" "${namespace}"

  printf "Testing %s on %s\n" "${release}" "${cluster}"
  exit_code=0
  helm test "${release}" 2>/dev/null || exit_code=1
  kubectl logs "${release}-smoke-tests"

  printf "\nFinished testing %s on %s\n" "${release}" "${cluster}"
  printf "============================================================\n"
  return $exit_code
}

function main() {
  local canary="${1}"
  local foundation="${2}"
  local cluster="${3}"
  local namespace="${4}"
  local release="${5}"

  export VARS_cluster_name="${cluster}"

  clusters_in_order_of_upgrade=$(om interpolate -s --config "environments/${foundation}/config/config.yml" \
      --vars-file "environments/${foundation}/vars/vars.yml" \
      --vars-env VARS \
      --path "/clusters" | \
      grep cluster_name | awk '{print $NF}')

  for cluster in ${clusters_in_order_of_upgrade}; do
    is_cluster_canary=$(om interpolate -s \
          --config "environments/${foundation}/config/config.yml" \
          --vars-file "environments/${foundation}/vars/vars.yml" \
          --vars-env VARS \
          --path "/clusters/cluster_name=${cluster}/is_canary")

    if [[ "${is_cluster_canary}" == "${canary}" ]]; then
        exit_code=0
        helm_test "${cluster}" "${namespace}" "${release}" 2>/dev/null || exit_code=1
        if [[ $exit_code -ne 0 ]]; then
           echo ""
           echo "Smoke tests failed" && exit $exit_code
        fi
    fi
  done
}

set -e
# only exit with zero if all commands of the pipeline exit successfully
set -o pipefail

__DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1090
source "${__DIR}/../../../scripts/helpers.sh"

canary="${1:-$CANARY}"
foundation="${2:-$FOUNDATION}"
cluster="${3:-$CLUSTER_NAME}"
namespace="${4:-$NAMESPACE}"
release="${5:-$RELEASE}"

if [[ -z "${canary}" ]]; then
  canary="false"
fi

if [[ -z "${foundation}" ]]; then
  echo "Foundation name is required"
  exit 1
fi

if [[ -z "${cluster}" ]]; then
  echo "Cluster name is required"
  exit 1
fi

if [[ -z "${namespace}" ]]; then
  echo "Namespace name is required"
  exit 1
fi

if [[ -z "${release}" ]]; then
  echo "Release is required"
  exit 1
fi

mkdir -p ~/.pks
cp pks-config/creds.yml ~/.pks/creds.yml

mkdir -p ~/.kube
cp kube-config/config ~/.kube/config

cd repo

main "${canary}" "${foundation}" "${cluster}" "${namespace}" "${release}"
