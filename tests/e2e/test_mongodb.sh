#!/bin/bash
# E2E tests for MongoDB (Percona) flow

SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
source "${SCRIPT_DIR}/../lib/testlib.sh"

# MongoDB configuration
MONGODB_NAMESPACE="mongodb"
MONGODB_CR_NAME="mongodb-psmdb-db"
MONGODB_RELEASE_NAME="mongodb"
PERCONA_OPERATOR_NAME="psmdb-operator"

########################
# Test: MongoDB namespace exists
#########################
test_mongodb_namespace() {
  test_start "MongoDB namespace exists"

  if namespace_exists "$MONGODB_NAMESPACE"; then
    test_pass
  else
    test_fail "Namespace '$MONGODB_NAMESPACE' does not exist"
  fi
}

########################
# Test: Percona operator is running
#########################
test_percona_operator() {
  test_start "Percona operator is running"

  if ! namespace_exists "$MONGODB_NAMESPACE"; then
    test_skip "MongoDB namespace does not exist"
    return
  fi

  local count
  count=$(count_ready_pods "app.kubernetes.io/name=psmdb-operator" "$MONGODB_NAMESPACE")

  if assert_gte "$count" 1; then
    test_pass "Found $count Percona operator pod(s)"
  else
    test_fail "No Percona operator pods running"
  fi
}

########################
# Test: Percona CRDs are installed
#########################
test_percona_crds() {
  test_start "Percona CRDs are installed"

  local expected_crds=("perconaservermongodbs.psmdb.percona.com")
  local missing_crds=()

  for crd in "${expected_crds[@]}"; do
    if ! crd_exists "$crd"; then
      missing_crds+=("$crd")
    fi
  done

  if [[ ${#missing_crds[@]} -eq 0 ]]; then
    test_pass "All Percona CRDs installed"
  else
    test_fail "Missing CRDs: ${missing_crds[*]}"
  fi
}

########################
# Test: MongoDB cluster CR exists and is ready
#########################
test_mongodb_cluster_ready() {
  test_start "MongoDB cluster is ready"

  if ! namespace_exists "$MONGODB_NAMESPACE"; then
    test_skip "MongoDB namespace does not exist"
    return
  fi

  local status
  status=$(microk8s kubectl get psmdb "$MONGODB_CR_NAME" -n "$MONGODB_NAMESPACE" -o jsonpath='{.status.state}' 2>/dev/null)

  if [[ "$status" == "ready" ]]; then
    test_pass
  elif [[ -z "$status" ]]; then
    test_fail "MongoDB CR does not exist or has no status"
  else
    test_fail "MongoDB cluster not ready (status: $status)"
  fi
}

########################
# Test: MongoDB replica set pods are running
#########################
test_mongodb_replicas() {
  test_start "MongoDB replica set pods are running"

  if ! namespace_exists "$MONGODB_NAMESPACE"; then
    test_skip "MongoDB namespace does not exist"
    return
  fi

  local count
  count=$(count_ready_pods "app.kubernetes.io/instance=${MONGODB_CR_NAME}" "$MONGODB_NAMESPACE")

  if assert_gte "$count" 3; then
    test_pass "Found $count MongoDB replica pod(s)"
  else
    test_fail "Expected 3 replica pods, found $count"
  fi
}

########################
# Test: MongoDB LoadBalancer services exist
#########################
test_mongodb_services() {
  test_start "MongoDB LoadBalancer services exist"

  if ! namespace_exists "$MONGODB_NAMESPACE"; then
    test_skip "MongoDB namespace does not exist"
    return
  fi

  local services_with_ip=0
  local expected_replicas=3

  for i in $(seq 0 $((expected_replicas - 1))); do
    local svc_name="${MONGODB_CR_NAME}-rs0-$i"
    if service_has_external_ip "$svc_name" "$MONGODB_NAMESPACE"; then
      ((services_with_ip++))
    fi
  done

  if [[ $services_with_ip -eq $expected_replicas ]]; then
    local ips=""
    for i in $(seq 0 $((expected_replicas - 1))); do
      local svc_name="${MONGODB_CR_NAME}-rs0-$i"
      local ip
      ip=$(microk8s kubectl get svc "$svc_name" -n "$MONGODB_NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
      ips="${ips}${ip}, "
    done
    test_pass "All $expected_replicas replica services have external IPs: ${ips%, }"
  else
    test_fail "Only $services_with_ip of $expected_replicas replica services have external IPs"
  fi
}

########################
# Test: MongoDB secrets exist
#########################
test_mongodb_secrets() {
  test_start "MongoDB secrets exist"

  if ! namespace_exists "$MONGODB_NAMESPACE"; then
    test_skip "MongoDB namespace does not exist"
    return
  fi

  local secrets_name="${MONGODB_CR_NAME}-secrets"

  if microk8s kubectl get secret "$secrets_name" -n "$MONGODB_NAMESPACE" &>/dev/null; then
    # Check if required keys exist
    local keys
    keys=$(microk8s kubectl get secret "$secrets_name" -n "$MONGODB_NAMESPACE" -o jsonpath='{.data}' 2>/dev/null)

    if assert_contains "$keys" "MONGODB_USER_ADMIN_PASSWORD"; then
      test_pass "Secrets exist with required credentials"
    else
      test_fail "Secrets exist but missing required keys"
    fi
  else
    test_fail "Secret '$secrets_name' does not exist"
  fi
}

########################
# Test: Helm releases exist
#########################
test_mongodb_helm_releases() {
  test_start "MongoDB Helm releases exist"

  if ! namespace_exists "$MONGODB_NAMESPACE"; then
    test_skip "MongoDB namespace does not exist"
    return
  fi

  local missing_releases=()

  if ! helm_release_exists "$MONGODB_RELEASE_NAME" "$MONGODB_NAMESPACE"; then
    missing_releases+=("$MONGODB_RELEASE_NAME")
  fi

  if ! helm_release_exists "$PERCONA_OPERATOR_NAME" "$MONGODB_NAMESPACE"; then
    missing_releases+=("$PERCONA_OPERATOR_NAME")
  fi

  if [[ ${#missing_releases[@]} -eq 0 ]]; then
    test_pass "Both MongoDB and operator Helm releases exist"
  else
    test_fail "Missing Helm releases: ${missing_releases[*]}"
  fi
}

########################
# Test: PVCs are bound
#########################
test_mongodb_pvcs() {
  test_start "MongoDB PVCs are bound"

  if ! namespace_exists "$MONGODB_NAMESPACE"; then
    test_skip "MongoDB namespace does not exist"
    return
  fi

  local pvc_count
  pvc_count=$(microk8s kubectl get pvc -n "$MONGODB_NAMESPACE" -l "app.kubernetes.io/instance=${MONGODB_CR_NAME}" --no-headers 2>/dev/null | grep -c "Bound" || echo "0")

  if assert_gte "$pvc_count" 3; then
    test_pass "Found $pvc_count bound PVC(s)"
  else
    test_fail "Expected at least 3 bound PVCs, found $pvc_count"
  fi
}

########################
# Test: MongoDB stop command
# WARNING: This is a destructive test
#########################
test_mongodb_stop() {
  test_start "devenv.sh mongodb stop command"

  if [[ "${RUN_DESTRUCTIVE_TESTS:-false}" != "true" ]]; then
    test_skip "Destructive test - set RUN_DESTRUCTIVE_TESTS=true to run"
    return
  fi

  local output
  output=$(run_devenv "mongodb" "stop")

  if [[ $DEVENV_EXIT_CODE -eq 0 ]]; then
    # Verify pods are stopped
    sleep 5
    local count
    # Use wc -l with grep to avoid exit code issues
    count=$(microk8s kubectl get pods -n "$MONGODB_NAMESPACE" -l "app.kubernetes.io/instance=${MONGODB_CR_NAME}" --no-headers 2>/dev/null | grep "Running" | wc -l)
    count=$((count + 0))  # Ensure it's a number
    if [[ $count -eq 0 ]]; then
      test_pass "MongoDB stopped (0 running pods)"
    else
      test_fail "MongoDB stop completed but $count pods still running"
    fi
  else
    test_fail "Command failed with exit code $DEVENV_EXIT_CODE"
  fi
}

########################
# Test: MongoDB start command
# WARNING: This is a destructive test
#########################
test_mongodb_start() {
  test_start "devenv.sh mongodb start command"

  if [[ "${RUN_DESTRUCTIVE_TESTS:-false}" != "true" ]]; then
    test_skip "Destructive test - set RUN_DESTRUCTIVE_TESTS=true to run"
    return
  fi

  local output
  output=$(run_devenv "mongodb" "start")

  if [[ $DEVENV_EXIT_CODE -eq 0 ]]; then
    # Wait for pods to come up
    wait_for "assert_gte \$(count_ready_pods 'app.kubernetes.io/instance=${MONGODB_CR_NAME}' '$MONGODB_NAMESPACE') 3" 120 "MongoDB pods to start"
    local count
    count=$(count_ready_pods "app.kubernetes.io/instance=${MONGODB_CR_NAME}" "$MONGODB_NAMESPACE")
    if assert_gte "$count" 3; then
      test_pass "MongoDB started ($count running pods)"
    else
      test_fail "MongoDB start completed but only $count pods running"
    fi
  else
    test_fail "Command failed with exit code $DEVENV_EXIT_CODE"
  fi
}

########################
# Test: MongoDB refresh command
# WARNING: This is a destructive test
#########################
test_mongodb_refresh() {
  test_start "devenv.sh mongodb refresh command"

  if [[ "${RUN_DESTRUCTIVE_TESTS:-false}" != "true" ]]; then
    test_skip "Destructive test - set RUN_DESTRUCTIVE_TESTS=true to run"
    return
  fi

  local output
  output=$(run_devenv "mongodb" "refresh")

  if [[ $DEVENV_EXIT_CODE -eq 0 ]]; then
    if assert_contains "$output" "Done"; then
      test_pass
    else
      test_fail "Command completed but 'Done' not found in output"
    fi
  else
    test_fail "Command failed with exit code $DEVENV_EXIT_CODE"
  fi
}

########################
# Test: MongoDB remove command
# WARNING: This is a destructive test
#########################
test_mongodb_remove() {
  test_start "devenv.sh mongodb remove command"

  if [[ "${RUN_DESTRUCTIVE_TESTS:-false}" != "true" ]]; then
    test_skip "Destructive test - set RUN_DESTRUCTIVE_TESTS=true to run"
    return
  fi

  local output
  output=$(run_devenv "mongodb" "remove")

  if [[ $DEVENV_EXIT_CODE -eq 0 ]]; then
    # Verify namespace is gone
    sleep 5
    if ! namespace_exists "$MONGODB_NAMESPACE"; then
      test_pass "MongoDB removed and namespace deleted"
    else
      test_fail "MongoDB removal completed but namespace still exists"
    fi
  else
    test_fail "Command failed with exit code $DEVENV_EXIT_CODE"
  fi
}

########################
# Main test runner
#########################
main() {
  init_test_suite "MongoDB (Percona) E2E Tests"

  # Check prerequisites
  if ! is_microk8s_running; then
    echo -e "${RED}ERROR: microk8s is not running${NC}"
    exit 1
  fi

  # Run all tests
  test_mongodb_namespace
  test_percona_crds
  test_percona_operator
  test_mongodb_helm_releases
  test_mongodb_cluster_ready
  test_mongodb_replicas
  test_mongodb_services
  test_mongodb_secrets
  test_mongodb_pvcs

  # Destructive tests (skipped by default)
  test_mongodb_stop
  test_mongodb_start
  test_mongodb_refresh
  test_mongodb_remove

  print_summary
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
