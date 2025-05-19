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
# Library used for interaction with microk8s

# Load required libraries
#. ./liblog.sh # log_warn, log_error

########################
# Gets microk8s status
# Arguments:
#   microk8s status placeholder
# Returns:
#   microk8s status
#########################
get_microk8s_status() {
  if [[ -z "$1" ]]; then
    log_error "Please make sure to pass a placeholder argument to get_microk8s_status() function."
    exit 1
  fi

  local microk8s_status=""
  microk8s_status=$(2>&1 microk8s status)

  if [[ $microk8s_status == *"Insufficient permissions to access MicroK8s"* ]]; then
    log_warn "$microk8s_status"
    log_error "Please run this script as root or with sudo."
    exit 1
  fi

  eval "$1='$microk8s_status'"
}

########################
# Installs microk8s
# Arguments:
#   microk8s version
# Returns:
#   none
#########################
install_microk8s() {
  if [[ -z "$1" ]]; then
    log_error "Please make sure to pass microk8s version argument to install_microk8s() function."
    exit 1
  fi

  local microk8s_version=$1

  log_warn "microk8s is not installed, installing it now..."
  snap install microk8s --classic --channel="$microk8s_version"/stable
  if [[ "$?" -ne 0 ]]; then
    log_error "Installation failed, terminating script."
    exit 1
  fi
}

########################
# Waits until microk8s starts
# Arguments:
#   none
# Returns:
#   none
#########################
wait_for_microk8s() {
  log_info "Waiting for microk8s to start..."
  microk8s.status --wait-ready --timeout 30
}

########################
# Restarts microk8s daemons
# Arguments:
#   none
# Returns:
#   none
#########################
snap_restart_microk8s() {
  snap restart microk8s
}

########################
# Starts microk8s daemons
# Arguments:
#   none
# Returns:
#   none
#########################
snap_start_microk8s() {
  snap start microk8s
}

########################
# Stops microk8s daemons
# Arguments:
#   none
# Returns:
#   none
#########################
snap_stop_microk8s() {
  snap stop microk8s
}

########################
# Refreshes kubectl configuration allowing the script invoker to use kubectl command locally to interact with microk8s cluster
# Arguments:
#   invoker username
# Returns:
#   none
#########################
refresh_kubectl_configuration() {
  if [[ -z "$1" ]]; then
    log_error "Please make sure to pass invoker username argument to refresh_kubectl_configuration() function."
    exit 1
  fi

  log_info "Refreshing microk8s configuration for local kubectl..."

  local invoker_username=$1
  local local_kubectl_config=""
  local_kubectl_config=$(2>&1 microk8s config > /home/"$invoker_username"/.kube/config)

  if [[ "$?" -ne 0 ]]; then
    log_error "$local_kubectl_config"
    log_error "Unable to refresh microk8s configuration for local kubectl. Make sure kubectl is installed and ~/.kube directory exists. You can install it using: snap install kubectl --classic --channel=$MICROK8S_VERSION/stable"
    exit 1
  fi

  log_success "kubectl config now points to $(cat /home/"$invoker_username"/.kube/config | grep server)"
  newline
}

########################
# Validates microk8s' node IP address against current local IP address
# Arguments:
#   current local IP address
# Returns:
#   none
#########################
validate_microk8s_ip() {
  if [[ -z "$1" ]]; then
    log_error "Please make sure to pass current ip address argument to validate_microk8s_ip() function."
    exit 1
  fi

  local current_ip=$1

  log_info "Checking ip address assigned to microk8s node..."

  local microk8s_ip="127.0.0.1"
  microk8s_ip=$(2>&1 microk8s.kubectl describe node $(microk8s.kubectl get nodes --no-headers | cut -f 1 -d " ") | grep InternalIP | awk '{print $2}')

  if [[ "$?" -ne 0 ]]; then
    log_error "$microk8s_ip"
    log_error "Unable to find IP address of microk8s node, terminating script."
    exit 1
  fi

  log_success "Found IP address of microk8s node: $microk8s_ip"

  if [[ "$microk8s_ip" == "$current_ip" ]]; then
    log_success "Current IP address $current_ip matches microk8s node IP address $microk8s_ip."
  else
    log_error "IP address mismatch, Current IP address $current_ip is different from microk8s node IP address $microk8s_ip. If the Operating System has been recently restarted, it is possible that microk8s is still reinitializing. Please run the script again in a moment, it may fix the issue."
    exit 1
  fi

  newline
}

########################
# Refreshes containerd's configuration in microk8s to point at correct current local IP address
# Arguments:
#   current local IP address
# Returns:
#   none
#########################
refresh_containerd_configuration() {
  if [[ -z "$1" ]]; then
    log_error "Please make sure to pass current ip address argument to refresh_containerd_configuration() function."
    exit 1
  fi

  local current_ip=$1

  log_info "Checking containerd configuration in microk8s to see whether the container registry IP address is set to $current_ip..."

  local containerd_template_container_registry_ip_address_defined=""
  containerd_template_container_registry_ip_address_defined=$(2>&1 cat /var/snap/microk8s/current/args/containerd-template.toml | grep 32000 | wc -l)

  if [[ "$?" -ne 0 ]]; then
    log_error "$containerd_template_container_registry_ip_address_defined"
    log_error "Unable to check containerd configuration in microk8s, terminating script."
    exit 1
  fi

  if [[ "$containerd_template_container_registry_ip_address_defined" == "4" ]]; then
    log_success "Container registry IP address seems to be defined in containerd's configuration in microk8s."
  else
    log_warn "Container registry IP address is currently not defined at all in containerd's configuration in microk8s. Setting it up now..."
    echo -e "      [plugins.\"io.containerd.grpc.v1.cri\".registry.mirrors.\"$current_ip:32000\"]\r\n        endpoint = [\"http://$current_ip:32000\"]" >> /var/snap/microk8s/current/args/containerd-template.toml
    snap_restart_microk8s
    wait_for_microk8s
  fi

  local containerd_template_container_registry_ip_address=""
  containerd_template_container_registry_ip_address=$(2>&1 cat /var/snap/microk8s/current/args/containerd-template.toml | grep 32000)

  if [[ "$?" -ne 0 ]]; then
    log_error "$containerd_template_container_registry_ip_address"
    log_error "Unable to check container registry's IP address defined in containerd's configuration in microk8s, terminating script."
    exit 1
  fi

  if [[ $containerd_template_container_registry_ip_address == *"$current_ip"* ]]; then
    log_success "Container registry IP address is properly defined in containerd's configuration in microk8s as $current_ip."
  else
    log_warn "Container registry IP address is not properly defined in containerd's configuration in microk8s. Fixing it to $current_ip..."

    echo "$containerd_template_container_registry_ip_address"
    local containerd_template_container_registry_ip_address_last_line=""
    containerd_template_container_registry_ip_address_last_line=$(2>&1 cat /var/snap/microk8s/current/args/containerd-template.toml | grep 32000 | tail -1)
    local httpToken="http://"

    local containerd_template_container_registry_ip_address_old=""
    containerd_template_container_registry_ip_address_old=${containerd_template_container_registry_ip_address_last_line#*"$httpToken"}
    sed -i "s/$containerd_template_container_registry_ip_address_old/$current_ip:32000\"]/g" /var/snap/microk8s/current/args/containerd-template.toml

    if [[ "$?" -ne 0 ]]; then
      log_error "Unable to fix container registry's IP address defined in containerd's configuration in microk8s, terminating script."
      exit 1
    fi

    containerd_template_container_registry_ip_address=$(2>&1 cat /var/snap/microk8s/current/args/containerd-template.toml | grep 32000)

    if [[ $containerd_template_container_registry_ip_address == *"$current_ip"* ]]; then
      log_success "$containerd_template_container_registry_ip_address"
    else
      log_error "$containerd_template_container_registry_ip_address"
      log_error "Failed to fix container registry's IP address defined in containerd's configuration in microk8s, terminating script."
      exit 1
    fi

    log_info "Patched container registry's IP address defined in containerd's configuration in microk8s, restarting microk8s now..."

    snap_restart_microk8s
    wait_for_microk8s
  fi

  newline
}

########################
# Starts microk8s: installs microk8s if needed, waits until it starts, checks ip address of the node against local ip, sets-up container registry ip, refreshes local kubectl config, if k8s is already running this function does nothing
# Arguments:
#   invoker username
#   current ip address
# Returns:
#   none
#########################
start_microk8s() {
  if [[ -z "$1" ]]; then
    log_error "Please make sure to pass invoker username argument to start_microk8s() function."
    exit 1
  fi

  if [[ -z "$2" ]]; then
    log_error "Please make sure to pass current ip address argument to start_microk8s() function."
    exit 1
  fi

  local invoker_username=$1
  local current_ip=$2

  local MICROK8S_STATUS=""
  get_microk8s_status MICROK8S_STATUS

  if [[ $MICROK8S_STATUS == *"microk8s is running"* ]]; then
    log_warn "$MICROK8S_STATUS"
    log_error "microk8s is already running, so it can't be started, try 'microk8s refresh', 'microk8s restart', 'microk8s stop' or 'microk8s remove' instead, terminating script."
    exit 1
  elif [[ $MICROK8S_STATUS == *"microk8s: command not found"* ]]; then
    install_microk8s "$MICROK8S_VERSION"
    wait_for_microk8s
  elif [[ $MICROK8S_STATUS == *"microk8s is not running."* ]]; then
    log_warn "$MICROK8S_STATUS"
    local kubelite_daemon_status=""
    snap_service_status kubelite_daemon_status "microk8s.daemon-kubelite"

    if [[ $kubelite_daemon_status == *"inactive"* ]]; then
      snap_start_microk8s
    fi

    wait_for_microk8s
  else
    log_warn "$MICROK8S_STATUS"
    log_error "Unable to recover from this error, terminating script."
    exit 1
  fi

  newline

  validate_microk8s_ip "$current_ip"
  #refresh_containerd_configuration "$current_ip" # bugged on microk8s 1.23
  refresh_kubectl_configuration "$invoker_username"
}

########################
# Restarts microk8s: installs microk8s if needed, waits until it starts, checks ip address of the node against local ip, sets-up container registry ip, refreshes local kubectl config
# Arguments:
#   invoker username
#   current ip address
# Returns:
#   none
#########################
restart_microk8s() {
  if [[ -z "$1" ]]; then
    log_error "Please make sure to pass invoker username argument to restart_microk8s() function."
    exit 1
  fi

  if [[ -z "$2" ]]; then
    log_error "Please make sure to pass current ip address argument to restart_microk8s() function."
    exit 1
  fi

  local invoker_username=$1
  local current_ip=$2

  local MICROK8S_STATUS=""
  get_microk8s_status MICROK8S_STATUS

  if [[ $MICROK8S_STATUS == *"microk8s is running"* ]]; then
    log_info "Restarting microk8s..."
    snap_restart_microk8s
    wait_for_microk8s
  elif [[ $MICROK8S_STATUS == *"microk8s: command not found"* ]]; then
    install_microk8s "$MICROK8S_VERSION"
    wait_for_microk8s
  elif [[ $MICROK8S_STATUS == *"microk8s is not running."* ]]; then
    log_warn "$MICROK8S_STATUS"
    local kubelite_daemon_status=""
    snap_service_status kubelite_daemon_status "microk8s.daemon-kubelite"

    if [[ $kubelite_daemon_status == *"inactive"* ]]; then
      snap_start_microk8s
    fi

    wait_for_microk8s
  else
    log_warn "$MICROK8S_STATUS"
    log_error "Unable to recover from this error, terminating script."
    exit 1
  fi

  newline

  validate_microk8s_ip "$current_ip"
  #refresh_containerd_configuration "$current_ip" # bugged on microk8s 1.23
  refresh_kubectl_configuration "$invoker_username"
}

########################
# Refreshes microk8s: installs microk8s if needed, waits until it starts, checks ip address of the node against local ip, refreshes container registry ip, refreshes local kubectl config
# Arguments:
#   daemons restarted placeholder
#   invoker username
#   current ip address
# Returns:
#   daemons restarted (true or false)
#########################
refresh_microk8s() {
  if [[ -z "$1" ]]; then
    log_error "Please make sure to pass daemons restarted placeholder argument to refresh_microk8s() function."
    exit 1
  fi

  if [[ -z "$2" ]]; then
    log_error "Please make sure to pass invoker username argument to refresh_microk8s() function."
    exit 1
  fi

  if [[ -z "$3" ]]; then
    log_error "Please make sure to pass current ip address argument to refresh_microk8s() function."
    exit 1
  fi

  local invoker_username=$2
  local current_ip=$3
  local daemons_restarted="false"

  local MICROK8S_STATUS=""
  get_microk8s_status MICROK8S_STATUS

  if [[ $MICROK8S_STATUS == *"microk8s is running"* ]]; then
    log_success "$MICROK8S_STATUS"
  elif [[ $MICROK8S_STATUS == *"microk8s: command not found"* ]]; then
    install_microk8s "$MICROK8S_VERSION"
    wait_for_microk8s
  elif [[ $MICROK8S_STATUS == *"microk8s is not running."* ]]; then
    log_warn "$MICROK8S_STATUS"
    local kubelite_daemon_status=""
    snap_service_status kubelite_daemon_status "microk8s.daemon-kubelite"

    if [[ $kubelite_daemon_status == *"inactive"* ]]; then
      snap_start_microk8s
      daemons_restarted="true"
    fi

    wait_for_microk8s
  else
    log_warn "$MICROK8S_STATUS"
    log_error "Unable to recover from this error, terminating script."
    exit 1
  fi

  newline

  validate_microk8s_ip "$current_ip"
  #refresh_containerd_configuration "$current_ip" # bugged on microk8s 1.23
  refresh_kubectl_configuration "$invoker_username"

  eval "$1='$daemons_restarted'"
}

########################
# Refreshes microk8s plugin: verifies if the plugin is up and running, and if it is not, then enables it
# Arguments:
#   plugin name
#   plugin namespace
#   plugin pod
# Returns:
#   none
#########################
refresh_microk8s_plugin() {
  if [[ -z "$1" ]]; then
    log_error "Please make sure to pass plugin name argument to refresh_microk8s_plugin() function."
    exit 1
  fi

  if [[ -z "$2" ]]; then
    log_error "Please make sure to pass plugin namespace argument to refresh_microk8s_plugin() function."
    exit 1
  fi

  if [[ -z "$3" ]]; then
    log_error "Please make sure to pass plugin pod argument to refresh_microk8s_plugin() function."
    exit 1
  fi

  local plugin_name=$1
  local plugin_namespace=$2
  local plugin_pod=$3
  local plugin_status=""

  log_info "Checking whether '$plugin_name' plugin is enabled in microk8s..."

  plugin_status=$(2>&1 microk8s status -a "$plugin_name")
  if [[ "$?" -ne 0 ]]; then
    log_error "$plugin_status"
    log_error "Unable to verify plugin, terminating script."
    exit 1
  fi

  if [[ "$plugin_status" == "disabled" ]]; then
    log_warn "microk8s plugin '$plugin_name' is disabled, enabling it now..."

    local plugin_enable=""
    if [[ "$plugin_name" == "kube-ovn" ]]; then
      plugin_enable=$(2>&1 microk8s enable "$plugin_name" --force)
    else
      plugin_enable=$(2>&1 microk8s enable "$plugin_name")
    fi

    if [[ "$?" -ne 0 ]]; then
      log_error "$plugin_enable"
      log_error "Unable to enable plugin, terminating script."
      exit 1
    fi

    echo "${plugin_enable}"

    log_success "microk8s plugin '$plugin_name' enabled successfully."

    if [[ "$plugin_pod" != "none" ]]; then
      log_info "Waiting for microk8s plugin '$plugin_name' to start..."

      microk8s status -a "$plugin_name" --wait-ready

      local spinner_counter=0

      log_info "Waiting for '$plugin_name' pod '$plugin_pod' in '$plugin_namespace' namespace..."

      until microk8s kubectl get pod -l "$plugin_pod" -n"$plugin_namespace" -o go-template='{{.items | len}}' | grep -qxF 1; do
        spin spinner_counter "$spinner_counter"
        sleep 0.1
      done

      finish_spin

      log_success "microk8s plugin '$plugin_name' started."

      if [[ "$plugin_name" == "kube-ovn" ]]; then
        disable_dns_plugin=$(2>&1 microk8s disable dns)
        if [[ "$?" -ne 0 ]]; then
          log_error "$disable_dns_plugin"
          log_error "Unable to disable dns plugin after activating kube-ovn plugin, terminating script."
          exit 1
        fi
        echo "${disable_dns_plugin}"
      fi
    fi
  else
    plugin_status=$(2>&1 microk8s status -a "$plugin_name" --wait-ready)
    if [[ "$?" -ne 0 ]]; then
      log_error "$plugin_status"
      log_error "Unable to verify plugin, terminating script."
      exit 1
    fi
    log_success "microk8s plugin '$plugin_name' is enabled."
  fi
}

########################
# Refreshes metallb plugin: verifies if the plugin is up and running and has correct IP settings, and if it is not, then enables or refreshes it
# Arguments:
#   loadbalancer ip range begin
#   loadbalancer ip range end
#   flow action
#   force metallb refresh (true or false)
# Returns:
#   none
#########################
refresh_metallb_plugin() {
  if [[ -z "$1" ]]; then
    log_error "Please make sure to pass loadbalancer's ip range begin argument to refresh_metallb_plugin() function."
    exit 1
  fi

  if [[ -z "$2" ]]; then
    log_error "Please make sure to pass loadbalancer's ip range end argument to refresh_metallb_plugin() function."
    exit 1
  fi

  if [[ -z "$3" ]]; then
    log_error "Please make sure to pass flow action argument to refresh_metallb_plugin() function."
    exit 1
  fi

  if [[ -z "$4" ]]; then
    log_error "Please make sure to pass force metallb refresh argument to refresh_metallb_plugin() function."
    exit 1
  fi

  local loadbalancer_ip_range_begin=$1
  local loadbalancer_ip_range_end=$2
  local flow_action=$3
  local force_metallb_refresh=$4

  local plugin_status=""

  log_info "Checking whether 'metallb' plugin is enabled in microk8s..."

  plugin_status=$(2>&1 microk8s status -a metallb)
  if [[ "$?" -ne 0 ]]; then
    log_error "$plugin_status"
    log_error "Unable to verify plugin, terminating script."
    exit 1
  fi

  if (( "${flow_action}" != "start" )) && [[ "$plugin_status" == "disabled" ]]; then
    log_warn "microk8s plugin 'metallb' is disabled, enabling it now..."

    local plugin_enable=""
    plugin_enable=$(2>&1 microk8s enable metallb:$loadbalancer_ip_range_begin-$loadbalancer_ip_range_end)

    if [[ "$?" -ne 0 ]]; then
      log_error "$plugin_enable"
      log_error "Unable to enable plugin, terminating script."
      exit 1
    fi

    echo "${plugin_enable}"

    log_success "microk8s plugin 'metallb' enabled successfully."
    log_info "Waiting for microk8s plugin 'metallb' to start..."

    microk8s status -a "metallb" --wait-ready
  else
    local metallb_verify=""

    if [[ "${flow_action}" == "restart" ]]; then
      metallb_verify="'metallb' must be recreated due to microk8s restart..."
    elif [[ "${flow_action}" == "start" ]]; then
      metallb_verify="'metallb' initializing..."
    elif [[ "${force_metallb_refresh}" == "true" ]]; then
      metallb_verify="'metallb' is in invalid state and must be recreated..."
    else
      log_info "Verifying if metallb is configured with proper IP range $loadbalancer_ip_range_begin-$loadbalancer_ip_range_end"

      metallb_verify=$(2>&1 microk8s kubectl describe ipaddresspools.metallb.io/default-addresspool -nmetallb-system | grep Addresses -A1 | grep -v "^  Addresses" | awk '{print $1}')

      if [[ "$?" -ne 0 ]]; then
        if [[ $metallb_verify == *"NotFound"* ]]; then
          log_warn "$metallb_verify"
          metallb_verify="'metallb' initializing..."
        else
          log_error "$metallb_verify"
          log_error "Unable to verify metallb plugin, terminating script."
          exit 1
        fi
      fi
    fi

    echo "$metallb_verify"

    if [[ "$metallb_verify" == *"$loadbalancer_ip_range_begin-$loadbalancer_ip_range_end"* ]]; then
      microk8s status -a metallb --wait-ready
      log_success "metallb is configured correctly."
    else
      log_warn "metallb is using outdated configuration, fixing it now..."
      microk8s kubectl delete pod --selector app=metallb --grace-period=0 --force --namespace metallb-system
      microk8s disable metallb
      microk8s kubectl delete namespace metallb-system
	    microk8s status -a metallb --wait-ready
	    microk8s enable metallb:$loadbalancer_ip_range_begin-$loadbalancer_ip_range_end
	    microk8s status -a metallb --wait-ready
	    metallb_verify=$(2>&1 microk8s kubectl describe cm config -nmetallb-system)
	    echo "$metallb_verify"
	    log_success "metallb is now configured correctly."
    fi
  fi
}

########################
# Refreshes microk8s plugins: verifies which plugins are up and running, enables missing ones and updates the ip address settings of each plugin if necessary
# Arguments:
#   loadbalancer ip range begin
#   loadbalancer ip range end
#   flow action
#   force metallb refresh (true or false)
# Returns:
#   none
#########################
refresh_microk8s_plugins() {
  if [[ -z "$1" ]]; then
    log_error "Please make sure to pass loadbalancer's ip range begin argument to refresh_microk8s_plugins() function."
    exit 1
  fi

  if [[ -z "$2" ]]; then
    log_error "Please make sure to pass loadbalancer's ip range end argument to refresh_microk8s_plugins() function."
    exit 1
  fi

  if [[ -z "$3" ]]; then
    log_error "Please make sure to pass flow action argument to refresh_microk8s_plugins() function."
    exit 1
  fi

  if [[ -z "$4" ]]; then
    log_error "Please make sure to pass force metallb refresh argument to refresh_microk8s_plugins() function."
    exit 1
  fi

  local loadbalancer_ip_range_begin=$1
  local loadbalancer_ip_range_end=$2
  local flow_action=$3
  local force_metallb_refresh=$4

  log_info "Waiting for kube-system pods to initialize..."
  microk8s kubectl wait --timeout=180s --for=condition=ready pod -l k8s-app=calico-node -nkube-system
  microk8s kubectl wait --timeout=180s --for=condition=ready pod -l k8s-app=calico-kube-controllers -nkube-system
  microk8s kubectl get pod -A
  log_success "kubs-system pods are up and running."

  local i=0
  for i in "${!PLUGINS[@]}"; do
    if [[ "${PLUGINS[$i]}" == "metallb" ]]; then
      refresh_metallb_plugin "$loadbalancer_ip_range_begin" "$loadbalancer_ip_range_end" "$flow_action" "$force_metallb_refresh"
    else
      refresh_microk8s_plugin "${PLUGINS[$i]}" "${PLUGIN_NAMESPACES[$i]}" "${PLUGIN_PODS[$i]}"
    fi
  done

  newline
}

########################
# Runs microk8s flow
# Arguments:
#   flow action
#   invoker username
# Returns:
#   none
#########################
run_microk8s_flow() {
  if [[ -z "$1" ]]; then
    log_error "Please make sure to pass flow action argument to run_microk8s_flow() function."
    exit 1
  fi

  if [[ -z "$2" ]]; then
    log_error "Please make sure to pass invoker username argument to run_microk8s_flow() function."
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

  local force_metallb_refresh="false"

  if [[ "${flow_action}" == "refresh" ]]; then
    refresh_microk8s force_metallb_refresh "$invoker_username" "$current_ip"
  elif [[ "${flow_action}" == "start" ]]; then
    start_microk8s "$invoker_username" "$current_ip"
  elif [[ "${flow_action}" == "restart" ]]; then
    restart_microk8s "$invoker_username" "$current_ip"
  elif [[ "${flow_action}" == "stop" ]]; then
    log_info "Stopping microk8s daemons..."
    snap_stop_microk8s
    log_success "Microk8s stopped, re-run the script with 'microk8s start', 'microk8s restart' or 'microk8s refresh' to bring it back."
    exit 0
  elif [[ "${flow_action}" == "remove" ]]; then
    log_warn "Removing microk8s in 10 seconds.... (Press CTRL+C to abort)"
    sleep 10
    snap remove microk8s
    log_warn "Microk8s removed."
    exit 0
  else
    log_error "Unknown flow action '${flow_action}' for microk8s flow, terminating script."
    exit 1
  fi

  log_info "Calculating IP range for $LOADBALANCER_NUM_OF_IP_ADDRESSES addresses higher than current $current_ip..."

  local loadbalancer_ip_range_begin=""
  calculate_next_ip loadbalancer_ip_range_begin "$current_ip"

  local loadbalancer_ip_range_end=""
  calculate_new_ip_with_offset loadbalancer_ip_range_end "$loadbalancer_ip_range_begin" "$LOADBALANCER_NUM_OF_IP_ADDRESSES"

  log_success "Loadbalancer will use the following IP range: $loadbalancer_ip_range_begin-$loadbalancer_ip_range_end."
  newline

  refresh_microk8s_plugins "$loadbalancer_ip_range_begin" "$loadbalancer_ip_range_end" "$flow_action" "$force_metallb_refresh"

  local ingress_ip_address="$loadbalancer_ip_range_begin"

  if [[ $KONG_ENABLED == "true" ]]; then
    refresh_kong_api_gateway ingress_ip_address
  fi

  setup_k8s_dashboard "${ingress_ip_address}"
}
