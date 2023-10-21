#!/bin/bash
# The MIT License (MIT)
#
# Copyright (c) 2022-2023 Felix Jacobsen
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
# Library for interactions with kafka

# Load required libraries
#. ./liblog.sh # logInfo

########################
# Gets kafka status
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
  kafka_query=$(2>&1 microk8s kubectl get pod -nkafka)

  if [[ $kafka_query == *"Insufficient permissions to access MicroK8s"* ]]; then
    log_warn "$kafka_query"
    log_error "Please run this script as root or with sudo."
    exit 1
  fi

  eval "$1='$kafka_query'"
}

########################
# Installs kafka
# Arguments:
#   highest ip assigned by loadbalancer
# Returns:
#   none
#########################
install_kafka() {
  if [[ -z "$1" ]]; then
    log_error "Please make sure to pass the highest ip assigned by loadbalancer argument to install_kafka() function."
    exit 1
  fi

  local last_ip_assigned_by_lb=$1

  local kafka_first_ip=""
  calculate_next_ip kafka_first_ip "$last_ip_assigned_by_lb"

  local kafka_second_ip=""
  calculate_next_ip kafka_second_ip "$kafka_first_ip"

  local kafka_third_ip=""
  calculate_next_ip kafka_third_ip "$kafka_second_ip"

  log_warn "kafka is not installed, installing it now with the following IP addresses assigned to brokers: $kafka_first_ip, $kafka_second_ip, $kafka_third_ip..."

  local namespace_exists=""
  does_namespace_exist namespace_exists "kafka"

  if [[ $namespace_exists == *"false"* ]]; then
    create_namespace "kafka"
  fi

  refresh_helm_repository "bitnami" "https://charts.bitnami.com/bitnami"
  create_helm_deployment "kafka" "kafka" "bitnami/kafka" "--set replicaCount=3 --set externalAccess.enabled=true --set externalAccess.controller.service.port=9092 --set externalAccess.controller.service.loadBalancerIPs[0]=$kafka_first_ip --set externalAccess.controller.service.loadBalancerIPs[1]=$kafka_second_ip --set externalAccess.controller.service.loadBalancerIPs[2]=$kafka_third_ip --version $KAFKA_VERSION"

  if [[ "$?" -ne 0 ]]; then
    log_error "Installation failed, terminating script."
    exit 1
  fi
}

########################
# Waits for kafka pods to be ready
# Arguments:
#   timeout in seconds
# Returns:
#   none
#########################
wait_for_kafka_pods() {
  if [[ -z "$1" ]]; then
    log_error "Please make sure to pass timeout in seconds argument to wait_for_kafka_pods() function."
    exit 1
  fi

  local timeout=$1

  #kubectl_wait_for_pod "kafka" "statefulset.kubernetes.io/pod-name=kafka-zookeeper-0" "$timeout"
  kubectl_wait_for_pod "kafka" "statefulset.kubernetes.io/pod-name=kafka-controller-0" "$timeout"
  kubectl_wait_for_pod "kafka" "statefulset.kubernetes.io/pod-name=kafka-controller-1" "$timeout"
  kubectl_wait_for_pod "kafka" "statefulset.kubernetes.io/pod-name=kafka-controller-2" "$timeout"
}

########################
# Applies kafka loadbalancer patch effectively assigning a new IP to a given kafka external service
# Arguments:
#   kafka service name
# Returns:
#   none
#########################
apply_kafka_lb_patch() {
  if [[ -z "$1" ]]; then
    log_error "Please make sure to pass kafka service name argument to apply_kafka_lb_patch() function."
    exit 1
  fi

  local kafka_svc_name="$1"

  log_info "Refreshing '$kafka_svc_name' service, asking loadbalancer to assign new IP..."

  local null_lb_patch=""
  IFS='' read -r -d '' null_lb_patch <<"EOF"
spec:
  loadBalancerIP: null
EOF

  local kafka_lb_patch=""
  kafka_lb_patch=$(2>&1 microk8s kubectl patch svc "$kafka_svc_name" --patch "$(echo -e "${null_lb_patch}")" --namespace kafka)

  if [[ "$?" -ne 0 ]]; then
    log_error "$kafka_lb_patch"
    log_error "Unable to patch '$kafka_svc_name' svc, terminating script."
    exit 1
  else
    if [[ $kafka_lb_patch == *"no change"* ]]; then
      # do nothing
      kafka_lb_patch=""
    else
      log_success "$kafka_lb_patch"
      log_info "Waiting 10 seconds for new loadbalancer to assign new IP..."
      sleep 10
    fi
  fi
}

########################
# Verifies if kafka external service has correct IP address assigned by the loadbalancer
# Arguments:
#   result placeholder
#   loadbalancer ip range begin
#   loadbalancer ip range end
#   kafka external service name
# Returns:
#   result (true or false)
#########################
verify_if_kafka_lb_svc_has_correct_ip() {
  if [[ -z "$1" ]]; then
    log_error "Please make sure to pass result placeholder argument to verify_if_kafka_lb_svc_has_correct_ip() function."
    exit 1
  fi

  if [[ -z "$2" ]]; then
    log_error "Please make sure to pass loadbalancer ip range begin argument to verify_if_kafka_lb_svc_has_correct_ip() function."
    exit 1
  fi

  if [[ -z "$3" ]]; then
    log_error "Please make sure to pass loadbalancer ip range end argument to verify_if_kafka_lb_svc_has_correct_ip() function."
    exit 1
  fi

  if [[ -z "$4" ]]; then
    log_error "Please make sure to pass kafka external service name argument to verify_if_kafka_lb_svc_has_correct_ip() function."
    exit 1
  fi

  local loadbalancer_ip_range_begin="$2"
  local loadbalancer_ip_range_end="$3"
  local kafka_external_service_name="$4"

  log_info "Verifying whether '$kafka_external_service_name' svc has correct ip address assigned..."

  local loadbalancer_ip_range_begin_int=""
  inet_aton loadbalancer_ip_range_begin_int "$loadbalancer_ip_range_begin"

  local loadbalancer_ip_range_end_int=""
  inet_aton loadbalancer_ip_range_end_int "$loadbalancer_ip_range_end"

  local kafka_ip_verification=""
  kafka_ip_verification=$(2>&1 microk8s kubectl get svc "$kafka_external_service_name" -nkafka | grep LoadBalancer | awk '{print $4}')

  if [[ "$?" -ne 0 ]]; then
    log_error "$kafka_ip_verification"
    log_error "Unable to verify the correctness of ip address assigned to '$kafka_external_service_name' svc, terminating script."
    exit 1
  else
    if [[ $kafka_ip_verification == *"<pending>"* ]]; then
      log_warn "'$kafka_external_service_name' svc does not have correct ip address assigned (i.e. <pending>)."
      eval "$1='false'"
    else
      local found_ip_int=""
      inet_aton found_ip_int "$kafka_ip_verification"

      if [[ $found_ip_int -lt $loadbalancer_ip_range_begin_int ]]; then
        log_warn "'$kafka_external_service_name' svc does not have correct ip address assigned (i.e. $kafka_ip_verification < $loadbalancer_ip_range_begin)."
        eval "$1='false'"
      elif [[ $found_ip_int -gt $loadbalancer_ip_range_end_int ]]; then
        log_warn "'$kafka_external_service_name' svc does not have correct ip address assigned (i.e. $kafka_ip_verification > $loadbalancer_ip_range_end)."
        eval "$1='false'"
      else
        log_success "'$kafka_external_service_name' svc's ip address is assigned correctly (i.e. $loadbalancer_ip_range_begin <= $kafka_ip_verification <= $loadbalancer_ip_range_end)."
        eval "$1='true'"
      fi
    fi
  fi
}

########################
# Refreshes kafka loadbalancer services
# Arguments:
#   current ip address
# Returns:
#   none
#########################
refresh_kafka_lb_svc() {
  if [[ -z "$1" ]]; then
    log_error "Please make sure to pass current ip address argument to refresh_kafka_lb_svc() function."
    exit 1
  fi

  local current_ip="$1"

  log_info "Calculating IP range for $LOADBALANCER_NUM_OF_IP_ADDRESSES addresses higher than current $current_ip..."

  local loadbalancer_ip_range_begin=""
  calculate_next_ip loadbalancer_ip_range_begin "$current_ip"

  local loadbalancer_ip_range_end=""
  calculate_new_ip_with_offset loadbalancer_ip_range_end "$loadbalancer_ip_range_begin" "$LOADBALANCER_NUM_OF_IP_ADDRESSES"

  log_success "Assuming that loadbalancer uses the following IP range: $loadbalancer_ip_range_begin-$loadbalancer_ip_range_end."

  local does_kafka_external_svc_has_correct_ip=""
  verify_if_kafka_lb_svc_has_correct_ip does_kafka_external_svc_has_correct_ip "$loadbalancer_ip_range_begin" "$loadbalancer_ip_range_end" "kafka-controller-0-external"

  if [[ $does_kafka_external_svc_has_correct_ip == "false" ]]; then
    apply_kafka_lb_patch "kafka-controller-0-external"
    verify_if_kafka_lb_svc_has_correct_ip does_kafka_external_svc_has_correct_ip "$loadbalancer_ip_range_begin" "$loadbalancer_ip_range_end" "kafka-controller-0-external"
    if [[ $does_kafka_external_svc_has_correct_ip == "false" ]]; then
      log_error "Unable to reassign ip address to kafka svc - loadbalancer uses outdated configuration, please run 'microk8s refresh', terminating script."
      exit 1
    fi
  fi

  verify_if_kafka_lb_svc_has_correct_ip does_kafka_external_svc_has_correct_ip "$loadbalancer_ip_range_begin" "$loadbalancer_ip_range_end" "kafka-controller-1-external"

  if [[ $does_kafka_external_svc_has_correct_ip == "false" ]]; then
    apply_kafka_lb_patch "kafka-controller-1-external"
    verify_if_kafka_lb_svc_has_correct_ip does_kafka_external_svc_has_correct_ip "$loadbalancer_ip_range_begin" "$loadbalancer_ip_range_end" "kafka-controller-1-external"
    if [[ $does_kafka_external_svc_has_correct_ip == "false" ]]; then
      log_error "Unable to reassign ip address to kafka svc - loadbalancer uses outdated configuration, please run 'microk8s refresh', terminating script."
      exit 1
    fi
  fi

  verify_if_kafka_lb_svc_has_correct_ip does_kafka_external_svc_has_correct_ip "$loadbalancer_ip_range_begin" "$loadbalancer_ip_range_end" "kafka-controller-2-external"

  if [[ $does_kafka_external_svc_has_correct_ip == "false" ]]; then
    apply_kafka_lb_patch "kafka-controller-2-external"
    verify_if_kafka_lb_svc_has_correct_ip does_kafka_external_svc_has_correct_ip "$loadbalancer_ip_range_begin" "$loadbalancer_ip_range_end" "kafka-controller-2-external"
    if [[ $does_kafka_external_svc_has_correct_ip == "false" ]]; then
      log_error "Unable to reassign ip address to kafka svc - loadbalancer uses outdated configuration, please run 'microk8s refresh', terminating script."
      exit 1
    fi
  fi
}

########################
# Verifies whether both kafka statefulsets exist, with the following answers: 'one', if only one of them exist; 'two', if both are present; 'false', if none are there
# Arguments:
#   result placeholder
# Returns:
#   result (one or two or false)
#########################
verify_kafka_statefulsets_existence() {
  if [[ -z "$1" ]]; then
    log_error "Please make sure to pass result placeholder argument to verify_kafka_statefulsets_existence() function."
    exit 1
  fi

  local kafka_statefulset_exists="true"
  #does_statefulset_exist kafka_statefulset_exists "kafka" "kafka-zookeeper"

  if [[ $kafka_statefulset_exists == "true" ]]; then
    does_statefulset_exist kafka_statefulset_exists "kafka" "kafka"
    if [[ $kafka_statefulset_exists == "true" ]]; then
      eval "$1='two'"
    else
      eval "$1='one'"
    fi
  else
    does_statefulset_exist kafka_statefulset_exists "kafka" "kafka"
    if [[ $kafka_statefulset_exists == "true" ]]; then
      eval "$1='one'"
    else
      eval "$1='false'"
    fi
  fi
}

########################
# Bootstraps kafka: verifies proper loadbalancer address, installs kafka, waits until it starts and then retrieves its status
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
  local kafka_status=""

  local highest_ip_assigned_by_loadbalancer=""
  find_the_highest_ip_assigned_by_loadbalancer highest_ip_assigned_by_loadbalancer "$current_ip"
  install_kafka "$highest_ip_assigned_by_loadbalancer"
  wait_for_kafka_pods 180
  get_kafka_status kafka_status
  log_info "$kafka_status"
}

########################
# Refreshes kafka: installs kafka if needed and waits until it starts
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

  local kafka_status=""
  get_kafka_status kafka_status

  if [[ $kafka_status == *"0/1"* ]]; then
    log_warn "$kafka_status"
    wait_for_kafka_pods 180
    get_kafka_status kafka_status
    log_info "$kafka_status"
  elif [[ $kafka_status == *"No resources found in kafka namespace"* ]]; then
    log_warn "$kafka_status"

    local kafka_statefulsets_existence=""
    verify_kafka_statefulsets_existence kafka_statefulsets_existence

    if [[ $kafka_statefulsets_existence == "one" ]]; then
      log_warn "There's some leftover, broken kafka deployment - cleaning it up..."

      microk8s kubectl delete pod --selector app=kafka --grace-period=0 --force --namespace kafka
      microk8s kubectl delete namespace kafka

      bootstrap_kafka "$current_ip"
    elif [[ $kafka_statefulsets_existence == "two" ]]; then
      log_warn "Previous kafka deployment already exists, but it has been stopped - trying to resume it now..."
      scale_kafka_statefulsets_up_to_normal
    else
      bootstrap_kafka "$current_ip"
    fi
  elif [[ $kafka_status == *"1/1"* ]]; then
    log_info "$kafka_status"
  else
    log_warn "$kafka_status"
    log_error "Unable to recover from this error, terminating script."
    exit 1
  fi

  refresh_kafka_lb_svc "$current_ip"

  log_success "Kafka is running."

  newline
}

########################
# Scales kafka statefulsets down to 0 while preserving the persistent volumes
# Arguments:
#   none
# Returns:
#   none
#########################
scale_kafka_statefulsets_down_to_zero() {
  microk8s kubectl scale statefulsets kafka --replicas=0 -nkafka
  #microk8s kubectl scale statefulsets kafka-zookeeper --replicas=0 -nkafka
  log_info "Waiting for kafka statefulsets to scale down to zero..."
  microk8s kubectl wait --namespace kafka --for=delete pod/kafka-controller-0 --timeout=180s
  microk8s kubectl wait --namespace kafka --for=delete pod/kafka-controller-1 --timeout=180s
  microk8s kubectl wait --namespace kafka --for=delete pod/kafka-controller-3 --timeout=180s
  #microk8s kubectl wait --namespace kafka --for=delete pod/kafka-zookeeper-0 --timeout=180s
}

########################
# Scales kafka statefulsets up to normal
# Arguments:
#   none
# Returns:
#   none
#########################
scale_kafka_statefulsets_up_to_normal() {
  #microk8s kubectl scale statefulsets kafka-zookeeper --replicas=1 -nkafka
  microk8s kubectl scale statefulsets kafka --replicas=3 -nkafka
  wait_for_kafka_pods 180
}

########################
# Starts kafka: if it's already installed and scaled down, it will scale statefulsets up; if it's not installed, it will install it; if it's installed and running, it won't do anything
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

  local kafka_status=""
  get_kafka_status kafka_status

  log_info "Starting kafka..."

  if [[ $kafka_status == *"0/1"* ]]; then
    wait_for_kafka_pods 180
  elif [[ $kafka_status == *"No resources found in kafka namespace"* ]]; then
    log_warn "$kafka_status"

    local kafka_statefulsets_existence=""
    verify_kafka_statefulsets_existence kafka_statefulsets_existence

    if [[ $kafka_statefulsets_existence == "one" ]]; then
      log_warn "Kafka statefulsets are broken, they can't be safely restored. Backup your PVs and then run 'kafka refresh' to fix the situation."
      exit 1
    elif [[ $kafka_statefulsets_existence == "two" ]]; then
      log_warn "Previous kafka deployment already exists, but it has been stopped - trying to resume it now..."
      scale_kafka_statefulsets_up_to_normal
    else
      bootstrap_kafka "$current_ip"
    fi
  elif [[ $kafka_status == *"1/1"* ]]; then
      log_error "Kafka is already running, it can't be started. Please run 'kafka stop' to stop it while preserving the persistent volumes. It can be fully removed from the cluster with 'kafka remove'."
      exit 1
  else
    log_warn "$kafka_status"
    log_error "Unable to recover from this error, terminating script."
    exit 1
  fi

  log_success "Kafka has been started."

  newline
}

########################
# Restarts kafka: if it's already installed and scaled down, it will scale statefulsets up; if it's not installed, it will install it; if it's installed and running, it will scale it down to zero and then scale it back to normal again
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

  local kafka_status=""
  get_kafka_status kafka_status

  log_info "Restarting kafka..."

  if [[ $kafka_status == *"0/1"* ]]; then
    scale_kafka_statefulsets_down_to_zero
    log_success "Kafka is no longer running, starting it up..."
    scale_kafka_statefulsets_up_to_normal
  elif [[ $kafka_status == *"No resources found in kafka namespace"* ]]; then
    log_warn "$kafka_status"

    local kafka_statefulsets_existence=""
    verify_kafka_statefulsets_existence kafka_statefulsets_existence

    if [[ $kafka_statefulsets_existence == "one" ]]; then
      log_warn "Kafka statefulsets are broken, they can't be safely restored. Backup your PVs and then run 'kafka refresh' to fix the situation."
      exit 1
    elif [[ $kafka_statefulsets_existence == "two" ]]; then
      log_warn "Previous kafka deployment already exists, but it has been stopped - trying to resume it now..."
      scale_kafka_statefulsets_up_to_normal
    else
      bootstrap_kafka "$current_ip"
    fi
  elif [[ $kafka_status == *"1/1"* ]]; then
    scale_kafka_statefulsets_down_to_zero
    log_success "Kafka is no longer running, starting it up..."
    scale_kafka_statefulsets_up_to_normal
  else
    log_warn "$kafka_status"
    log_error "Unable to recover from this error, terminating script."
    exit 1
  fi

  log_success "Kafka has been re-started."

  newline
}

########################
# Stops kafka: scales statefulsets down to 0 while preserving the persistent volumes
# Arguments:
#   none
# Returns:
#   none
#########################
stop_kafka() {
  local kafka_status=""
  get_kafka_status kafka_status

  log_info "Stopping kafka..."

  if [[ $kafka_status == *"0/1"* ]]; then
    scale_kafka_statefulsets_down_to_zero
  elif [[ $kafka_status == *"No resources found in kafka namespace"* ]]; then
    log_warn "$kafka_status"

    local kafka_statefulsets_existence=""
    verify_kafka_statefulsets_existence kafka_statefulsets_existence

    if [[ $kafka_statefulsets_existence == "one" ]]; then
      log_error "Kafka statefulsets are broken, they can't be safely stopped. Backup your PVs and then run 'kafka refresh' to fix the situation."
      exit 1
    elif [[ $kafka_statefulsets_existence == "two" ]]; then
      log_error "Kafka is already not running, it can't be stopped. Please run 'kafka start' or 'kafka refresh' to bring it back. It can be fully removed from the cluster with 'kafka remove'."
      exit 1
    else
      log_error "Kafka does not exist on this cluster, it can't be safely stopped."
      exit 1
    fi
  elif [[ $kafka_status == *"1/1"* ]]; then
    scale_kafka_statefulsets_down_to_zero
  else
    log_warn "$kafka_status"
    log_error "Unable to recover from this error, terminating script."
    exit 1
  fi

  log_success "Kafka has been stopped."

  newline
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
    log_warn "Removing kafka in 10 seconds.... (Press CTRL+C to abort)"
    sleep 10
    microk8s kubectl delete pod --selector app=kafka --grace-period=0 --force --namespace kafka
    microk8s kubectl delete namespace kafka
    log_warn "Kafka removed."
    exit 0
  else
    log_error "Unknown flow action '${flow_action}' for kafka flow, terminating script."
    exit 1
  fi
}
