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
# Library for managing Kong API Gateway

# Load required libraries
#. ./liblog.sh # log_info
#. ./libk8s.sh # does_namespace_exist, create_namespace
#. ./libhelm.sh # does_helm_deployment_exist, create_helm_deployment
#. ./libcurl.sh # wrapper around cURL binary

########################
# Refreshes Kong API Gateway
# Arguments:
#   ip address placeholder
# Returns:
#   gateway ip address
#########################
refresh_kong_api_gateway() {
  if [[ -z "$1" ]]; then
    log_error "Please make sure to pass ip address placeholder argument to refresh_kong_api_gateway() function."
    exit 1
  fi

  local namespace_exists=""
  does_namespace_exist namespace_exists "kong"

  if [[ $namespace_exists == *"false"* ]]; then
    create_namespace "kong"
  fi

  local helm_deployment_exists=""
  does_helm_deployment_exist helm_deployment_exists "kong" "api-gateway"

  if [[ $helm_deployment_exists == *"false"* ]]; then
    refresh_helm_repository "kong" "https://charts.konghq.com"
    create_helm_deployment "kong" "api-gateway" "kong/kong" "--version ${KONG_VERSION} --set ingressController.installCRDs=false --set admin.enabled=true --set admin.http.enabled=true --set admin.type='ClusterIP'"
  else
    log_info "Checking status of kong pods..."
    check_and_recreate_kong_deployment_if_necessary
  fi

  wait_for_kong_pods_in_a_loop_and_recreate_deployment_if_needed "kong" "app.kubernetes.io/name=kong" 300 10
  local gateway_ip_address=""
  check_kong_api_gateway_availability gateway_ip_address

  newline

  eval "$1='$gateway_ip_address'"
}

########################
# Checks the state of Kong deployment and then if needed recreate it from scratch
# Arguments:
#   none
# Returns:
#   none
#########################
check_and_recreate_kong_deployment_if_necessary() {
    local kong_pods_status=""
    kong_pods_status=$(2>&1 microk8s kubectl get pod -nkong | grep api-gateway | awk '{print $3}')

    if [[ "$?" -ne 0 ]]; then
      log_error "$kong_pods_status"
      log_error "Unable to find kong pods, terminating script."
      exit 1
    else
      if [[ $kong_pods_status == "CrashLoopBackOff" ]]; then
        log_error "Kong pods are in CrashLoopBackOff, recreating kong deployment..."
        recreate_kong_deployment
      fi
    fi
}

########################
# Recreates Kong deployment from scratch - removes old namespace, creates a new namespace, refreshes helm repository and installs new kong deployment
# Arguments:
#   none
# Returns:
#   none
#########################
recreate_kong_deployment() {
  microk8s kubectl delete namespace kong
  create_namespace "kong"
  refresh_helm_repository "kong" "https://charts.konghq.com"
  create_helm_deployment "kong" "api-gateway" "kong/kong" "--version ${KONG_VERSION} --set ingressController.installCRDs=false --set admin.enabled=true --set admin.http.enabled=true --set admin.type='ClusterIP'"
}

########################
# Waits for Kong pods in a loop and recreates Kong deployment if it's stuck in CrashLoopBackOff
# Arguments:
#   namespace name
#   pod name
#   iteration timeout in seconds
#   loop timeout in seconds
# Returns:
#   none
#########################
wait_for_kong_pods_in_a_loop_and_recreate_deployment_if_needed() {
  if [[ -z "$1" ]]; then
    log_error "Please make sure to pass namespace name argument to wait_for_kong_pods_in_a_loop_and_recreate_deployment_if_needed() function."
    exit 1
  fi

  if [[ -z "$2" ]]; then
    log_error "Please make sure to pass pod name argument to wait_for_kong_pods_in_a_loop_and_recreate_deployment_if_needed() function."
    exit 1
  fi

  if [[ -z "$3" ]]; then
    log_error "Please make sure to pass iteration timeout in seconds argument to wait_for_kong_pods_in_a_loop_and_recreate_deployment_if_needed() function."
    exit 1
  fi

  if [[ -z "$4" ]]; then
    log_error "Please make sure to pass loop timeout in seconds argument to wait_for_kong_pods_in_a_loop_and_recreate_deployment_if_needed() function."
    exit 1
  fi

  local namespace_name=$1
  local pod_name=$2
  local loop_timeout_in_seconds=$3
  local iteration_timeout_in_seconds=$4

  if [[ $loop_timeout_in_seconds -le $iteration_timeout_in_seconds ]]; then
    log_error "Please make sure that loop timeout in seconds argument is greater than iteration timeout in seconds argument in wait_for_kong_pods_in_a_loop_and_recreate_deployment_if_needed() function."
    exit 1
  fi

  local max_iterations=$(( "$loop_timeout_in_seconds" / "$iteration_timeout_in_seconds" ))
  local current_iteration=0

  local loop_timer=0
  while [ "$loop_timer" -lt "$loop_timeout_in_seconds" ]
  do
    local kong_pods_kubectl_wait=""
    kong_pods_kubectl_wait=$(2>&1 microk8s kubectl wait --timeout=${iteration_timeout_in_seconds}s --for=condition=ready pod -l ${pod_name} -n${namespace_name})
    loop_timer=$(( "$loop_timer" + "$iteration_timeout_in_seconds" ))
    current_iteration=$(( "$current_iteration" + 1 ))

    if [[ "$kong_pods_kubectl_wait" == *"error:"* ]]; then
      microk8s kubectl get pod -nkong

      if [[ "$current_iteration" -ge "$max_iterations" ]]; then
        log_error "$kong_pods_kubectl_wait"
        log_error "Timed out iteration $current_iteration/$max_iterations while waiting for '${pod_name}' pod to start, terminating script."
        exit 1
      fi

      log_warn "$kong_pods_kubectl_wait"
      log_info "Timed out iteration $current_iteration/$max_iterations while waiting for '${pod_name}' pod to start, waiting another ${iteration_timeout_in_seconds}s..."
      check_and_recreate_kong_deployment_if_necessary
    else
      microk8s kubectl get pod -nkong
      echo "$kong_pods_kubectl_wait"
      log_success "'${pod_name}' pod in ${namespace_name} namespace is now ready."
      loop_timer=$loop_timeout_in_seconds
    fi
  done
}

########################
# Checks Kong API Gateway's availability
# Arguments:
#   ip address placeholder
# Returns:
#   kong ip gateway ip address
#########################
check_kong_api_gateway_availability() {
  if [[ -z "$1" ]]; then
    log_error "Please make sure to pass ip address placeholder argument to check_kong_api_gateway_availability() function."
    exit 1
  fi

  log_info "Checking if Kong API Gateway is reachable..."

  local kong_api_gateway_ip_address=""
  find_ip_assigned_by_loadbalancer_to_svc kong_api_gateway_ip_address "kong" "api-gateway-kong-proxy"

  local kong_api_gateway_call=""
  simple_curl_call kong_api_gateway_call "$kong_api_gateway_ip_address"

  if [[ "$kong_api_gateway_call" == *"no Route matched with those values"* ]]; then
    log_success "Kong API Gateway is reachable."
  else
    log_error "$kong_api_gateway_call"
    log_error "Unable to reach Kong API Gateway, terminating script."
    exit 1
  fi

  eval "$1='$kong_api_gateway_ip_address'"
}
