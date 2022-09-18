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
# Library for interacting with Kubernetes

# Load required libraries
#. ./liblog.sh # log_info, log_error, log_success, log_warn
#. ./libos.h # update_etc_hosts

########################
# Finds IP assigned by LoadBalancer to a given service
# Arguments:
#   ip address placeholder
#   namespace name
#   service name
# Returns:
#   ip address
#########################
find_ip_assigned_by_loadbalancer_to_svc() {
  if [[ -z "$1" ]]; then
    log_error "Please make sure to pass ip address placeholder argument to find_ip_assigned_by_loadbalancer_to_svc() function."
    exit 1
  fi

  if [[ -z "$2" ]]; then
    log_error "Please make sure to pass namespace name argument to find_ip_assigned_by_loadbalancer_to_svc() function."
    exit 1
  fi

  if [[ -z "$3" ]]; then
    log_error "Please make sure to pass service name argument to find_ip_assigned_by_loadbalancer_to_svc() function."
    exit 1
  fi

  local namespace_name=$2
  local service_name=$3

  log_info "Searching for '${service_name}' service's IP address assigned by loadbalancer in namespace '${namespace_name}'..."

  local ip_address_check=""
  ip_address_check=$(2>&1 microk8s kubectl get svc "${service_name}" -n"${namespace_name}" | grep LoadBalancer | awk '{print $4}')

  if [[ "$?" -ne 0 ]]; then
    log_error "$ip_address_check"
    log_error "Unable to find IP address, terminating script."
    exit 1
  else
    log_success "Found IP address of service '${service_name}' in namespace '${namespace_name}': $ip_address_check."
    eval "$1='$ip_address_check'"
  fi
}

########################
# Finds the highest IP assigned by LoadBalancer
# Arguments:
#   ip address placeholder
#   current ip address
# Returns:
#   ip address
#########################
find_the_highest_ip_assigned_by_loadbalancer() {
  if [[ -z "$1" ]]; then
    log_error "Please make sure to pass ip address placeholder argument to find_the_highest_ip_assigned_by_loadbalancer() function."
    exit 1
  fi

  if [[ -z "$2" ]]; then
    log_error "Please make sure to pass curent ip address argument to find_the_highest_ip_assigned_by_loadbalancer() function."
    exit 1
  fi

  log_info "Searching for highest IP address assigned by loadbalancer..."

  local current_ip_address=$2

  local highest_ip_address_check=""
  highest_ip_address_check=$(2>&1 microk8s kubectl get svc -A | grep LoadBalancer | awk '{print $5}')

  if [[ "$?" -ne 0 ]]; then
    log_error "$highest_ip_address_check"
    log_error "Unable to find IP address, terminating script."
    exit 1
  else
    local ip_addresses_array=""
    readarray -t ip_addresses_array <<<"$highest_ip_address_check"

    local highest_int_ip=0
    local highest_ip=$current_ip_address

    local i=0
    for i in "${!ip_addresses_array[@]}"; do
      if [[ ${ip_addresses_array[$i]} == "<pending>" ]]; then
        log_error "Unable to translate ip address, it seems that loadbalancer is stuck with assignments in <pending> state, please run 'microk8s refresh'. Terminating script..."
        exit 1
      fi

      local int_ip=""
      inet_aton int_ip "${ip_addresses_array[$i]}"
      if [[ $int_ip -ge $highest_int_ip ]]; then
        highest_int_ip=$int_ip
        highest_ip=${ip_addresses_array[$i]}
      fi
    done

    log_success "Found the highest IP address assigned by loadbalancer: $highest_ip"

    eval "$1='$highest_ip'"
  fi
}

########################
# Verifies whether a given namespace exists
# Arguments:
#   result placeholder
#   namespace name
# Returns:
#   result (true or false)
#########################
does_namespace_exist() {
  if [[ -z "$1" ]]; then
    log_error "Please make sure to pass result placeholder argument to does_namespace_exist() function."
    exit 1
  fi

  if [[ -z "$2" ]]; then
    log_error "Please make sure to pass namespace name argument to does_namespace_exist() function."
    exit 1
  fi

  local namespace_name=$2

  log_info "Checking if '${namespace_name}' namespace exists..."

  local namespace_check=""
  namespace_check=$(2>&1 microk8s kubectl get namespace "${namespace_name}")

  if [[ "$?" -ne 0 ]]; then
    if [[ $namespace_check == *"NotFound"* ]]; then
      log_warn "$namespace_check"
      eval "$1='false'"
    else
      log_error "$namespace_check"
      log_error "Unable to interact with the microk8s cluster, terminating script."
      exit 1
    fi
  else
    log_success "$namespace_check"
    eval "$1='true'"
  fi
}

########################
# Verifies whether a given namespace exists
# Arguments:
#   result placeholder
#   namespace name
#   secret name
# Returns:
#   result (true or false)
#########################
does_secret_exist() {
  if [[ -z "$1" ]]; then
    log_error "Please make sure to pass result placeholder argument to does_secret_exist() function."
    exit 1
  fi

  if [[ -z "$2" ]]; then
    log_error "Please make sure to pass namespace name argument to does_secret_exist() function."
    exit 1
  fi

  if [[ -z "$2" ]]; then
    log_error "Please make sure to pass secret name argument to does_secret_exist() function."
    exit 1
  fi

  local namespace_name=$2
  local secret_name=$3

  log_info "Checking if '${secret_name}' secret exists in namespace '${namespace_name}'..."

  local secret_check=""
  secret_check=$(2>&1 microk8s kubectl get secret "${secret_name}" -n"${namespace_name}")

  if [[ "$?" -ne 0 ]]; then
    if [[ $secret_check == *"NotFound"* ]]; then
      log_warn "$secret_check"
      eval "$1='false'"
    else
      log_error "$secret_check"
      log_error "Unable to interact with the microk8s cluster, terminating script."
      exit 1
    fi
  else
    log_success "$secret_check"
    eval "$1='true'"
  fi
}

########################
# Verifies whether a given ingress object exists
# Arguments:
#   result placeholder
#   namespace name
#   ingress name
# Returns:
#   result (true or false)
#########################
does_ingress_exist() {
  if [[ -z "$1" ]]; then
    log_error "Please make sure to pass result placeholder argument to does_ingress_exist() function."
    exit 1
  fi

  if [[ -z "$2" ]]; then
    log_error "Please make sure to pass namespace name argument to does_ingress_exist() function."
    exit 1
  fi

  if [[ -z "$2" ]]; then
    log_error "Please make sure to pass ingress object name argument to does_ingress_exist() function."
    exit 1
  fi

  local namespace_name=$2
  local ingress_name=$3

  log_info "Checking if '${ingress_name}' ingress object exists in namespace '${namespace_name}'..."

  local ingress_object_check=""
  ingress_object_check=$(2>&1 microk8s kubectl get ingress "${ingress_name}" -n"${namespace_name}")

  if [[ "$?" -ne 0 ]]; then
    if [[ $ingress_object_check == *"NotFound"* ]]; then
      log_warn "$ingress_object_check"
      eval "$1='false'"
    else
      log_error "$ingress_object_check"
      log_error "Unable to interact with the microk8s cluster, terminating script."
      exit 1
    fi
  else
    log_success "$ingress_object_check"
    eval "$1='true'"
  fi
}

########################
# Verifies whether a given statefulset object exists
# Arguments:
#   result placeholder
#   namespace name
#   statefulset name
# Returns:
#   result (true or false)
#########################
does_statefulset_exist() {
  if [[ -z "$1" ]]; then
    log_error "Please make sure to pass result placeholder argument to does_statefulset_exist() function."
    exit 1
  fi

  if [[ -z "$2" ]]; then
    log_error "Please make sure to pass namespace name argument to does_statefulset_exist() function."
    exit 1
  fi

  if [[ -z "$2" ]]; then
    log_error "Please make sure to pass statefulset object name argument to does_statefulset_exist() function."
    exit 1
  fi

  local namespace_name=$2
  local statefulset_name=$3

  log_info "Checking if '${statefulset_name}' statefulset object exists in namespace '${namespace_name}'..."

  local statefulset_check=""
  statefulset_check=$(2>&1 microk8s kubectl get statefulset "${statefulset_name}" -n"${namespace_name}")

  if [[ "$?" -ne 0 ]]; then
    if [[ $statefulset_check == *"NotFound"* ]]; then
      log_warn "$statefulset_check"
      eval "$1='false'"
    else
      log_error "$statefulset_check"
      log_error "Unable to interact with the microk8s cluster, terminating script."
      exit 1
    fi
  else
    log_success "$statefulset_check"
    eval "$1='true'"
  fi
}

########################
# Creates a new namespace
# Arguments:
#   namespace name
# Returns:
#   none
#########################
create_namespace() {
  if [[ -z "$1" ]]; then
    log_error "Please make sure to pass namespace name argument to create_namespace() function."
    exit 1
  fi

  local namespace_name=$1

  log_info "Creating namespace '${namespace_name}'..."

  local namespace_create=""
  namespace_create=$(2>&1 microk8s kubectl create namespace "${namespace_name}")

  if [[ "$?" -ne 0 ]]; then
    if [[ $namespace_create == *"AlreadyExists"* ]]; then
      log_error "$namespace_create"
      log_error "Unable to create namespace, terminating script."
    else
      log_error "$namespace_create"
      log_error "Unable to interact with the microk8s cluster, terminating script."
      exit 1
    fi
  else
    log_success "$namespace_create"
  fi
}

########################
# Creates a new tls ingress object with https backend in a given namespace
# Arguments:
#   namespace name
#   ingress name
#   tls secret name
#   service name
# Returns:
#   none
#########################
create_tls_ingress_https_backend() {
  if [[ -z "$1" ]]; then
    log_error "Please make sure to pass namespace name argument to create_tls_ingress_https_backend() function."
    exit 1
  fi

  if [[ -z "$2" ]]; then
    log_error "Please make sure to pass secret name argument to create_tls_ingress_https_backend() function."
    exit 1
  fi

  if [[ -z "$3" ]]; then
    log_error "Please make sure to pass tls secret name argument to create_tls_ingress_https_backend() function."
    exit 1
  fi

  if [[ -z "$4" ]]; then
    log_error "Please make sure to pass service name argument to create_tls_ingress_https_backend() function."
    exit 1
  fi

  local namespace_name=$1
  local ingress_name=$2
  local tls_secret_name=$3
  local service_name=$4

  log_info "Creating tls '${ingress_name}' ingress object in namespace '${namespace_name}'..."

  local tls_ingress_create=""
  if [[ $KONG_ENABLED == "true" ]]; then
    tls_ingress_create=$(2>&1 cat <<EOF | microk8s kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    kubernetes.io/ingress.class: kong
    konghq.com/protocol: "https"
    konghq.com/protocols: "https"
  name: ${ingress_name}
  namespace: ${namespace_name}
spec:
  tls:
    - hosts:
        - ${DASHBOARD_DOMAIN}
      secretName: ${tls_secret_name}
  rules:
  - host: ${DASHBOARD_DOMAIN}
    http:
      paths:
      - path: "/"
        pathType: Prefix
        backend:
          service:
            name: ${service_name}
            port:
             number: 443
---
apiVersion: configuration.konghq.com/v1
kind: KongIngress
metadata:
  name: ${service_name}
  namespace: ${namespace_name}
proxy:
  protocol: https
route:
  https_redirect_status_code: 301
  protocols:
  - https
EOF
  )
  else
    tls_ingress_create=$(2>&1 cat <<EOF | microk8s kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    kubernetes.io/ingress.class: nginx
    nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
  name: ${ingress_name}
  namespace: ${namespace_name}
spec:
  tls:
    - hosts:
        - ${DASHBOARD_DOMAIN}
      secretName: ${tls_secret_name}
  rules:
  - host: ${DASHBOARD_DOMAIN}
    http:
      paths:
      - path: "/"
        pathType: Prefix
        backend:
          service:
            name: ${service_name}
            port:
             number: 443
EOF
  )
  fi

  if [[ "$?" -ne 0 ]]; then
    if [[ $tls_ingress_create == *"AlreadyExists"* ]]; then
      log_error "$tls_ingress_create"
      log_error "Unable to create tls ingress object, terminating script."
    else
      log_error "$tls_ingress_create"
      log_error "Unable to interact with the cluster, terminating script."
      exit 1
    fi
  else
    log_success "$tls_ingress_create"
  fi
}

########################
# Creates a new secret in a given namespace
# Arguments:
#   namespace name
#   secret name
#   secret type
#   secret options
# Returns:
#   none
#########################
create_secret() {
  if [[ -z "$1" ]]; then
    log_error "Please make sure to pass namespace name argument to create_secret() function."
    exit 1
  fi

  if [[ -z "$2" ]]; then
    log_error "Please make sure to pass secret name argument to create_secret() function."
    exit 1
  fi

  if [[ -z "$3" ]]; then
    log_error "Please make sure to pass secret type argument to create_secret() function."
    exit 1
  fi

  if [[ -z "$4" ]]; then
    log_error "Please make sure to pass secret options argument to create_secret() function."
    exit 1
  fi

  local namespace_name=$1
  local secret_name=$2
  local secret_type=$3
  local secret_options=$4

  log_info "Creating '${secret_type}' secret '${secret_name}' in namespace '${namespace_name}'..."

  local secret_create=""
  secret_create=$(2>&1 microk8s kubectl create secret "${secret_type}" "${secret_name}" ${secret_options} --namespace "${namespace_name}")

  if [[ "$?" -ne 0 ]]; then
    if [[ $secret_create == *"AlreadyExists"* ]]; then
      log_error "$secret_create"
      log_error "Unable to create secret, terminating script."
    else
      log_error "$secret_create"
      log_error "Make sure that secret options point to existing files and directories: ${secret_options}, terminating script."
      exit 1
    fi
  else
    log_success "$secret_create"
  fi
}

########################
# Waits for pod to be ready until given timeout passes
# Arguments:
#   namespace name
#   pod name
#   timeout in seconds
# Returns:
#   none
#########################
kubectl_wait_for_pod() {
  if [[ -z "$1" ]]; then
    log_error "Please make sure to pass namespace name argument to kubectl_wait_for_pod() function."
    exit 1
  fi

  if [[ -z "$2" ]]; then
    log_error "Please make sure to pass pod name argument to kubectl_wait_for_pod() function."
    exit 1
  fi

  if [[ -z "$3" ]]; then
    log_error "Please make sure to pass timeout in seconds argument to kubectl_wait_for_pod() function."
    exit 1
  fi

  local namespace_name=$1
  local pod_name=$2
  local timeout_in_seconds=$3

  log_info "Waiting for '${pod_name}' pod in '${namespace_name}' namespace to be ready (max ${timeout_in_seconds}s)..."

  local kubectl_wait=""
  kubectl_wait=$(2>&1 microk8s kubectl wait --timeout=${timeout_in_seconds}s --for=condition=ready pod -l ${pod_name} -n${namespace_name})

  if [[ "$?" -ne 0 ]]; then
    log_error "$kubectl_wait"
    log_error "Timed out while waiting for '${pod_name}' pod to start, terminating script."
    exit 1
  else
    echo "$kubectl_wait"
    log_success "'${pod_name}' pod in ${namespace_name} namespace is now ready."
  fi
}

########################
# Sets-up Kubernetes dashboard
# Arguments:
#   ingress ip
# Returns:
#   none
#########################
setup_k8s_dashboard() {
  if [[ -z "$1" ]]; then
    log_error "Please make sure to pass ingress ip argument to setup_k8s_dashboard() function."
    exit 1
  fi

  local ingress_ip="$1"

  log_info "Setting up Kubernetes dashboard..."

  local secret_exists=""
  does_secret_exist secret_exists "kube-system" "ingress-tls-secrets"

  if [[ $secret_exists == *"false"* ]]; then
    create_secret "kube-system" "ingress-tls-secrets" "tls" "--key=./certificates/${DASHBOARD_CERTIFICATE}-domain.key --cert=./certificates/${DASHBOARD_CERTIFICATE}-domain.crt"
  fi

  local ingress_exists=""
  does_ingress_exist ingress_exists "kube-system" "dashboard"

  if [[ $ingress_exists == *"false"* ]]; then
    create_tls_ingress_https_backend "kube-system" "dashboard" "ingress-tls-secrets" "kubernetes-dashboard"
  fi

  if [[ $KONG_ENABLED == "true" ]]; then
    local annotations_patch=""
    IFS='' read -r -d '' annotations_patch <<"EOF"
metadata:
  annotations:
    configuration.konghq.com: kubernetes-dashboard
    konghq.com/protocol: https
EOF

    local kong_https_patch=""
    kong_https_patch=$(2>&1 microk8s kubectl patch svc kubernetes-dashboard --patch "$(echo -e "${annotations_patch}")" --namespace kube-system)

    if [[ "$?" -ne 0 ]]; then
      log_error "$kong_https_patch"
      log_error "Unable to patch k8s dashboard svc, terminating script."
      exit 1
    else
      if [[ $kong_https_patch == *"no change"* ]]; then
        # do nothing
        kong_https_patch=""
      else
        log_success "$kong_https_patch"
        log_info "Waiting 10 seconds for the kong settings to kick in..."
        sleep 10
      fi
    fi
  fi

  update_etc_hosts "${DASHBOARD_DOMAIN}" "${ingress_ip}"
  check_k8s_dashboard_availability

  newline
}

########################
# Checks Kubernetes dashboard's availability
# Arguments:
#   none
# Returns:
#   none
#########################
check_k8s_dashboard_availability() {
  log_info "Checking if Kubernetes dashboard is reachable under https://${DASHBOARD_DOMAIN}..."

  local dashboard_call=""
  simple_curl_call dashboard_call "https://${DASHBOARD_DOMAIN}"

  if [[ "$dashboard_call" == *"<title>Kubernetes Dashboard</title>"* ]]; then
    log_success "Kubernetes Dashboard is reachable."
  else
    log_error "$dashboard_call"
    log_error "Unable to reach Kubernetes Dashboard, terminating script."
    exit 1
  fi
}
