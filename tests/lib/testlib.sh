#!/bin/bash
# Test utility library for devenv E2E tests

# Colors for test output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0
CURRENT_TEST=""

# Test result storage
declare -a FAILED_TESTS=()
declare -a SKIPPED_TESTS=()

########################
# Initialize test suite
# Arguments:
#   suite name
# Returns:
#   none
#########################
init_test_suite() {
  local suite_name="$1"
  echo -e "${BLUE}========================================${NC}"
  echo -e "${BLUE}  Test Suite: ${suite_name}${NC}"
  echo -e "${BLUE}========================================${NC}"
  echo ""
  TESTS_PASSED=0
  TESTS_FAILED=0
  TESTS_SKIPPED=0
  FAILED_TESTS=()
  SKIPPED_TESTS=()
}

########################
# Start a test case
# Arguments:
#   test name
# Returns:
#   none
#########################
test_start() {
  CURRENT_TEST="$1"
  echo -e "${BLUE}[TEST]${NC} ${CURRENT_TEST}..."
}

########################
# Mark test as passed
# Arguments:
#   optional message
# Returns:
#   none
#########################
test_pass() {
  local msg="${1:-}"
  ((TESTS_PASSED++))
  if [[ -n "$msg" ]]; then
    echo -e "${GREEN}[PASS]${NC} ${CURRENT_TEST} - ${msg}"
  else
    echo -e "${GREEN}[PASS]${NC} ${CURRENT_TEST}"
  fi
}

########################
# Mark test as failed
# Arguments:
#   failure message
# Returns:
#   none
#########################
test_fail() {
  local msg="$1"
  ((TESTS_FAILED++))
  FAILED_TESTS+=("${CURRENT_TEST}: ${msg}")
  echo -e "${RED}[FAIL]${NC} ${CURRENT_TEST} - ${msg}"
}

########################
# Skip a test
# Arguments:
#   skip reason
# Returns:
#   none
#########################
test_skip() {
  local reason="$1"
  ((TESTS_SKIPPED++))
  SKIPPED_TESTS+=("${CURRENT_TEST}: ${reason}")
  echo -e "${YELLOW}[SKIP]${NC} ${CURRENT_TEST} - ${reason}"
}

########################
# Print test suite summary
# Arguments:
#   none
# Returns:
#   exit code (0 if all passed, 1 if any failed)
#########################
print_summary() {
  echo ""
  echo -e "${BLUE}========================================${NC}"
  echo -e "${BLUE}  Test Summary${NC}"
  echo -e "${BLUE}========================================${NC}"
  echo -e "${GREEN}Passed:${NC}  ${TESTS_PASSED}"
  echo -e "${RED}Failed:${NC}  ${TESTS_FAILED}"
  echo -e "${YELLOW}Skipped:${NC} ${TESTS_SKIPPED}"
  echo ""

  if [[ ${#FAILED_TESTS[@]} -gt 0 ]]; then
    echo -e "${RED}Failed tests:${NC}"
    for test in "${FAILED_TESTS[@]}"; do
      echo -e "  - ${test}"
    done
    echo ""
  fi

  if [[ ${#SKIPPED_TESTS[@]} -gt 0 ]]; then
    echo -e "${YELLOW}Skipped tests:${NC}"
    for test in "${SKIPPED_TESTS[@]}"; do
      echo -e "  - ${test}"
    done
    echo ""
  fi

  if [[ $TESTS_FAILED -gt 0 ]]; then
    echo -e "${RED}SUITE FAILED${NC}"
    return 1
  else
    echo -e "${GREEN}SUITE PASSED${NC}"
    return 0
  fi
}

########################
# Assert that a command succeeds
# Arguments:
#   command to run
# Returns:
#   0 on success, 1 on failure
#########################
assert_success() {
  local cmd="$1"
  if eval "$cmd" &>/dev/null; then
    return 0
  else
    return 1
  fi
}

########################
# Assert that a command fails
# Arguments:
#   command to run
# Returns:
#   0 on expected failure, 1 on unexpected success
#########################
assert_failure() {
  local cmd="$1"
  if eval "$cmd" &>/dev/null; then
    return 1
  else
    return 0
  fi
}

########################
# Assert string contains substring
# Arguments:
#   string
#   substring
# Returns:
#   0 if contains, 1 if not
#########################
assert_contains() {
  local string="$1"
  local substring="$2"
  if [[ "$string" == *"$substring"* ]]; then
    return 0
  else
    return 1
  fi
}

########################
# Assert string equals expected
# Arguments:
#   actual
#   expected
# Returns:
#   0 if equal, 1 if not
#########################
assert_equals() {
  local actual="$1"
  local expected="$2"
  if [[ "$actual" == "$expected" ]]; then
    return 0
  else
    return 1
  fi
}

########################
# Assert numeric greater than or equal
# Arguments:
#   actual
#   minimum
# Returns:
#   0 if >= minimum, 1 if not
#########################
assert_gte() {
  local actual="$1"
  local minimum="$2"
  if [[ "$actual" -ge "$minimum" ]]; then
    return 0
  else
    return 1
  fi
}

########################
# Check if microk8s is running
# Arguments:
#   none
# Returns:
#   0 if running, 1 if not
#########################
is_microk8s_running() {
  microk8s status --wait-ready &>/dev/null
}

########################
# Check if namespace exists
# Arguments:
#   namespace name
# Returns:
#   0 if exists, 1 if not
#########################
namespace_exists() {
  local ns="$1"
  microk8s kubectl get namespace "$ns" &>/dev/null
}

########################
# Check if pod is running
# Arguments:
#   pod label selector
#   namespace
# Returns:
#   0 if running, 1 if not
#########################
pods_running() {
  local selector="$1"
  local namespace="$2"
  local count
  count=$(microk8s kubectl get pods -n "$namespace" -l "$selector" -o jsonpath='{.items[*].status.phase}' 2>/dev/null | tr ' ' '\n' | grep -c "Running" || echo "0")
  [[ "$count" -gt 0 ]]
}

########################
# Get number of ready pods
# Arguments:
#   pod label selector
#   namespace
# Returns:
#   count of ready pods (single integer)
#########################
count_ready_pods() {
  local selector="$1"
  local namespace="$2"
  local count
  # Use wc -l with grep (not grep -c) to avoid exit code issues when no matches
  count=$(microk8s kubectl get pods -n "$namespace" -l "$selector" --no-headers 2>/dev/null | grep "Running" | wc -l)
  # Ensure we return a clean integer
  echo "$((count + 0))"
}

########################
# Check if service has external IP
# Arguments:
#   service name
#   namespace
# Returns:
#   0 if has IP, 1 if not
#########################
service_has_external_ip() {
  local svc="$1"
  local namespace="$2"
  local ip
  ip=$(microk8s kubectl get svc "$svc" -n "$namespace" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
  [[ -n "$ip" && "$ip" != "null" ]]
}

########################
# Check if Helm release exists
# Arguments:
#   release name
#   namespace
# Returns:
#   0 if exists, 1 if not
#########################
helm_release_exists() {
  local release="$1"
  local namespace="$2"
  microk8s helm3 status "$release" -n "$namespace" &>/dev/null
}

########################
# Check if CRD exists
# Arguments:
#   CRD name
# Returns:
#   0 if exists, 1 if not
#########################
crd_exists() {
  local crd="$1"
  microk8s kubectl get crd "$crd" &>/dev/null
}

########################
# Wait for condition with timeout
# Arguments:
#   condition command
#   timeout in seconds
#   description
# Returns:
#   0 if condition met, 1 if timeout
#########################
wait_for() {
  local condition="$1"
  local timeout="$2"
  local desc="$3"
  local elapsed=0

  while [[ $elapsed -lt $timeout ]]; do
    if eval "$condition"; then
      return 0
    fi
    sleep 5
    ((elapsed+=5))
  done

  echo "Timeout waiting for: $desc"
  return 1
}

########################
# Run devenv command and capture output
# Arguments:
#   flow
#   action
# Returns:
#   command output (also stored in DEVENV_OUTPUT)
#########################
run_devenv() {
  local flow="$1"
  local action="$2"
  local devenv_dir
  devenv_dir="$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")")"

  # Run with SLOW_MOTION_TEXT=false to speed up tests
  DEVENV_OUTPUT=$(cd "$devenv_dir/.." && SLOW_MOTION_TEXT=false ./devenv.sh "$flow" "$action" 2>&1)
  DEVENV_EXIT_CODE=$?
  echo "$DEVENV_OUTPUT"
}
