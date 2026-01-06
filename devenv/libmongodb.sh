#!/bin/bash
# The MIT License (MIT)
#
# Copyright (c) 2022-2025 Felix Jacobsen
#
# Permission is hereby granted, free of charge, to any person obtaining a copy of
# this software and associated documentation files (the "Software"), to deal in
# the Software without restriction, including without limitation the rights to
# use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
# the Software, and to permit persons to whom the Software is furnished to do so,
# subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
# FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
# COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
# IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
# CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#
# Library for managing MongoDB using Percona Operator

# Percona Helm repository configuration
PERCONA_HELM_REPO="https://percona.github.io/percona-helm-charts/"
PERCONA_HELM_REPO_NAME="percona"
MONGODB_NAMESPACE="mongodb"
MONGODB_RELEASE_NAME="mongodb"
# Note: psmdb-db chart creates CR named {release}-psmdb-db
MONGODB_CR_NAME="mongodb-psmdb-db"

########################
# Gets mongodb cluster status
# Arguments:
#   status placeholder
# Returns:
#   mongodb status string
#########################
get_mongodb_status() {
  if [[ -z "$1" ]]; then
    log_error "Please make sure to pass a placeholder argument to get_mongodb_status() function."
    exit 1
  fi

  local mongodb_query=""
  mongodb_query=$(microk8s kubectl get psmdb "$MONGODB_CR_NAME" -n"$MONGODB_NAMESPACE" -o jsonpath='{.status.state}' 2>&1)

  if [[ $mongodb_query == *"Insufficient permissions to access MicroK8s"* ]]; then
    log_warn "$mongodb_query"
    log_error "Please run this script as root or with sudo."
    exit 1
  elif [[ $mongodb_query == *"NotFound"* ]] || [[ $mongodb_query == *"not found"* ]]; then
    mongodb_query="not_found"
  elif [[ $mongodb_query == *"error: the server doesn't have a resource type"* ]]; then
    mongodb_query="no_crd"
  fi

  # Use printf to safely assign value (avoids eval quoting issues)
  printf -v "$1" '%s' "$mongodb_query"
}

########################
# Checks if Percona operator is installed
# Arguments:
#   result placeholder
# Returns:
#   true or false
#########################
is_percona_operator_installed() {
  if [[ -z "$1" ]]; then
    log_error "Please make sure to pass a placeholder argument to is_percona_operator_installed() function."
    exit 1
  fi

  local operator_check=""
  operator_check=$(microk8s kubectl get deployment -n"$MONGODB_NAMESPACE" -l app.kubernetes.io/name=psmdb-operator 2>&1)

  if [[ $operator_check == *"No resources found"* ]] || [[ $operator_check == *"NotFound"* ]]; then
    printf -v "$1" '%s' "false"
  else
    printf -v "$1" '%s' "true"
  fi
}

########################
# Installs Percona operator using Helm
# Arguments:
#   none
# Returns:
#   none
#########################
install_percona_operator() {
  log_info "Installing Percona MongoDB operator version ${PERCONA_OPERATOR_VERSION}..."

  # Check if namespace exists
  log_info "Checking if '$MONGODB_NAMESPACE' namespace exists..."
  local namespace_check=""
  namespace_check=$(microk8s kubectl get namespace "$MONGODB_NAMESPACE" 2>&1)

  if [[ $namespace_check == *"NotFound"* ]] || [[ $namespace_check == *"not found"* ]]; then
    log_info "Creating namespace '$MONGODB_NAMESPACE'..."
    microk8s kubectl create namespace "$MONGODB_NAMESPACE"
    log_success "namespace/$MONGODB_NAMESPACE created"
  fi

  # Add Percona Helm repo if not present
  if ! microk8s helm3 repo list 2>/dev/null | grep -q "$PERCONA_HELM_REPO_NAME"; then
    microk8s helm3 repo add "$PERCONA_HELM_REPO_NAME" "$PERCONA_HELM_REPO"
  fi
  microk8s helm3 repo update

  # Clean up any failed release before fresh install
  local release_status=""
  release_status=$(microk8s helm3 status psmdb-operator -n"$MONGODB_NAMESPACE" -o json 2>/dev/null | grep -o '"status":"[^"]*"' | head -1 || echo "")
  if [[ "$release_status" == *"failed"* ]] || [[ "$release_status" == *"pending"* ]]; then
    log_info "Cleaning up failed/pending Helm release..."
    microk8s helm3 uninstall psmdb-operator -n"$MONGODB_NAMESPACE" 2>/dev/null || true
    sleep 2
  fi

  # Install Percona operator
  local install_result=""
  install_result=$(microk8s helm3 install psmdb-operator "$PERCONA_HELM_REPO_NAME/psmdb-operator" \
    --namespace "$MONGODB_NAMESPACE" \
    --version "$PERCONA_OPERATOR_VERSION" \
    --set watchNamespaces="$MONGODB_NAMESPACE" \
    --set disableTelemetry=true \
    --wait 2>&1)

  local helm_exit_code=$?

  # Check if the actual deployment exists regardless of Helm exit code
  if ! microk8s kubectl get deployment -n"$MONGODB_NAMESPACE" -l app.kubernetes.io/name=psmdb-operator &>/dev/null; then
    log_error "$install_result"
    log_error "Failed to install Percona operator, terminating script."
    exit 1
  fi

  log_info "Waiting for Percona operator deployment to be ready..."
  if ! microk8s kubectl wait --for=condition=Available deployment -l app.kubernetes.io/name=psmdb-operator -n"$MONGODB_NAMESPACE" --timeout=120s 2>&1; then
    log_error "Percona operator deployment failed to become ready."
    exit 1
  fi

  log_success "Percona operator installed successfully."
}

########################
# Deploys MongoDB cluster using Percona Helm chart
# Arguments:
#   highest ip assigned by loadbalancer
# Returns:
#   none
#########################
deploy_mongodb_cluster() {
  if [[ -z "$1" ]]; then
    log_error "Please make sure to pass the highest ip assigned by loadbalancer argument to deploy_mongodb_cluster() function."
    exit 1
  fi

  local last_ip_assigned_by_lb=$1

  # Calculate 4 IPs: 1 for general LB + 3 for replica set members
  local mongodb_lb_ip=""
  calculate_next_ip mongodb_lb_ip "$last_ip_assigned_by_lb"

  log_info "Deploying MongoDB cluster with LoadBalancer IP: $mongodb_lb_ip..."

  # Clean up any failed release before fresh install
  local release_status=""
  release_status=$(microk8s helm3 status "$MONGODB_RELEASE_NAME" -n"$MONGODB_NAMESPACE" -o json 2>/dev/null | grep -o '"status":"[^"]*"' | head -1 || echo "")
  if [[ "$release_status" == *"failed"* ]] || [[ "$release_status" == *"pending"* ]]; then
    log_info "Cleaning up failed/pending Helm release..."
    microk8s helm3 uninstall "$MONGODB_RELEASE_NAME" -n"$MONGODB_NAMESPACE" 2>/dev/null || true
    sleep 2
  fi

  # Install MongoDB cluster using Helm
  # - Disable sharding for simpler dev environment
  # - Use 3-node replica set
  # - Expose via LoadBalancer
  local install_result=""
  install_result=$(microk8s helm3 install "$MONGODB_RELEASE_NAME" "$PERCONA_HELM_REPO_NAME/psmdb-db" \
    --namespace "$MONGODB_NAMESPACE" \
    --version "$PERCONA_DB_VERSION" \
    --set "image.tag=${PERCONA_MONGODB_VERSION}" \
    --set "sharding.enabled=false" \
    --set "replsets.rs0.size=3" \
    --set "replsets.rs0.expose.enabled=true" \
    --set "replsets.rs0.expose.type=LoadBalancer" \
    --set "replsets.rs0.affinity.antiAffinityTopologyKey=none" \
    --set "replsets.rs0.resources.limits.cpu=1" \
    --set "replsets.rs0.resources.limits.memory=2Gi" \
    --set "replsets.rs0.resources.requests.cpu=300m" \
    --set "replsets.rs0.resources.requests.memory=500Mi" \
    --set "replsets.rs0.volumeSpec.pvc.storageClassName=microk8s-hostpath" \
    --set "replsets.rs0.volumeSpec.pvc.resources.requests.storage=5Gi" \
    --set "backup.enabled=false" \
    2>&1)

  if [[ "$?" -ne 0 ]]; then
    # Check if cluster CR was still created
    if ! microk8s kubectl get psmdb "$MONGODB_CR_NAME" -n"$MONGODB_NAMESPACE" &>/dev/null; then
      log_error "$install_result"
      log_error "Failed to deploy MongoDB cluster, terminating script."
      exit 1
    fi
  fi

  log_success "MongoDB cluster deployed successfully."
}

########################
# Waits for MongoDB cluster to be ready
# Arguments:
#   timeout in seconds (default 300)
# Returns:
#   none
#########################
wait_for_mongodb_cluster() {
  local timeout=${1:-300}
  local elapsed=0
  local interval=10

  log_info "Waiting for MongoDB cluster to be ready (max ${timeout}s)..."

  while [[ $elapsed -lt $timeout ]]; do
    local status=""
    get_mongodb_status status

    microk8s kubectl get pods -n"$MONGODB_NAMESPACE" -l app.kubernetes.io/instance="$MONGODB_CR_NAME" 2>/dev/null || true

    if [[ "$status" == "ready" ]]; then
      log_success "MongoDB cluster is ready."
      return 0
    elif [[ "$status" == "error" ]] || [[ "$status" == "failed" ]]; then
      log_error "MongoDB cluster entered error state: $status"
      return 1
    fi

    sleep $interval
    elapsed=$((elapsed + interval))
    log_info "Still waiting... (${elapsed}s/${timeout}s) - Status: $status"
  done

  log_error "Timeout waiting for MongoDB cluster to be ready."
  return 1
}

########################
# Gets MongoDB connection credentials
# Arguments:
#   none
# Returns:
#   prints connection info
#########################
get_mongodb_credentials() {
  log_info "MongoDB connection information:"

  local secret_name="${MONGODB_CR_NAME}-secrets"

  if microk8s kubectl get secret "$secret_name" -n"$MONGODB_NAMESPACE" &>/dev/null; then
    local admin_user="userAdmin"
    local admin_pass=""
    admin_pass=$(microk8s kubectl get secret "$secret_name" -n"$MONGODB_NAMESPACE" -o jsonpath='{.data.MONGODB_USER_ADMIN_PASSWORD}' 2>/dev/null | base64 -d)

    local cluster_admin_pass=""
    cluster_admin_pass=$(microk8s kubectl get secret "$secret_name" -n"$MONGODB_NAMESPACE" -o jsonpath='{.data.MONGODB_CLUSTER_ADMIN_PASSWORD}' 2>/dev/null | base64 -d)

    echo "  User Admin: userAdmin / $admin_pass"
    echo "  Cluster Admin: clusterAdmin / $cluster_admin_pass"
  else
    log_warn "Secrets not found yet. They will be created when the cluster initializes."
  fi

  # Get LoadBalancer IPs
  log_info "MongoDB LoadBalancer services:"
  microk8s kubectl get svc -n"$MONGODB_NAMESPACE" -l app.kubernetes.io/instance="$MONGODB_CR_NAME" | grep LoadBalancer || true
}

########################
# Updates mongodb /etc/hosts entries
# Arguments:
#   none
# Returns:
#   none
#########################
update_mongodb_etc_hosts() {
  # Get the first replica set member's LoadBalancer IP for general access
  local mongodb_ip=""
  mongodb_ip=$(microk8s kubectl get svc -n"$MONGODB_NAMESPACE" -l "app.kubernetes.io/instance=$MONGODB_CR_NAME,app.kubernetes.io/component=mongod" -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}' 2>/dev/null)

  if [[ -n "$mongodb_ip" ]]; then
    update_etc_hosts "mongodb$" "${mongodb_ip}"
    log_success "Updated /etc/hosts with mongodb -> ${mongodb_ip}"
  fi
}

########################
# Bootstraps mongodb: installs operator and cluster
# Arguments:
#   none
# Returns:
#   none
#########################
bootstrap_mongodb() {
  local operator_installed=""
  is_percona_operator_installed operator_installed

  if [[ "$operator_installed" == "false" ]]; then
    install_percona_operator
  else
    log_success "Percona operator is already installed."
  fi

  # Get highest IP assigned by loadbalancer
  local current_ip=""
  get_current_ip current_ip "$(ip route | grep default | awk '{print $5}')"
  local last_ip=""
  find_the_highest_ip_assigned_by_loadbalancer last_ip "$current_ip"

  # Deploy MongoDB cluster
  deploy_mongodb_cluster "$last_ip"

  # Wait for cluster to be ready
  wait_for_mongodb_cluster 300

  # Show connection info
  get_mongodb_credentials
}

########################
# Refreshes mongodb: installs if needed and waits until ready
# Arguments:
#   invoker username
#   current ip address
# Returns:
#   none
#########################
refresh_mongodb() {
  if [[ -z "$1" ]]; then
    log_error "Please make sure to pass invoker username argument to refresh_mongodb() function."
    exit 1
  fi

  if [[ -z "$2" ]]; then
    log_error "Please make sure to pass current ip address argument to refresh_mongodb() function."
    exit 1
  fi

  local invoker_username=$1
  local current_ip=$2

  local mongodb_status=""
  get_mongodb_status mongodb_status

  if [[ "$mongodb_status" == "ready" ]]; then
    log_success "MongoDB cluster is already running."
    get_mongodb_credentials
  elif [[ "$mongodb_status" == "initializing" ]] || [[ "$mongodb_status" == "pending" ]]; then
    log_warn "MongoDB cluster is initializing, waiting..."
    wait_for_mongodb_cluster 300
    get_mongodb_credentials
  elif [[ "$mongodb_status" == "not_found" ]] || [[ "$mongodb_status" == "no_crd" ]]; then
    log_warn "MongoDB cluster is not deployed, bootstrapping it now..."
    bootstrap_mongodb
  else
    log_warn "MongoDB status: $mongodb_status"
    log_info "Attempting to wait for cluster..."
    wait_for_mongodb_cluster 300
    get_mongodb_credentials
  fi

  update_mongodb_etc_hosts

  log_success "MongoDB is running."
  newline
}

########################
# Removes mongodb: deletes cluster, operator, and namespace
# Arguments:
#   none
# Returns:
#   none
#########################
remove_mongodb() {
  log_info "Removing MongoDB cluster and Percona operator..."

  # Delete MongoDB cluster via Helm
  log_info "Uninstalling MongoDB cluster Helm release..."
  microk8s helm3 uninstall "$MONGODB_RELEASE_NAME" -n"$MONGODB_NAMESPACE" 2>/dev/null || true

  # Remove finalizers from CR first (prevents hanging CRD deletion when operator is gone)
  log_info "Removing finalizers from MongoDB CR..."
  microk8s kubectl patch psmdb "$MONGODB_CR_NAME" -n"$MONGODB_NAMESPACE" -p '{"metadata":{"finalizers":null}}' --type=merge 2>/dev/null || true

  # Delete any remaining PSMDB CR
  microk8s kubectl delete psmdb "$MONGODB_CR_NAME" -n"$MONGODB_NAMESPACE" --ignore-not-found --grace-period=5 2>/dev/null || true

  # Force delete pods (don't wait - they may hang with finalizer issues)
  log_info "Force deleting MongoDB pods..."
  microk8s kubectl delete pods -l "app.kubernetes.io/instance=$MONGODB_CR_NAME" -n"$MONGODB_NAMESPACE" --force --grace-period=0 --ignore-not-found 2>/dev/null || true

  # Uninstall Percona operator via Helm
  log_info "Uninstalling Percona operator Helm release..."
  microk8s helm3 uninstall psmdb-operator -n"$MONGODB_NAMESPACE" 2>/dev/null || true

  # Clean up Percona CRDs
  log_info "Cleaning up Percona CRDs..."
  microk8s kubectl get crd -o name 2>/dev/null | grep -E 'percona\.com|psmdb' | xargs -r microk8s kubectl delete --ignore-not-found 2>/dev/null || true

  # Delete PVCs (data will be lost)
  log_info "Deleting PVCs..."
  microk8s kubectl delete pvc -l "app.kubernetes.io/instance=$MONGODB_CR_NAME" -n"$MONGODB_NAMESPACE" --ignore-not-found 2>/dev/null || true

  # Delete namespace
  log_info "Deleting mongodb namespace..."
  microk8s kubectl delete namespace "$MONGODB_NAMESPACE" --ignore-not-found --grace-period=30 2>/dev/null || true

  log_success "MongoDB and Percona operator removed."
}

########################
# Stops mongodb: scales cluster down to 0
# Arguments:
#   none
# Returns:
#   none
#########################
stop_mongodb() {
  log_info "Stopping MongoDB cluster..."

  local mongodb_status=""
  get_mongodb_status mongodb_status

  if [[ "$mongodb_status" == "not_found" ]] || [[ "$mongodb_status" == "no_crd" ]]; then
    log_error "MongoDB cluster does not exist, nothing to stop."
    exit 1
  fi

  # Scale down by pausing the cluster
  microk8s kubectl patch psmdb "$MONGODB_CR_NAME" -n"$MONGODB_NAMESPACE" --type=merge -p '{"spec":{"pause":true}}' 2>&1

  log_info "Waiting for MongoDB pods to terminate..."
  microk8s kubectl wait --for=delete pod -l "app.kubernetes.io/instance=$MONGODB_CR_NAME,app.kubernetes.io/component=mongod" -n"$MONGODB_NAMESPACE" --timeout=180s 2>/dev/null || true

  log_success "MongoDB has been stopped. PVCs are preserved."
  newline
}

########################
# Starts mongodb: unpauses the cluster
# Arguments:
#   invoker username
#   current ip address
# Returns:
#   none
#########################
start_mongodb() {
  if [[ -z "$1" ]]; then
    log_error "Please make sure to pass invoker username argument to start_mongodb() function."
    exit 1
  fi

  if [[ -z "$2" ]]; then
    log_error "Please make sure to pass current ip address argument to start_mongodb() function."
    exit 1
  fi

  local invoker_username=$1
  local current_ip=$2

  log_info "Starting MongoDB cluster..."

  local mongodb_status=""
  get_mongodb_status mongodb_status

  if [[ "$mongodb_status" == "not_found" ]] || [[ "$mongodb_status" == "no_crd" ]]; then
    log_warn "MongoDB cluster does not exist, bootstrapping..."
    bootstrap_mongodb
  elif [[ "$mongodb_status" == "ready" ]]; then
    log_warn "MongoDB is already running."
  else
    # Unpause the cluster
    microk8s kubectl patch psmdb "$MONGODB_CR_NAME" -n"$MONGODB_NAMESPACE" --type=merge -p '{"spec":{"pause":false}}' 2>&1
    wait_for_mongodb_cluster 300
  fi

  update_mongodb_etc_hosts
  get_mongodb_credentials

  log_success "MongoDB has been started."
  newline
}

########################
# Restarts mongodb: stops and starts the cluster
# Arguments:
#   invoker username
#   current ip address
# Returns:
#   none
#########################
restart_mongodb() {
  if [[ -z "$1" ]]; then
    log_error "Please make sure to pass invoker username argument to restart_mongodb() function."
    exit 1
  fi

  if [[ -z "$2" ]]; then
    log_error "Please make sure to pass current ip address argument to restart_mongodb() function."
    exit 1
  fi

  local invoker_username=$1
  local current_ip=$2

  log_info "Restarting MongoDB cluster..."

  local mongodb_status=""
  get_mongodb_status mongodb_status

  if [[ "$mongodb_status" == "not_found" ]] || [[ "$mongodb_status" == "no_crd" ]]; then
    log_warn "MongoDB cluster does not exist, bootstrapping..."
    bootstrap_mongodb
  else
    # Rolling restart by triggering annotation change
    microk8s kubectl patch psmdb "$MONGODB_CR_NAME" -n"$MONGODB_NAMESPACE" --type=merge \
      -p "{\"spec\":{\"replsets\":[{\"name\":\"rs0\",\"annotations\":{\"restart-trigger\":\"$(date +%s)\"}}]}}" 2>&1 || true

    log_info "Rolling restart triggered, waiting for cluster..."
    sleep 10
    wait_for_mongodb_cluster 300
  fi

  update_mongodb_etc_hosts
  get_mongodb_credentials

  log_success "MongoDB has been restarted."
  newline
}

########################
# Runs mongodb flow
# Arguments:
#   flow action
#   invoker username
# Returns:
#   none
#########################
run_mongodb_flow() {
  if [[ -z "$1" ]]; then
    log_error "Please make sure to pass flow action argument to run_mongodb_flow() function."
    exit 1
  fi

  if [[ -z "$2" ]]; then
    log_error "Please make sure to pass invoker username argument to run_mongodb_flow() function."
    exit 1
  fi

  local flow_action="$1"
  local invoker_username="$2"

  local default_network_interface="unknown"
  get_default_network_interface default_network_interface

  log_success "Assuming that this is the default network interface: $default_network_interface"
  newline

  local current_ip="127.0.0.1"
  get_current_ip current_ip "$default_network_interface"

  local MICROK8S_STATUS=""
  get_microk8s_status MICROK8S_STATUS

  if [[ $MICROK8S_STATUS == *"microk8s is running"* ]]; then
    log_success "microk8s is running"
  elif [[ $MICROK8S_STATUS == *"microk8s: command not found"* ]]; then
    log_warn "$MICROK8S_STATUS"
    log_error "microk8s is not installed, mongodb flow can run only if microk8s is available, terminating script."
    exit 1
  elif [[ $MICROK8S_STATUS == *"microk8s is not running."* ]]; then
    log_warn "$MICROK8S_STATUS"
    log_error "microk8s is not running, mongodb flow can run only if microk8s is available, terminating script."
    exit 1
  else
    log_warn "$MICROK8S_STATUS"
    log_error "Unable to recover from this error, terminating script."
    exit 1
  fi

  newline

  if [[ "${flow_action}" == "refresh" ]]; then
    refresh_mongodb "$invoker_username" "$current_ip"
  elif [[ "${flow_action}" == "start" ]]; then
    start_mongodb "$invoker_username" "$current_ip"
  elif [[ "${flow_action}" == "restart" ]]; then
    restart_mongodb "$invoker_username" "$current_ip"
  elif [[ "${flow_action}" == "stop" ]]; then
    stop_mongodb
    exit 0
  elif [[ "${flow_action}" == "remove" ]]; then
    log_warn "Removing MongoDB in 10 seconds.... (Press CTRL+C to abort)"
    sleep 10
    remove_mongodb
    log_warn "MongoDB removed."
    exit 0
  else
    log_error "Unknown flow action '${flow_action}' for mongodb flow, terminating script."
    exit 1
  fi
}
