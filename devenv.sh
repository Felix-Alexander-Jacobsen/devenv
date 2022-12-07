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
# Dev Environment set-up

declare -a PLUGINS
PLUGINS=("dns" "dashboard" "storage" "registry" "metrics-server" "metallb" "helm3")
PLUGIN_PODS=("k8s-app=kube-dns" "k8s-app=kubernetes-dashboard" "k8s-app=hostpath-provisioner" "app=registry" "k8s-app=metrics-server" "app=metallb" "none")
PLUGIN_NAMESPACES=("kube-system" "kube-system" "kube-system" "container-registry" "kube-system" "metallb-system" "none")

SLOW_MOTION_TEXT=${SLOW_MOTION_TEXT:-true}
MICROK8S_VERSION=${MICROK8S_VERSION:-"1.23"}
MONGODB_VERSION=${MONGODB_VERSION:-"6.0.3"}
LOADBALANCER_NUM_OF_IP_ADDRESSES=${LOADBALANCER_NUM_OF_IP_ADDRESSES:-16}
KONG_ENABLED=${KONG_ENABLED:-true}
DASHBOARD_DOMAIN=${DASHBOARD_DOMAIN:-k8s.devenv.dev}
DASHBOARD_CERTIFICATE=${DASHBOARD_CERTIFICATE:-devenv.dev}

RUN_FLOW="microk8s"
FLOW_ACTION="refresh"

if [ "$1" ]; then
  RUN_FLOW="$1"
fi

if [ "$2" ]; then
  FLOW_ACTION="$2"
fi

# Load required libraries
. ./devenv/liblog.sh # log_success, log_info, newline
. ./devenv/libversion.sh
. ./devenv/libdevenv.sh
. ./devenv/libnetwork.sh  # get_default_network_interface, get_current_ip, calculate_next_ip, calculate_new_ip_with_offset
. ./devenv/libuser.sh     # get_invoker_username
. ./devenv/libwelcome.sh  # print_welcome
. ./devenv/libmicrok8s.sh # refresh_microk8s
. ./devenv/libkong.sh     # refresh_kong_api_gateway
. ./devenv/libk8s.sh      # interaction with Kubernetes
. ./devenv/libhelm.sh     # interaction with Helm
. ./devenv/libcurl.sh     # wrapper around cURL binary
. ./devenv/libgit.sh      # wrapper around git binary
. ./devenv/libos.sh       # update_etc_hosts
. ./devenv/libflows.sh    # run_flow
. ./devenv/libkafka.sh    # run_kafka_flow
. ./devenv/libmongodb.sh  # run_mongodb_flow

print_welcome

INVOKER_USERNAME=$USER
get_invoker_username INVOKER_USERNAME

run_flow "${RUN_FLOW}" "${FLOW_ACTION}" "${INVOKER_USERNAME}"

log_success "Done"
