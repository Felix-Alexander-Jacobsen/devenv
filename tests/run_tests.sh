#!/bin/bash
# Main test runner for devenv E2E tests
#
# Usage:
#   ./run_tests.sh                    # Run all tests (non-destructive only)
#   ./run_tests.sh microk8s           # Run only microk8s tests
#   ./run_tests.sh kafka mongodb      # Run kafka and mongodb tests
#   ./run_tests.sh --destructive      # Run all tests including destructive ones
#   ./run_tests.sh --help             # Show help
#
# Environment variables:
#   RUN_DESTRUCTIVE_TESTS=true        # Enable destructive tests

set -euo pipefail

SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
source "${SCRIPT_DIR}/lib/testlib.sh"

# Available test suites
declare -A TEST_SUITES
TEST_SUITES["microk8s"]="${SCRIPT_DIR}/e2e/test_microk8s.sh"
TEST_SUITES["kafka"]="${SCRIPT_DIR}/e2e/test_kafka.sh"
TEST_SUITES["mongodb"]="${SCRIPT_DIR}/e2e/test_mongodb.sh"

# Global counters
TOTAL_PASSED=0
TOTAL_FAILED=0
TOTAL_SKIPPED=0
SUITES_RUN=0
SUITES_FAILED=0

########################
# Print usage information
#########################
usage() {
  cat << EOF
DevEnv E2E Test Runner

Usage:
  $(basename "$0") [OPTIONS] [SUITE...]

Options:
  -d, --destructive    Run destructive tests (remove, refresh commands)
  -h, --help           Show this help message
  -l, --list           List available test suites

Suites:
  microk8s             Test microk8s installation and plugins
  kafka                Test Kafka (Strimzi) deployment
  mongodb              Test MongoDB (Percona) deployment

Examples:
  $(basename "$0")                    # Run all non-destructive tests
  $(basename "$0") microk8s           # Run only microk8s tests
  $(basename "$0") kafka mongodb      # Run kafka and mongodb tests
  $(basename "$0") -d                 # Run all tests including destructive ones
  $(basename "$0") -d mongodb         # Run mongodb tests with destructive tests

Environment Variables:
  RUN_DESTRUCTIVE_TESTS=true          # Enable destructive tests

Note: Destructive tests will actually remove and reinstall components.
      Use with caution in production environments.
EOF
}

########################
# List available test suites
#########################
list_suites() {
  echo "Available test suites:"
  echo ""
  for suite in "${!TEST_SUITES[@]}"; do
    echo "  - $suite"
  done
  echo ""
}

########################
# Run a single test suite
# Arguments:
#   suite name
# Returns:
#   0 if passed, 1 if failed
#########################
run_suite() {
  local suite="$1"
  local suite_script="${TEST_SUITES[$suite]}"

  if [[ ! -f "$suite_script" ]]; then
    echo -e "${RED}ERROR: Test suite script not found: $suite_script${NC}"
    return 1
  fi

  echo ""
  echo -e "${BLUE}Running test suite: ${suite}${NC}"
  echo ""

  # Run the suite and capture its exit code
  local exit_code=0
  bash "$suite_script" || exit_code=$?

  ((SUITES_RUN++))
  if [[ $exit_code -ne 0 ]]; then
    ((SUITES_FAILED++))
  fi

  return $exit_code
}

########################
# Print overall summary
#########################
print_overall_summary() {
  echo ""
  echo -e "${BLUE}========================================${NC}"
  echo -e "${BLUE}  Overall Test Results${NC}"
  echo -e "${BLUE}========================================${NC}"
  echo -e "Suites run:    ${SUITES_RUN}"
  echo -e "Suites failed: ${SUITES_FAILED}"
  echo ""

  if [[ $SUITES_FAILED -gt 0 ]]; then
    echo -e "${RED}OVERALL: FAILED${NC}"
    return 1
  else
    echo -e "${GREEN}OVERALL: PASSED${NC}"
    return 0
  fi
}

########################
# Main entry point
#########################
main() {
  local suites_to_run=()
  local show_help=false
  local show_list=false

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        show_help=true
        shift
        ;;
      -l|--list)
        show_list=true
        shift
        ;;
      -d|--destructive)
        export RUN_DESTRUCTIVE_TESTS=true
        shift
        ;;
      -*)
        echo -e "${RED}Unknown option: $1${NC}"
        usage
        exit 1
        ;;
      *)
        if [[ -v "TEST_SUITES[$1]" ]]; then
          suites_to_run+=("$1")
        else
          echo -e "${RED}Unknown test suite: $1${NC}"
          list_suites
          exit 1
        fi
        shift
        ;;
    esac
  done

  # Handle help and list options
  if $show_help; then
    usage
    exit 0
  fi

  if $show_list; then
    list_suites
    exit 0
  fi

  # Default to all suites if none specified
  if [[ ${#suites_to_run[@]} -eq 0 ]]; then
    suites_to_run=("microk8s" "kafka" "mongodb")
  fi

  # Print header
  echo -e "${BLUE}========================================${NC}"
  echo -e "${BLUE}  DevEnv E2E Test Runner${NC}"
  echo -e "${BLUE}========================================${NC}"
  echo ""
  echo "Date: $(date)"
  echo "Suites to run: ${suites_to_run[*]}"
  echo "Destructive tests: ${RUN_DESTRUCTIVE_TESTS:-false}"
  echo ""

  # Check prerequisites
  if ! command -v microk8s &>/dev/null; then
    echo -e "${RED}ERROR: microk8s is not installed${NC}"
    exit 1
  fi

  if ! microk8s status --wait-ready &>/dev/null; then
    echo -e "${RED}ERROR: microk8s is not running${NC}"
    exit 1
  fi

  # Run test suites
  local any_failed=false
  for suite in "${suites_to_run[@]}"; do
    if ! run_suite "$suite"; then
      any_failed=true
    fi
  done

  # Print overall summary
  if ! print_overall_summary; then
    exit 1
  fi
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
