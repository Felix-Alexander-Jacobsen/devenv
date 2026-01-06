# DevEnv E2E Test Suite

End-to-end tests for the DevEnv Kubernetes development environment setup scripts.

## Overview

This test suite validates the complete functionality of the DevEnv scripts, which automate the deployment and management of a local Kubernetes development environment using microk8s.

## Project Rationale

The DevEnv scripts manage a complex multi-component Kubernetes environment including:
- **microk8s** - Lightweight Kubernetes distribution
- **Kafka** (Strimzi) - Event streaming platform
- **MongoDB** (Percona) - Document database

Manual testing of these components is time-consuming and error-prone. This E2E test suite provides:
- Automated validation of deployments
- Regression testing after code changes
- Documentation of expected system state
- CI/CD integration capability

## Features

### Test Categories

| Category | Description |
|----------|-------------|
| **Non-destructive** | Read-only checks of current system state (default) |
| **Destructive** | Tests that modify state (remove, refresh, stop, start) |

### What's Tested

#### microk8s Tests
- microk8s installation and status
- Plugin enablement (kube-ovn, dns, dashboard, storage, registry, metrics-server, metallb, helm3)
- CoreDNS availability
- Kubernetes Dashboard
- MetalLB load balancer
- Container Registry
- Storage class configuration
- Kong API Gateway (if enabled)
- Kubernetes API accessibility
- Helm functionality

#### Kafka (Strimzi) Tests
- Namespace existence
- Strimzi operator deployment
- CRD installation
- Kafka cluster CR status
- Controller pod health (3 replicas)
- Entity operator status
- LoadBalancer services (bootstrap + per-broker)
- Helm release verification

#### MongoDB (Percona) Tests
- Namespace existence
- Percona operator deployment
- CRD installation
- MongoDB cluster CR status
- Replica set pod health (3 replicas)
- LoadBalancer services (per-replica)
- Secret creation and content
- PVC binding
- Helm release verification

## Architecture

```
tests/
├── README.md           # This file
├── run_tests.sh        # Main test runner
├── lib/
│   └── testlib.sh      # Test utility library (assertions, helpers)
└── e2e/
    ├── test_microk8s.sh   # microk8s E2E tests
    ├── test_kafka.sh      # Kafka E2E tests
    └── test_mongodb.sh    # MongoDB E2E tests
```

### Test Library (testlib.sh)

The test library provides:

**Test Lifecycle:**
- `init_test_suite` - Initialize a test suite
- `test_start` - Begin a test case
- `test_pass` / `test_fail` / `test_skip` - Record test results
- `print_summary` - Display test results

**Assertions:**
- `assert_success` - Command should succeed
- `assert_failure` - Command should fail
- `assert_contains` - String contains substring
- `assert_equals` - String equality
- `assert_gte` - Numeric greater than or equal

**Kubernetes Helpers:**
- `is_microk8s_running` - Check microk8s status
- `namespace_exists` - Check namespace
- `pods_running` - Check pod status by selector
- `count_ready_pods` - Count running pods
- `service_has_external_ip` - Check LoadBalancer IP
- `helm_release_exists` - Check Helm release
- `crd_exists` - Check CRD installation
- `wait_for` - Wait for condition with timeout

**DevEnv Integration:**
- `run_devenv` - Execute devenv.sh commands

## Usage

### Run All Non-Destructive Tests

```bash
./tests/run_tests.sh
```

### Run Specific Test Suite

```bash
./tests/run_tests.sh microk8s        # Only microk8s tests
./tests/run_tests.sh kafka           # Only Kafka tests
./tests/run_tests.sh mongodb         # Only MongoDB tests
./tests/run_tests.sh kafka mongodb   # Multiple suites
```

### Run Including Destructive Tests

```bash
./tests/run_tests.sh --destructive
# or
RUN_DESTRUCTIVE_TESTS=true ./tests/run_tests.sh
```

### List Available Test Suites

```bash
./tests/run_tests.sh --list
```

### Run Individual Test File

```bash
./tests/e2e/test_microk8s.sh
./tests/e2e/test_kafka.sh
./tests/e2e/test_mongodb.sh
```

## Test Output

Tests produce colored output indicating status:

- `[TEST]` - Test starting (blue)
- `[PASS]` - Test passed (green)
- `[FAIL]` - Test failed (red)
- `[SKIP]` - Test skipped (yellow)

### Example Output

```
========================================
  Test Suite: microk8s E2E Tests
========================================

[TEST] microk8s is running...
[PASS] microk8s is running
[TEST] Kubernetes API is accessible...
[PASS] Kubernetes API is accessible
[TEST] Helm is working...
[PASS] Helm is working - Helm version: v3.16.4+g7877b45
[TEST] All required plugins are enabled...
[PASS] All required plugins are enabled - All 8 plugins enabled

========================================
  Test Summary
========================================
Passed:  12
Failed:  0
Skipped: 1

SUITE PASSED
```

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | All tests passed |
| 1 | One or more tests failed |

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `RUN_DESTRUCTIVE_TESTS` | `false` | Enable destructive tests |
| `SLOW_MOTION_TEXT` | `true` | Disable for faster devenv.sh execution |

## Writing New Tests

### Adding a Test Case

```bash
test_my_new_check() {
  test_start "My new check description"

  if some_condition; then
    test_pass "Optional success message"
  else
    test_fail "Failure reason"
  fi
}
```

### Adding a Conditional Test

```bash
test_optional_feature() {
  test_start "Optional feature check"

  if ! namespace_exists "optional-ns"; then
    test_skip "Optional feature not installed"
    return
  fi

  # ... actual test logic
}
```

### Adding Destructive Tests

```bash
test_destructive_operation() {
  test_start "Destructive operation"

  if [[ "${RUN_DESTRUCTIVE_TESTS:-false}" != "true" ]]; then
    test_skip "Destructive test - set RUN_DESTRUCTIVE_TESTS=true to run"
    return
  fi

  # ... destructive test logic
}
```

## Integration with CI/CD

The test suite is designed for CI/CD integration:

```yaml
# Example GitHub Actions workflow
- name: Run E2E Tests
  run: |
    ./tests/run_tests.sh
  continue-on-error: false
```

For full environment testing including destructive tests:

```yaml
- name: Run Full E2E Tests
  run: |
    RUN_DESTRUCTIVE_TESTS=true ./tests/run_tests.sh
```

## Troubleshooting

### Tests Fail Immediately

Ensure microk8s is installed and running:
```bash
microk8s status --wait-ready
```

### Namespace Tests Fail

Components may not be deployed. Run the appropriate devenv flow:
```bash
./devenv.sh kafka refresh
./devenv.sh mongodb refresh
```

### LoadBalancer Tests Fail

MetalLB may not have assigned IPs. Check:
```bash
microk8s kubectl get svc -A | grep LoadBalancer
```

### Destructive Tests Not Running

Set the environment variable:
```bash
export RUN_DESTRUCTIVE_TESTS=true
./tests/run_tests.sh
```
