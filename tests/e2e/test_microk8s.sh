#!/bin/bash
# E2E tests for microk8s flow

SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
source "${SCRIPT_DIR}/../lib/testlib.sh"

# Expected plugins from devenv.sh
EXPECTED_PLUGINS=("kube-ovn" "dns" "dashboard" "storage" "registry" "metrics-server" "metallb" "helm3")

########################
# Test: microk8s is installed and running
#########################
test_microk8s_running() {
  test_start "microk8s is running"

  if is_microk8s_running; then
    test_pass
  else
    test_fail "microk8s is not running"
  fi
}

########################
# Test: All required plugins are enabled
#########################
test_plugins_enabled() {
  test_start "All required plugins are enabled"

  local status
  status=$(microk8s status 2>/dev/null)
  local missing_plugins=()

  # Extract only the enabled section
  local enabled_section
  enabled_section=$(echo "$status" | sed -n '/^  enabled:/,/^  disabled:/p' | head -n -1)

  for plugin in "${EXPECTED_PLUGINS[@]}"; do
    # Special handling for storage (shows as hostpath-storage)
    local check_plugin="$plugin"
    if [[ "$plugin" == "storage" ]]; then
      check_plugin="hostpath-storage"
    fi

    # Check if plugin name appears in enabled section (format: "    plugin-name   # description")
    if ! echo "$enabled_section" | grep -qE "^\s+${check_plugin}\s+#"; then
      missing_plugins+=("$plugin")
    fi
  done

  if [[ ${#missing_plugins[@]} -eq 0 ]]; then
    test_pass "All ${#EXPECTED_PLUGINS[@]} plugins enabled"
  else
    test_fail "Missing plugins: ${missing_plugins[*]}"
  fi
}

########################
# Test: CoreDNS is running
#########################
test_coredns_running() {
  test_start "CoreDNS pods are running"

  local count
  count=$(count_ready_pods "k8s-app=kube-dns" "kube-system")

  if assert_gte "$count" 1; then
    test_pass "Found $count CoreDNS pod(s)"
  else
    test_fail "No CoreDNS pods running"
  fi
}

########################
# Test: Dashboard is accessible
#########################
test_dashboard_running() {
  test_start "Kubernetes Dashboard is running"

  if namespace_exists "kubernetes-dashboard"; then
    local count
    count=$(count_ready_pods "app.kubernetes.io/instance=kubernetes-dashboard" "kubernetes-dashboard")
    if assert_gte "$count" 1; then
      test_pass "Found $count Dashboard pod(s)"
    else
      test_fail "No Dashboard pods running"
    fi
  else
    test_fail "kubernetes-dashboard namespace does not exist"
  fi
}

########################
# Test: MetalLB is configured
#########################
test_metallb_running() {
  test_start "MetalLB is running"

  if namespace_exists "metallb-system"; then
    local count
    count=$(count_ready_pods "app=metallb" "metallb-system")
    if assert_gte "$count" 1; then
      test_pass "Found $count MetalLB pod(s)"
    else
      test_fail "No MetalLB pods running"
    fi
  else
    test_fail "metallb-system namespace does not exist"
  fi
}

########################
# Test: Metrics Server is running
#########################
test_metrics_server_running() {
  test_start "Metrics Server is running"

  local count
  count=$(count_ready_pods "k8s-app=metrics-server" "kube-system")

  if assert_gte "$count" 1; then
    test_pass "Found $count Metrics Server pod(s)"
  else
    test_fail "No Metrics Server pods running"
  fi
}

########################
# Test: Container Registry is running
#########################
test_registry_running() {
  test_start "Container Registry is running"

  if namespace_exists "container-registry"; then
    local count
    count=$(count_ready_pods "app=registry" "container-registry")
    if assert_gte "$count" 1; then
      test_pass "Found $count Registry pod(s)"
    else
      test_fail "No Registry pods running"
    fi
  else
    test_fail "container-registry namespace does not exist"
  fi
}

########################
# Test: Kube-OVN is running
#########################
test_kube_ovn_running() {
  test_start "Kube-OVN is running"

  local count
  count=$(count_ready_pods "app=ovs" "kube-system")

  if assert_gte "$count" 1; then
    test_pass "Found $count OVS pod(s)"
  else
    test_fail "No OVS pods running"
  fi
}

########################
# Test: Kong API Gateway is running (if enabled)
#########################
test_kong_running() {
  test_start "Kong API Gateway is running"

  if namespace_exists "kong"; then
    local count
    count=$(count_ready_pods "app.kubernetes.io/name=kong" "kong")
    if assert_gte "$count" 1; then
      # Check for LoadBalancer IP
      if service_has_external_ip "kong-kong-proxy" "kong"; then
        local ip
        ip=$(microk8s kubectl get svc kong-kong-proxy -n kong -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
        test_pass "Kong running with external IP: $ip"
      else
        test_pass "Kong running (no LoadBalancer IP yet)"
      fi
    else
      test_fail "No Kong pods running"
    fi
  else
    test_skip "Kong namespace does not exist (Kong may be disabled)"
  fi
}

########################
# Test: Can access kubernetes API
#########################
test_k8s_api_access() {
  test_start "Kubernetes API is accessible"

  if microk8s kubectl cluster-info &>/dev/null; then
    test_pass
  else
    test_fail "Cannot access Kubernetes API"
  fi
}

########################
# Test: Helm is working
#########################
test_helm_working() {
  test_start "Helm is working"

  if microk8s helm3 version &>/dev/null; then
    local version
    version=$(microk8s helm3 version --short 2>/dev/null)
    test_pass "Helm version: $version"
  else
    test_fail "Helm is not working"
  fi
}

########################
# Test: Storage class exists
#########################
test_storage_class() {
  test_start "Default storage class exists"

  local sc
  sc=$(microk8s kubectl get storageclass microk8s-hostpath -o name 2>/dev/null)

  if [[ -n "$sc" ]]; then
    test_pass "microk8s-hostpath storage class exists"
  else
    test_fail "microk8s-hostpath storage class not found"
  fi
}

########################
# Test: microk8s refresh command
# WARNING: This is a destructive test
#########################
test_refresh_command() {
  test_start "devenv.sh microk8s refresh command"

  if [[ "${RUN_DESTRUCTIVE_TESTS:-false}" != "true" ]]; then
    test_skip "Destructive test - set RUN_DESTRUCTIVE_TESTS=true to run"
    return
  fi

  local output
  output=$(run_devenv "microk8s" "refresh")

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
# Main test runner
#########################
main() {
  init_test_suite "microk8s E2E Tests"

  # Check prerequisites
  if ! command -v microk8s &>/dev/null; then
    echo -e "${RED}ERROR: microk8s is not installed${NC}"
    exit 1
  fi

  # Run all tests
  test_microk8s_running
  test_k8s_api_access
  test_helm_working
  test_plugins_enabled
  test_coredns_running
  test_dashboard_running
  test_metallb_running
  test_metrics_server_running
  test_registry_running
  test_kube_ovn_running
  test_storage_class
  test_kong_running

  # Destructive tests (skipped by default)
  test_refresh_command

  print_summary
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
