#!/bin/bash
# E2E tests for Kafka (Strimzi) flow

SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
source "${SCRIPT_DIR}/../lib/testlib.sh"

# Kafka configuration
KAFKA_NAMESPACE="kafka"
KAFKA_CLUSTER_NAME="kafka"
STRIMZI_HELM_RELEASE="strimzi-cluster-operator"

########################
# Test: Kafka namespace exists
#########################
test_kafka_namespace() {
  test_start "Kafka namespace exists"

  if namespace_exists "$KAFKA_NAMESPACE"; then
    test_pass
  else
    test_fail "Namespace '$KAFKA_NAMESPACE' does not exist"
  fi
}

########################
# Test: Strimzi operator is running
#########################
test_strimzi_operator() {
  test_start "Strimzi operator is running"

  if ! namespace_exists "$KAFKA_NAMESPACE"; then
    test_skip "Kafka namespace does not exist"
    return
  fi

  local count
  count=$(count_ready_pods "strimzi.io/kind=cluster-operator" "$KAFKA_NAMESPACE")

  if assert_gte "$count" 1; then
    test_pass "Found $count Strimzi operator pod(s)"
  else
    test_fail "No Strimzi operator pods running"
  fi
}

########################
# Test: Strimzi CRDs are installed
#########################
test_strimzi_crds() {
  test_start "Strimzi CRDs are installed"

  local expected_crds=("kafkas.kafka.strimzi.io" "kafkatopics.kafka.strimzi.io" "kafkausers.kafka.strimzi.io")
  local missing_crds=()

  for crd in "${expected_crds[@]}"; do
    if ! crd_exists "$crd"; then
      missing_crds+=("$crd")
    fi
  done

  if [[ ${#missing_crds[@]} -eq 0 ]]; then
    test_pass "All ${#expected_crds[@]} Strimzi CRDs installed"
  else
    test_fail "Missing CRDs: ${missing_crds[*]}"
  fi
}

########################
# Test: Kafka cluster CR exists and is ready
#########################
test_kafka_cluster_ready() {
  test_start "Kafka cluster is ready"

  if ! namespace_exists "$KAFKA_NAMESPACE"; then
    test_skip "Kafka namespace does not exist"
    return
  fi

  local status
  status=$(microk8s kubectl get kafka "$KAFKA_CLUSTER_NAME" -n "$KAFKA_NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)

  if [[ "$status" == "True" ]]; then
    test_pass
  elif [[ -z "$status" ]]; then
    test_fail "Kafka CR does not exist or has no status"
  else
    test_fail "Kafka cluster not ready (status: $status)"
  fi
}

########################
# Test: Kafka controller pods are running
#########################
test_kafka_controllers() {
  test_start "Kafka controller pods are running"

  if ! namespace_exists "$KAFKA_NAMESPACE"; then
    test_skip "Kafka namespace does not exist"
    return
  fi

  local count
  # Use strimzi.io/pool-name=controller label which is set on all Kafka node pool pods
  count=$(microk8s kubectl get pods -n "$KAFKA_NAMESPACE" -l "strimzi.io/pool-name=controller" --no-headers 2>/dev/null | grep -c "Running" || echo "0")

  if [[ "$count" -ge 3 ]]; then
    test_pass "Found $count Kafka controller pod(s)"
  else
    test_fail "Expected 3 controller pods, found $count"
  fi
}

########################
# Test: Entity operator is running
#########################
test_entity_operator() {
  test_start "Entity operator is running"

  if ! namespace_exists "$KAFKA_NAMESPACE"; then
    test_skip "Kafka namespace does not exist"
    return
  fi

  local count
  count=$(count_ready_pods "strimzi.io/name=${KAFKA_CLUSTER_NAME}-entity-operator" "$KAFKA_NAMESPACE")

  if assert_gte "$count" 1; then
    test_pass "Entity operator is running"
  else
    test_fail "Entity operator is not running"
  fi
}

########################
# Test: Kafka bootstrap LoadBalancer service exists
#########################
test_kafka_bootstrap_service() {
  test_start "Kafka bootstrap LoadBalancer service exists"

  if ! namespace_exists "$KAFKA_NAMESPACE"; then
    test_skip "Kafka namespace does not exist"
    return
  fi

  local svc_name="${KAFKA_CLUSTER_NAME}-kafka-external-bootstrap"

  if service_has_external_ip "$svc_name" "$KAFKA_NAMESPACE"; then
    local ip
    ip=$(microk8s kubectl get svc "$svc_name" -n "$KAFKA_NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
    test_pass "Bootstrap service has external IP: $ip"
  else
    # Check if service exists but no IP yet
    if microk8s kubectl get svc "$svc_name" -n "$KAFKA_NAMESPACE" &>/dev/null; then
      test_fail "Bootstrap service exists but has no external IP"
    else
      test_fail "Bootstrap service does not exist"
    fi
  fi
}

########################
# Test: Individual broker LoadBalancer services exist
#########################
test_kafka_broker_services() {
  test_start "Kafka broker LoadBalancer services exist"

  if ! namespace_exists "$KAFKA_NAMESPACE"; then
    test_skip "Kafka namespace does not exist"
    return
  fi

  local services_with_ip=0
  local expected_brokers=3

  for i in $(seq 0 $((expected_brokers - 1))); do
    local svc_name="${KAFKA_CLUSTER_NAME}-controller-$i"
    if service_has_external_ip "$svc_name" "$KAFKA_NAMESPACE"; then
      ((services_with_ip++))
    fi
  done

  if [[ $services_with_ip -eq $expected_brokers ]]; then
    test_pass "All $expected_brokers broker services have external IPs"
  else
    test_fail "Only $services_with_ip of $expected_brokers broker services have external IPs"
  fi
}

########################
# Test: Helm releases exist
#########################
test_kafka_helm_releases() {
  test_start "Kafka Helm release exists"

  # Check if release exists (may show as 'failed' due to race condition, but deployment works)
  local release_info
  release_info=$(microk8s helm3 list -n "$KAFKA_NAMESPACE" 2>/dev/null | grep "$STRIMZI_HELM_RELEASE" || echo "")

  if [[ -n "$release_info" ]]; then
    test_pass "Strimzi Helm release exists"
  else
    test_fail "Strimzi Helm release does not exist"
  fi
}

########################
# Test: Kafka refresh command
# WARNING: This is a destructive test
#########################
test_kafka_refresh() {
  test_start "devenv.sh kafka refresh command"

  if [[ "${RUN_DESTRUCTIVE_TESTS:-false}" != "true" ]]; then
    test_skip "Destructive test - set RUN_DESTRUCTIVE_TESTS=true to run"
    return
  fi

  local output
  output=$(run_devenv "kafka" "refresh")

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
# Test: Kafka remove command
# WARNING: This is a destructive test
#########################
test_kafka_remove() {
  test_start "devenv.sh kafka remove command"

  if [[ "${RUN_DESTRUCTIVE_TESTS:-false}" != "true" ]]; then
    test_skip "Destructive test - set RUN_DESTRUCTIVE_TESTS=true to run"
    return
  fi

  local output
  output=$(run_devenv "kafka" "remove")

  if [[ $DEVENV_EXIT_CODE -eq 0 ]]; then
    # Verify namespace is gone
    sleep 5
    if ! namespace_exists "$KAFKA_NAMESPACE"; then
      test_pass "Kafka removed and namespace deleted"
    else
      test_fail "Kafka removal completed but namespace still exists"
    fi
  else
    test_fail "Command failed with exit code $DEVENV_EXIT_CODE"
  fi
}

########################
# Main test runner
#########################
main() {
  init_test_suite "Kafka (Strimzi) E2E Tests"

  # Check prerequisites
  if ! is_microk8s_running; then
    echo -e "${RED}ERROR: microk8s is not running${NC}"
    exit 1
  fi

  # Run all tests
  test_kafka_namespace
  test_strimzi_crds
  test_strimzi_operator
  test_kafka_helm_releases
  test_kafka_cluster_ready
  test_kafka_controllers
  test_entity_operator
  test_kafka_bootstrap_service
  test_kafka_broker_services

  # Destructive tests (skipped by default)
  test_kafka_refresh
  test_kafka_remove

  print_summary
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
