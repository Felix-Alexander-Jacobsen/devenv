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
# Library for interactions with Kafka using Strimzi operator

# Strimzi Helm repository
STRIMZI_HELM_REPO="https://strimzi.io/charts/"
STRIMZI_HELM_REPO_NAME="strimzi"
KAFKA_NAMESPACE="kafka"
KAFKA_CLUSTER_NAME="kafka"

########################
# Gets kafka cluster status
# Arguments:
#   kafka status placeholder
# Returns:
#   kafka status
#########################
get_kafka_status() {
  if [[ -z "$1" ]]; then
    log_error "Please make sure to pass a placeholder argument to get_kafka_status() function."
    exit 1
  fi

  local kafka_query=""
  kafka_query=$(microk8s kubectl get kafka "$KAFKA_CLUSTER_NAME" -n"$KAFKA_NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")

  if [[ $kafka_query == *"Insufficient permissions to access MicroK8s"* ]]; then
    log_warn "$kafka_query"
    log_error "Please run this script as root or with sudo."
    exit 1
  fi

  printf -v "$1" '%s' "$kafka_query"
}

########################
# Gets kafka pods status
# Arguments:
#   kafka pods status placeholder
# Returns:
#   kafka pods status
#########################
get_kafka_pods_status() {
  if [[ -z "$1" ]]; then
    log_error "Please make sure to pass a placeholder argument to get_kafka_pods_status() function."
    exit 1
  fi

  local kafka_query=""
  kafka_query=$(microk8s kubectl get pods -n"$KAFKA_NAMESPACE" -l strimzi.io/cluster="$KAFKA_CLUSTER_NAME" 2>&1)

  printf -v "$1" '%s' "$kafka_query"
}

########################
# Checks if Strimzi operator is installed
# Arguments:
#   result placeholder
# Returns:
#   true or false
#########################
is_strimzi_operator_installed() {
  if [[ -z "$1" ]]; then
    log_error "Please make sure to pass a placeholder argument to is_strimzi_operator_installed() function."
    exit 1
  fi

  local strimzi_check=""
  strimzi_check=$(microk8s kubectl get deployment strimzi-cluster-operator -n"$KAFKA_NAMESPACE" --ignore-not-found 2>/dev/null)

  if [[ -z "$strimzi_check" ]]; then
    printf -v "$1" '%s' "false"
  else
    printf -v "$1" '%s' "true"
  fi
}

########################
# Checks if Kafka cluster CR exists
# Arguments:
#   result placeholder
# Returns:
#   true or false
#########################
is_kafka_cluster_deployed() {
  if [[ -z "$1" ]]; then
    log_error "Please make sure to pass a placeholder argument to is_kafka_cluster_deployed() function."
    exit 1
  fi

  local kafka_check=""
  kafka_check=$(microk8s kubectl get kafka "$KAFKA_CLUSTER_NAME" -n"$KAFKA_NAMESPACE" --ignore-not-found 2>/dev/null)

  if [[ -z "$kafka_check" ]]; then
    printf -v "$1" '%s' "false"
  else
    printf -v "$1" '%s' "true"
  fi
}

########################
# Installs Strimzi operator via Helm
# Arguments:
#   none
# Returns:
#   none
#########################
install_strimzi_operator() {
  log_info "Installing Strimzi Kafka operator version $STRIMZI_VERSION..."

  local namespace_exists=""
  does_namespace_exist namespace_exists "$KAFKA_NAMESPACE"

  if [[ $namespace_exists == *"false"* ]]; then
    create_namespace "$KAFKA_NAMESPACE"
  fi

  # Add Strimzi Helm repository
  local repo_exists=""
  repo_exists=$(microk8s helm3 repo list 2>/dev/null | grep -c "$STRIMZI_HELM_REPO_NAME" || true)

  if [[ "$repo_exists" -eq 0 ]]; then
    log_info "Adding Strimzi Helm repository..."
    microk8s helm3 repo add "$STRIMZI_HELM_REPO_NAME" "$STRIMZI_HELM_REPO"
  fi

  microk8s helm3 repo update

  # Clean up any failed release before fresh install
  local release_status=""
  release_status=$(microk8s helm3 status strimzi-cluster-operator -n"$KAFKA_NAMESPACE" -o json 2>/dev/null | grep -o '"status":"[^"]*"' | head -1 || echo "")
  if [[ "$release_status" == *"failed"* ]] || [[ "$release_status" == *"pending"* ]]; then
    log_info "Cleaning up failed/pending Helm release..."
    microk8s helm3 uninstall strimzi-cluster-operator -n"$KAFKA_NAMESPACE" 2>/dev/null || true
    sleep 2
  fi

  # Install Strimzi operator (known issue: Helm may report role binding conflicts due to race condition)
  local install_result=""
  install_result=$(microk8s helm3 install strimzi-cluster-operator "$STRIMZI_HELM_REPO_NAME/strimzi-kafka-operator" \
    --namespace "$KAFKA_NAMESPACE" \
    --version "$STRIMZI_VERSION" \
    --set watchNamespaces="{$KAFKA_NAMESPACE}" \
    --wait 2>&1)

  local helm_exit_code=$?

  # Check if the actual deployment exists and wait for it regardless of Helm exit code
  # (Strimzi chart has a race condition with role bindings that causes spurious failures)
  if ! microk8s kubectl get deployment strimzi-cluster-operator -n"$KAFKA_NAMESPACE" &>/dev/null; then
    log_error "$install_result"
    log_error "Failed to install Strimzi operator, terminating script."
    exit 1
  fi

  log_info "Waiting for Strimzi operator deployment to be ready..."
  if ! microk8s kubectl wait --for=condition=Available deployment/strimzi-cluster-operator -n"$KAFKA_NAMESPACE" --timeout=120s 2>&1; then
    log_error "Strimzi operator deployment failed to become ready."
    exit 1
  fi

  log_success "Strimzi operator installed successfully."
}

########################
# Generates Kafka cluster CR YAML
# Arguments:
#   bootstrap IP
#   broker IP 0
#   broker IP 1
#   broker IP 2
# Returns:
#   Kafka CR YAML via stdout
#########################
generate_kafka_cr() {
  local bootstrap_ip="$1"
  local broker_ip_0="$2"
  local broker_ip_1="$3"
  local broker_ip_2="$4"

  cat <<EOF
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaNodePool
metadata:
  name: controller
  namespace: $KAFKA_NAMESPACE
  labels:
    strimzi.io/cluster: $KAFKA_CLUSTER_NAME
spec:
  replicas: 3
  roles:
    - controller
    - broker
  storage:
    type: persistent-claim
    size: 10Gi
    deleteClaim: false
---
apiVersion: kafka.strimzi.io/v1beta2
kind: Kafka
metadata:
  name: $KAFKA_CLUSTER_NAME
  namespace: $KAFKA_NAMESPACE
  annotations:
    strimzi.io/node-pools: enabled
    strimzi.io/kraft: enabled
spec:
  kafka:
    version: $KAFKA_VERSION
    metadataVersion: $KAFKA_VERSION
    listeners:
      - name: plain
        port: 9092
        type: internal
        tls: false
      - name: external
        port: 9094
        type: loadbalancer
        tls: false
        configuration:
          bootstrap:
            loadBalancerIP: $bootstrap_ip
          brokers:
            - broker: 0
              loadBalancerIP: $broker_ip_0
            - broker: 1
              loadBalancerIP: $broker_ip_1
            - broker: 2
              loadBalancerIP: $broker_ip_2
    config:
      offsets.topic.replication.factor: 3
      transaction.state.log.replication.factor: 3
      transaction.state.log.min.isr: 2
      default.replication.factor: 3
      min.insync.replicas: 2
  entityOperator:
    topicOperator: {}
    userOperator: {}
EOF
}

########################
# Deploys Kafka cluster using Strimzi CR
# Arguments:
#   highest ip assigned by loadbalancer
# Returns:
#   none
#########################
deploy_kafka_cluster() {
  if [[ -z "$1" ]]; then
    log_error "Please make sure to pass the highest ip assigned by loadbalancer argument to deploy_kafka_cluster() function."
    exit 1
  fi

  local last_ip_assigned_by_lb=$1

  # Calculate 4 IPs: bootstrap + 3 brokers
  local kafka_bootstrap_ip=""
  calculate_next_ip kafka_bootstrap_ip "$last_ip_assigned_by_lb"

  local kafka_broker_0_ip=""
  calculate_next_ip kafka_broker_0_ip "$kafka_bootstrap_ip"

  local kafka_broker_1_ip=""
  calculate_next_ip kafka_broker_1_ip "$kafka_broker_0_ip"

  local kafka_broker_2_ip=""
  calculate_next_ip kafka_broker_2_ip "$kafka_broker_1_ip"

  log_info "Deploying Kafka cluster with bootstrap IP: $kafka_bootstrap_ip, broker IPs: $kafka_broker_0_ip, $kafka_broker_1_ip, $kafka_broker_2_ip..."

  # Generate and apply Kafka CR
  local kafka_cr=""
  kafka_cr=$(generate_kafka_cr "$kafka_bootstrap_ip" "$kafka_broker_0_ip" "$kafka_broker_1_ip" "$kafka_broker_2_ip")

  echo "$kafka_cr" | microk8s kubectl apply -f -

  if [[ "$?" -ne 0 ]]; then
    log_error "Failed to deploy Kafka cluster, terminating script."
    exit 1
  fi

  log_success "Kafka cluster CR applied successfully."
}

########################
# Waits for Kafka cluster to be ready
# Arguments:
#   timeout in seconds
# Returns:
#   none
#########################
wait_for_kafka_ready() {
  if [[ -z "$1" ]]; then
    log_error "Please make sure to pass timeout in seconds argument to wait_for_kafka_ready() function."
    exit 1
  fi

  local timeout=$1
  local elapsed=0
  local interval=10

  log_info "Waiting for Kafka cluster to be ready (max ${timeout}s)..."

  while [[ $elapsed -lt $timeout ]]; do
    local kafka_status=""
    get_kafka_status kafka_status

    if [[ "$kafka_status" == "True" ]]; then
      log_success "Kafka cluster is ready."
      return 0
    fi

    local pods_status=""
    get_kafka_pods_status pods_status
    echo "$pods_status" | head -5

    sleep $interval
    elapsed=$((elapsed + interval))
    log_info "Still waiting... (${elapsed}s/${timeout}s)"
  done

  log_error "Timed out waiting for Kafka cluster to be ready."
  exit 1
}

########################
# Bootstraps kafka: installs operator if needed, deploys cluster, waits until ready
# Arguments:
#   current ip address
# Returns:
#   none
#########################
bootstrap_kafka() {
  if [[ -z "$1" ]]; then
    log_error "Please make sure to pass current ip argument to bootstrap_kafka() function."
    exit 1
  fi

  local current_ip="$1"

  # Check if Strimzi operator is installed
  local operator_installed=""
  is_strimzi_operator_installed operator_installed

  if [[ "$operator_installed" == "false" ]]; then
    install_strimzi_operator
  else
    log_info "Strimzi operator is already installed."
  fi

  # Deploy Kafka cluster
  local highest_ip_assigned_by_loadbalancer=""
  find_the_highest_ip_assigned_by_loadbalancer highest_ip_assigned_by_loadbalancer "$current_ip"

  deploy_kafka_cluster "$highest_ip_assigned_by_loadbalancer"
  wait_for_kafka_ready 300

  local pods_status=""
  get_kafka_pods_status pods_status
  log_info "$pods_status"
}

########################
# Refreshes kafka: installs if needed and waits until ready
# Arguments:
#   invoker username
#   current ip address
# Returns:
#   none
#########################
refresh_kafka() {
  if [[ -z "$1" ]]; then
    log_error "Please make sure to pass invoker username argument to refresh_kafka() function."
    exit 1
  fi

  if [[ -z "$2" ]]; then
    log_error "Please make sure to pass current ip address argument to refresh_kafka() function."
    exit 1
  fi

  local invoker_username=$1
  local current_ip=$2

  local kafka_deployed=""
  is_kafka_cluster_deployed kafka_deployed

  if [[ "$kafka_deployed" == "false" ]]; then
    log_warn "Kafka cluster is not deployed, bootstrapping it now..."
    bootstrap_kafka "$current_ip"
  else
    local kafka_status=""
    get_kafka_status kafka_status

    if [[ "$kafka_status" == "True" ]]; then
      log_info "Kafka cluster is already running."
      local pods_status=""
      get_kafka_pods_status pods_status
      log_info "$pods_status"
    else
      log_warn "Kafka cluster exists but is not ready. Waiting for it to become ready..."
      wait_for_kafka_ready 300
    fi
  fi

  log_success "Kafka is running."
  newline
}

########################
# Scales kafka cluster replicas
# Arguments:
#   replicas count
# Returns:
#   none
#########################
scale_kafka_cluster() {
  if [[ -z "$1" ]]; then
    log_error "Please make sure to pass replicas count argument to scale_kafka_cluster() function."
    exit 1
  fi

  local replicas=$1

  log_info "Scaling Kafka cluster to $replicas replicas..."

  microk8s kubectl patch kafkanodepool controller -n"$KAFKA_NAMESPACE" --type merge -p "{\"spec\":{\"replicas\":$replicas}}"

  if [[ "$?" -ne 0 ]]; then
    log_error "Failed to scale Kafka cluster."
    exit 1
  fi

  log_success "Kafka cluster scaled to $replicas replicas."
}

########################
# Starts kafka: scales up to 3 replicas if stopped
# Arguments:
#   invoker username
#   current ip address
# Returns:
#   none
#########################
start_kafka() {
  if [[ -z "$1" ]]; then
    log_error "Please make sure to pass invoker username argument to start_kafka() function."
    exit 1
  fi

  if [[ -z "$2" ]]; then
    log_error "Please make sure to pass current ip address argument to start_kafka() function."
    exit 1
  fi

  local invoker_username=$1
  local current_ip=$2

  log_info "Starting Kafka cluster..."

  local kafka_deployed=""
  is_kafka_cluster_deployed kafka_deployed

  if [[ "$kafka_deployed" == "false" ]]; then
    log_warn "Kafka cluster is not deployed, bootstrapping it now..."
    bootstrap_kafka "$current_ip"
  else
    scale_kafka_cluster 3
    wait_for_kafka_ready 300
  fi

  log_success "Kafka has been started."
  newline
}

########################
# Restarts kafka: scales down to 0 then back to 3
# Arguments:
#   invoker username
#   current ip address
# Returns:
#   none
#########################
restart_kafka() {
  if [[ -z "$1" ]]; then
    log_error "Please make sure to pass invoker username argument to restart_kafka() function."
    exit 1
  fi

  if [[ -z "$2" ]]; then
    log_error "Please make sure to pass current ip address argument to restart_kafka() function."
    exit 1
  fi

  local invoker_username=$1
  local current_ip=$2

  log_info "Restarting Kafka cluster..."

  local kafka_deployed=""
  is_kafka_cluster_deployed kafka_deployed

  if [[ "$kafka_deployed" == "false" ]]; then
    log_warn "Kafka cluster is not deployed, bootstrapping it now..."
    bootstrap_kafka "$current_ip"
  else
    # Trigger rolling restart by annotating the pods
    microk8s kubectl annotate kafkanodepool controller -n"$KAFKA_NAMESPACE" strimzi.io/manual-rolling-update=true --overwrite

    log_info "Rolling restart initiated. Waiting for cluster to stabilize..."
    sleep 10
    wait_for_kafka_ready 300
  fi

  log_success "Kafka has been restarted."
  newline
}

########################
# Stops kafka: scales down to 0 replicas (preserves PVCs)
# Arguments:
#   none
# Returns:
#   none
#########################
stop_kafka() {
  log_info "Stopping Kafka cluster..."

  local kafka_deployed=""
  is_kafka_cluster_deployed kafka_deployed

  if [[ "$kafka_deployed" == "false" ]]; then
    log_error "Kafka cluster is not deployed, nothing to stop."
    exit 1
  fi

  scale_kafka_cluster 0

  log_info "Waiting for Kafka pods to terminate..."
  microk8s kubectl wait --for=delete pod -l strimzi.io/cluster="$KAFKA_CLUSTER_NAME" -n"$KAFKA_NAMESPACE" --timeout=180s 2>/dev/null || true

  log_success "Kafka has been stopped. PVCs are preserved."
  newline
}

########################
# Removes kafka: deletes cluster CR, operator, namespace
# Arguments:
#   none
# Returns:
#   none
#########################
remove_kafka() {
  log_info "Removing Kafka cluster and Strimzi operator..."

  # Delete Kafka cluster CR
  microk8s kubectl delete kafka "$KAFKA_CLUSTER_NAME" -n"$KAFKA_NAMESPACE" --ignore-not-found --grace-period=30 2>/dev/null || true

  # Delete KafkaNodePool
  microk8s kubectl delete kafkanodepool controller -n"$KAFKA_NAMESPACE" --ignore-not-found --grace-period=30 2>/dev/null || true

  # Wait for pods to terminate
  log_info "Waiting for Kafka pods to terminate..."
  microk8s kubectl wait --for=delete pod -l strimzi.io/cluster="$KAFKA_CLUSTER_NAME" -n"$KAFKA_NAMESPACE" --timeout=180s 2>/dev/null || true

  # Uninstall Strimzi operator via Helm
  log_info "Uninstalling Strimzi Helm release..."
  microk8s helm3 uninstall strimzi-cluster-operator -n"$KAFKA_NAMESPACE" 2>/dev/null || true

  # Clean up Strimzi role bindings in namespace
  log_info "Cleaning up Strimzi role bindings..."
  microk8s kubectl delete rolebinding strimzi-cluster-operator-watched -n"$KAFKA_NAMESPACE" --ignore-not-found 2>/dev/null || true
  microk8s kubectl delete rolebinding strimzi-cluster-operator-entity-operator-delegation -n"$KAFKA_NAMESPACE" --ignore-not-found 2>/dev/null || true
  microk8s kubectl delete rolebinding strimzi-cluster-operator-leader-election -n"$KAFKA_NAMESPACE" --ignore-not-found 2>/dev/null || true
  microk8s kubectl delete rolebinding strimzi-cluster-operator -n"$KAFKA_NAMESPACE" --ignore-not-found 2>/dev/null || true

  # Clean up Strimzi cluster role bindings (cluster-wide)
  log_info "Cleaning up Strimzi cluster role bindings..."
  microk8s kubectl delete clusterrolebinding strimzi-cluster-operator --ignore-not-found 2>/dev/null || true
  microk8s kubectl delete clusterrolebinding strimzi-cluster-operator-kafka-broker-delegation --ignore-not-found 2>/dev/null || true
  microk8s kubectl delete clusterrolebinding strimzi-cluster-operator-kafka-client-delegation --ignore-not-found 2>/dev/null || true
  microk8s kubectl delete clusterrolebinding strimzi-cluster-operator-namespaced --ignore-not-found 2>/dev/null || true
  microk8s kubectl delete clusterrolebinding strimzi-cluster-operator-entity-operator-delegation --ignore-not-found 2>/dev/null || true

  # Clean up Strimzi cluster roles
  log_info "Cleaning up Strimzi cluster roles..."
  microk8s kubectl delete clusterrole strimzi-cluster-operator-global --ignore-not-found 2>/dev/null || true
  microk8s kubectl delete clusterrole strimzi-cluster-operator-namespaced --ignore-not-found 2>/dev/null || true
  microk8s kubectl delete clusterrole strimzi-entity-operator --ignore-not-found 2>/dev/null || true
  microk8s kubectl delete clusterrole strimzi-kafka-broker --ignore-not-found 2>/dev/null || true
  microk8s kubectl delete clusterrole strimzi-kafka-client --ignore-not-found 2>/dev/null || true

  # Clean up Kafka-specific CRDs (not all Strimzi CRDs in case other components use them)
  log_info "Cleaning up Kafka CRDs..."
  microk8s kubectl get crd -o name 2>/dev/null | grep -E 'kafka\.strimzi\.io|strimzipodsets\.core\.strimzi\.io' | xargs -r microk8s kubectl delete --ignore-not-found 2>/dev/null || true

  # Delete PVCs (optional - uncomment if you want to delete data)
  # microk8s kubectl delete pvc -l strimzi.io/cluster="$KAFKA_CLUSTER_NAME" -n"$KAFKA_NAMESPACE"

  # Delete namespace
  log_info "Deleting kafka namespace..."
  microk8s kubectl delete namespace "$KAFKA_NAMESPACE" --ignore-not-found --grace-period=30 2>/dev/null || true

  # Remove legacy Bitnami Helm repo if present (no longer used)
  if microk8s helm3 repo list 2>/dev/null | grep -q "bitnami"; then
    log_info "Removing legacy Bitnami Helm repository..."
    microk8s helm3 repo remove bitnami 2>/dev/null || true
  fi

  log_success "Kafka and Strimzi operator removed."
}

########################
# Runs kafka flow
# Arguments:
#   flow action
#   invoker username
# Returns:
#   none
#########################
run_kafka_flow() {
  if [[ -z "$1" ]]; then
    log_error "Please make sure to pass flow action argument to run_kafka_flow() function."
    exit 1
  fi

  if [[ -z "$2" ]]; then
    log_error "Please make sure to pass invoker username argument to run_kafka_flow() function."
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
    log_error "microk8s is not installed, kafka flow can run only if microk8s is available, terminating script."
    exit 1
  elif [[ $MICROK8S_STATUS == *"microk8s is not running."* ]]; then
    log_warn "$MICROK8S_STATUS"
    log_error "microk8s is not running, kafka flow can run only if microk8s is available, terminating script."
    exit 1
  else
    log_warn "$MICROK8S_STATUS"
    log_error "Unable to recover from this error, terminating script."
    exit 1
  fi

  newline

  if [[ "${flow_action}" == "refresh" ]]; then
    refresh_kafka "$invoker_username" "$current_ip"
  elif [[ "${flow_action}" == "start" ]]; then
    start_kafka "$invoker_username" "$current_ip"
  elif [[ "${flow_action}" == "restart" ]]; then
    restart_kafka "$invoker_username" "$current_ip"
  elif [[ "${flow_action}" == "stop" ]]; then
    stop_kafka
    exit 0
  elif [[ "${flow_action}" == "remove" ]]; then
    log_warn "Removing Kafka in 10 seconds.... (Press CTRL+C to abort)"
    sleep 10
    remove_kafka
    log_warn "Kafka removed."
    exit 0
  else
    log_error "Unknown flow action '${flow_action}' for kafka flow, terminating script."
    exit 1
  fi
}
