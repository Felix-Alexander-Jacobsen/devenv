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
    create_helm_deployment "kong" "api-gateway" "kong/kong" "--set ingressController.installCRDs=false --set admin.enabled=true --set admin.http.enabled=true --set admin.type='ClusterIP'"
  fi

  kubectl_wait_for_pod "kong" "app.kubernetes.io/name=kong" 300
  local gateway_ip_address=""
  check_kong_api_gateway_availability gateway_ip_address

  newline

  eval "$1='$gateway_ip_address'"
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
