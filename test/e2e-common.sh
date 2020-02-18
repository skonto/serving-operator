#!/usr/bin/env bash

# Copyright 2019 The Knative Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# This script provides helper methods to perform cluster actions.
source $(dirname $0)/../vendor/knative.dev/test-infra/scripts/e2e-tests.sh

# Latest serving release. This is intentionally hardcoded for now, but
# will need the ability to test against the latest successful serving
# CI runs in the future.
readonly LATEST_SERVING_RELEASE_VERSION=$(git describe --match "v[0-9]*" --abbrev=0)
# Istio version we test with
readonly ISTIO_VERSION="1.4.2"
# Test without Istio mesh enabled
readonly ISTIO_MESH=0
# Namespace used for tests
readonly TEST_NAMESPACE="operator-tests"

# Choose a correct istio-crds.yaml file.
# - $1 specifies Istio version.
function istio_crds_yaml() {
  local istio_version="$1"
  echo "third_party/istio-${istio_version}/istio-crds.yaml"
}

# Choose a correct istio.yaml file.
# - $1 specifies Istio version.
# - $2 specifies whether we should use mesh.
function istio_yaml() {
  local istio_version="$1"
  local istio_mesh=$2
  local suffix=""
  if [[ $istio_mesh -eq 0 ]]; then
    suffix="ci-no-mesh"
  else
    suffix="ci-mesh"
  fi
  echo "third_party/istio-${istio_version}/istio-${suffix}.yaml"
}

# Install Istio.
function install_istio() {
  local base_url="https://raw.githubusercontent.com/knative/serving/${LATEST_SERVING_RELEASE_VERSION}"
  INSTALL_ISTIO_CRD_YAML="${base_url}/$(istio_crds_yaml $ISTIO_VERSION)"
  INSTALL_ISTIO_YAML="${base_url}/$(istio_yaml $ISTIO_VERSION $ISTIO_MESH)"

  echo ">> Installing Istio"
  echo "Istio CRD YAML: ${INSTALL_ISTIO_CRD_YAML}"
  echo "Istio YAML: ${INSTALL_ISTIO_YAML}"
    
  echo ">> Bringing up Istio"
  echo ">> Running Istio CRD installer"
  kubectl apply -f "${INSTALL_ISTIO_CRD_YAML}" || return 1
  wait_until_batch_job_complete istio-system || return 1

  echo ">> Running Istio"
  kubectl apply -f "${INSTALL_ISTIO_YAML}" || return 1
}

function create_namespace() {
  echo ">> Creating test namespaces"
  # All the custom resources and Knative Serving resources are created under this TEST_NAMESPACE.
  kubectl create namespace $TEST_NAMESPACE
}

function install_serving_operator() {
  header "Installing Knative Serving operator"
  # Deploy the operator
  ko apply -f config/
  wait_until_pods_running default || fail_test "Serving Operator did not come up"
}

# Uninstalls Knative Serving from the current cluster.
function knative_teardown() {
  echo ">> Uninstalling Knative serving"
  echo "Istio YAML: ${INSTALL_ISTIO_YAML}"
  echo ">> Bringing down Serving"
  kubectl delete -n knative-serving knativeserving --all
  echo ">> Bringing down Istio"
  kubectl delete --ignore-not-found=true -f "${INSTALL_ISTIO_YAML}" || return 1
  kubectl delete --ignore-not-found=true clusterrolebinding cluster-admin-binding
  echo ">> Bringing down Serving Operator"
  ko delete --ignore-not-found=true -f config/ || return 1
  echo ">> Removing test namespaces"
  kubectl delete all --all --ignore-not-found --now --timeout 60s -n $TEST_NAMESPACE
  kubectl delete --ignore-not-found --now --timeout 300s namespace $TEST_NAMESPACE
}
