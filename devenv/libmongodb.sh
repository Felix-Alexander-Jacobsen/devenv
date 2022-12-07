#!/bin/bash
# The MIT License (MIT)
#
# Copyright (c) 2022 Felix Jacobsen
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
# Library for interactions with mongodb

# Load required libraries
#. ./liblog.sh # logInfo

########################
# Gets mongodb status
# Arguments:
#   mongodb status placeholder
# Returns:
#   mongodb status
#########################
get_mongodb_status() {
  if [[ -z "$1" ]]; then
    log_error "Please make sure to pass a placeholder argument to get_mongodb_status() function."
    exit 1
  fi

  local mongodb_query=""
  mongodb_query=$(2>&1 microk8s kubectl get mongodbcommunity.mongodbcommunity.mongodb.com -nmongodb)

  if [[ $mongodb_query == *"Insufficient permissions to access MicroK8s"* ]]; then
    log_warn "$mongodb_query"
    log_error "Please run this script as root or with sudo."
    exit 1
  fi

  eval "$1='$mongodb_query'"
}

########################
# Installs mongodb
# Arguments:
#   none
# Returns:
#   none
#########################
install_mongodb() {
  local namespace_exists=""
  does_namespace_exist namespace_exists "mongodb"

  if [[ $namespace_exists == *"false"* ]]; then
    create_namespace "mongodb"
  fi

  log_info "Installing MongoDB in mongodb namespace..."

  log_info "Checking if 'mongodb-kubernetes-operator/config/crd/bases/mongodbcommunity.mongodb.com_mongodbcommunity.yaml' file exists..."

  local mongodb_crd_exists=""
  does_file_exist mongodb_crd_exists "mongodb-kubernetes-operator/config/crd/bases/mongodbcommunity.mongodb.com_mongodbcommunity.yaml"

  if [[ $mongodb_crd_exists == *"false"* ]]; then
    log_warn "'mongodb-kubernetes-operator/config/crd/bases/mongodbcommunity.mongodb.com_mongodbcommunity.yaml' file does not exist, git repository will be cloned."
    git_clone "https://github.com/mongodb/mongodb-kubernetes-operator.git"
  else
    log_success "'mongodb-kubernetes-operator/config/crd/bases/mongodbcommunity.mongodb.com_mongodbcommunity.yaml' file exists, git repository will be updated."
    git_pull "mongodb-kubernetes-operator"
  fi

  kubectl_delete "mongodb" "MongoDBCommunity" "mongodb-ce"
  kubectl_delete "mongodb" "deployment" "mongodb-kubernetes-operator"
  kubectl_delete "mongodb" "rolebinding.rbac.authorization.k8s.io" "mongodb-kubernetes-operator"
  kubectl_delete "mongodb" "rolebinding.rbac.authorization.k8s.io" "mongodb-database"
  kubectl_delete "mongodb" "role.rbac.authorization.k8s.io" "mongodb-kubernetes-operator"
  kubectl_delete "mongodb" "role.rbac.authorization.k8s.io" "mongodb-database"
  kubectl_delete "mongodb" "serviceaccount" "mongodb-kubernetes-operator"
  kubectl_delete "mongodb" "serviceaccount" "mongodb-database"
  kubectl_delete_crd "mongodbcommunity.mongodbcommunity.mongodb.com"

  log_info "Creating MongoDB Custom Resource Definitions..."
  kubectl_apply "default" "f" "mongodb-kubernetes-operator/config/crd/bases/mongodbcommunity.mongodb.com_mongodbcommunity.yaml"
  log_success "MongoDB CRD created successfully."

  microk8s kubectl get crd/mongodbcommunity.mongodbcommunity.mongodb.com

  log_info "Creating MongoDB Operator's Roles and Role Bindings..."
  kubectl_apply "mongodb" "k" "mongodb-kubernetes-operator/config/rbac/"
  log_success "MongoDB Operator's Roles and Role Bindings created successfully."

  microk8s kubectl get serviceaccount --namespace mongodb
  microk8s kubectl get role --namespace mongodb
  microk8s kubectl get rolebinding --namespace mongodb

  log_info "Creating MongoDB Operator Deployment..."
  kubectl_apply "mongodb" "f" "mongodb-kubernetes-operator/config/manager/manager.yaml"
  log_success "MongoDB Operator Deployment created successfully."

  kubectl_wait_for_pod "mongodb" "name=mongodb-kubernetes-operator" "180"

  microk8s kubectl get deployment --namespace mongodb

  log_info "Creating MongoDB CE StatefulSet..."

  scale_mongodb_statefulsets_up_to_normal

  log_success "MongoDB CE StatefulSet created successfully."

  microk8s kubectl get MongoDBCommunity --namespace mongodb
  microk8s kubectl get pod --namespace mongodb

  log_info "Creating MongoDB LoadBalancer service..."

  local mongodb_lb_create=""
  mongodb_lb_create=$(2>&1 cat <<EOF | microk8s kubectl apply --namespace mongodb -f -
apiVersion: v1
kind: Service
metadata:
  name: mongodb-ce-lb-svc
spec:
  ports:
  - name: mongodb
    port: 27017
    protocol: TCP
    targetPort: 27017
  publishNotReadyAddresses: true
  selector:
    app: mongodb-ce-svc
  sessionAffinity: None
  type: LoadBalancer
EOF
  )

  if [[ "$?" -ne 0 ]]; then
    if [[ mongodb_lb_create == *"AlreadyExists"* ]]; then
      log_error "${mongodb_lb_create}"
      log_error "Unable to create MongoDB loadbalancer object, terminating script."
    else
      log_error "${mongodb_lb_create}"
      log_error "Unable to interact with the cluster, terminating script."
      exit 1
    fi
  else
    log_success "${mongodb_lb_create}"
  fi

  microk8s kubectl get svc -nmongodb

  log_success "MongoDB has been installed."

  newline
}

########################
# Waits for mongodb pods to be ready
# Arguments:
#   timeout in seconds
# Returns:
#   none
#########################
wait_for_mongodb_pods() {
  if [[ -z "$1" ]]; then
    log_error "Please make sure to pass timeout in seconds argument to wait_for_mongodb_pods() function."
    exit 1
  fi

  local timeout=$1

  kubectl_wait_for_pod "mongodb" "statefulset.kubernetes.io/pod-name=mongodb-ce-0" "$timeout"
  kubectl_wait_for_pod "mongodb" "statefulset.kubernetes.io/pod-name=mongodb-ce-1" "$timeout"
  kubectl_wait_for_pod "mongodb" "statefulset.kubernetes.io/pod-name=mongodb-ce-2" "$timeout"
}

########################
# Applies mongodb loadbalancer patch effectively assigning a new IP to a given mongodb external service
# Arguments:
#   mongodb service name
# Returns:
#   none
#########################
apply_mongodb_lb_patch() {
#  if [[ -z "$1" ]]; then
#    log_error "Please make sure to pass kafka service name argument to apply_kafka_lb_patch() function."
#    exit 1
#  fi

  local mongodb_svc_name="$1"

  log_info "Refreshing '$mongodb_svc_name' service, asking loadbalancer to assign new IP..."

#  local null_lb_patch=""
#  IFS='' read -r -d '' null_lb_patch <<"EOF"
#spec:
#  loadBalancerIP: null
#EOF

#  local kafka_lb_patch=""
#  kafka_lb_patch=$(2>&1 microk8s kubectl patch svc "$kafka_svc_name" --patch "$(echo -e "${null_lb_patch}")" --namespace kafka)

#  if [[ "$?" -ne 0 ]]; then
#    log_error "$kafka_lb_patch"
#    log_error "Unable to patch '$kafka_svc_name' svc, terminating script."
#    exit 1
#  else
#    if [[ $kafka_lb_patch == *"no change"* ]]; then
#      # do nothing
#      kafka_lb_patch=""
#    else
#      log_success "$kafka_lb_patch"
#      log_info "Waiting 10 seconds for new loadbalancer to assign new IP..."
#      sleep 10
#    fi
#  fi
}

########################
# Bootstraps mongodb: installs mongodb, waits until it starts and then retrieves its status
# Arguments:
#   current ip address
# Returns:
#   none
#########################
bootstrap_mongodb() {
  if [[ -z "$1" ]]; then
    log_error "Please make sure to pass current ip argument to bootstrap_mongodb() function."
    exit 1
  fi

  local current_ip="$1"
  local mongodb_status=""

  install_mongodb
  wait_for_mongodb_pods 180
  get_mongodb_status mongodb_status
  log_info "$mongodb_status"
}

########################
# Refreshes mongodb: installs mongodb if needed and waits until it starts
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

  if [[ $mongodb_status == *"Pending"* ]]; then
    log_warn "$mongodb_status"
    wait_for_mongodb_pods 180
    get_mongodb_status mongodb_status
    log_info "$mongodb_status"
  elif [[ $mongodb_status == *"No resources found in mongodb namespace"* ]] || [[ $mongodb_status == *"Failed"* ]]; then
    log_warn "$mongodb_status"
    bootstrap_mongodb "$current_ip"
  elif [[ $mongodb_status == *"Running"* ]]; then
    log_info "$mongodb_status"
  else
    log_warn "$mongodb_status"
    log_error "Unable to recover from this error, terminating script."
    exit 1
  fi

  local mongodb_ip=""
  mongodb_ip=$(microk8s kubectl get svc mongodb-ce-lb-svc -nmongodb | grep LoadBalancer | awk '{print $4}')
  update_etc_hosts "mongodb" "${mongodb_ip}"

  log_success "MongoDB is running."

  newline
}

########################
# Scales mongodb statefulsets down to 0 while preserving the persistent volumes
# Arguments:
#   none
# Returns:
#   none
#########################
scale_mongodb_statefulsets_down_to_zero() {
  microk8s kubectl delete mongodbcommunity.mongodbcommunity.mongodb.com/mongodb-ce -nmongodb
  log_info "Waiting for mongodb statefulsets to scale down to zero..."
  microk8s kubectl wait --namespace mongodb --for=delete pod/mongodb-ce-0 --timeout=180s
  microk8s kubectl wait --namespace mongodb --for=delete pod/mongodb-ce-1 --timeout=180s
  microk8s kubectl wait --namespace mongodb --for=delete pod/mongodb-ce-2 --timeout=180s
}

########################
# Scales mongodb statefulsets up to normal
# Arguments:
#   none
# Returns:
#   none
#########################
scale_mongodb_statefulsets_up_to_normal() {
  cat mongodb-kubernetes-operator/config/samples/mongodb.com_v1_mongodbcommunity_cr.yaml | sed "s/example-mongodb/mongodb-ce/g" | sed "s/  version:.*/  version: \"${MONGODB_VERSION}\"/g" | sed "s/my-user/root/g" | sed "s/my-scram/scram-secret/g" | sed "s/<your-password-here>/admin/g" | microk8s kubectl apply --namespace mongodb -f -
  wait_for_mongodb_pods 180
}

########################
# Starts mongodb: if it's already installed and scaled down, it will scale statefulsets up; if it's not installed, it will install it; if it's installed and running, it won't do anything
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

  local mongodb_status=""
  get_mongodb_status mongodb_status

  log_info "Starting MongoDB..."

  if [[ $mongodb_status == *"Pending"* ]]; then
    wait_for_mongodb_pods 180
  elif [[ $mongodb_status == *"No resources found in mongodb namespace"* ]]; then
    log_warn "$mongodb_status"
    bootstrap_mongodb "$current_ip"
  elif [[ $mongodb_status == *"Running"* ]]; then
      log_error "MongoDB is already running, it can't be started. Please run 'mongodb stop' to stop it while preserving the persistent volumes. It can be fully removed from the cluster with 'mongodb remove'."
      exit 1
  else
    log_warn "$mongodb_status"
    log_error "Unable to recover from this error, terminating script."
    exit 1
  fi

  local mongodb_ip=""
  mongodb_ip=$(microk8s kubectl get svc mongodb-ce-lb-svc -nmongodb | grep LoadBalancer | awk '{print $4}')
  update_etc_hosts "mongodb" "${mongodb_ip}"

  log_success "MongoDB has been started."

  newline
}

########################
# Restarts mongodb: if it's already installed and scaled down, it will scale statefulsets up; if it's not installed, it will install it; if it's installed and running, it will scale it down to zero and then scale it back to normal again
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

  local mongodb_status=""
  get_mongodb_status mongodb_status

  log_info "Restarting MongoDB..."

  if [[ $mongodb_status == *"Pending"* ]] || [[ $mongodb_status == *"Running"* ]]; then
    scale_mongodb_statefulsets_down_to_zero
    log_success "MongoDB is no longer running, starting it up..."
    scale_mongodb_statefulsets_up_to_normal
  elif [[ $mongodb_status == *"No resources found in mongodb namespace"* ]] || [[ $mongodb_status == *"Failed"* ]]; then
    log_warn "$mongodb_status"
    bootstrap_mongodb "$current_ip"
  else
    log_warn "$mongodb_status"
    log_error "Unable to recover from this error, terminating script."
    exit 1
  fi

  local mongodb_ip=""
  mongodb_ip=$(microk8s kubectl get svc mongodb-ce-lb-svc -nmongodb | grep LoadBalancer | awk '{print $4}')
  update_etc_hosts "mongodb" "${mongodb_ip}"

  log_success "MongoDB has been re-started."

  newline
}

########################
# Stops mongodb: scales statefulsets down to 0 while preserving the persistent volumes
# Arguments:
#   none
# Returns:
#   none
#########################
stop_mongodb() {
  local mongodb_status=""
  get_mongodb_status mongodb_status

  log_info "Stopping MongoDB..."

  if [[ $mongodb_status == *"Failed"* ]]; then
    scale_mongodb_statefulsets_down_to_zero
  elif [[ $mongodb_status == *"Pending"* ]]; then
    scale_mongodb_statefulsets_down_to_zero
  elif [[ $mongodb_status == *"No resources found in mongodb namespace"* ]]; then
    log_warn "$mongodb_status"
    log_error "MongoDB does not exist on this cluster, it can't be safely stopped."
    exit 1
  elif [[ $mongodb_status == *"Running"* ]]; then
    scale_mongodb_statefulsets_down_to_zero
  else
    log_warn "$mongodb_status"
    log_error "Unable to recover from this error, terminating script."
    exit 1
  fi

  log_success "MongoDB has been stopped."

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
    microk8s kubectl delete pod --selector app=mongodb --grace-period=0 --force --namespace mongodb
    microk8s kubectl delete namespace mongodb
    log_warn "MongoDB removed."
    exit 0
  else
    log_error "Unknown flow action '${flow_action}' for mongodb flow, terminating script."
    exit 1
  fi
}
