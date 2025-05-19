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
# Library for interacting with the Operating System

# Load required libraries
#. ./liblog.sh # logInfo

########################
# Updates /etc/hosts entry
# Arguments:
#   entry to update
#   new address
# Returns:
#   none
#########################
update_etc_hosts() {
  if [[ -z "$1" ]]; then
    log_error "Please make sure to pass entry to update argument to update_etc_hosts() function."
    exit 1
  fi

  if [[ -z "$2" ]]; then
    log_error "Please make sure to pass new address argument to update_etc_hosts() function."
    exit 1
  fi

  local entry_to_update="$1"
  local new_address="$2"
  local escaped_entry_to_update=$(echo "${entry_to_update}" | sed 's/\$//')

  log_info "Updating /etc/hosts '${escaped_entry_to_update}' entry to '${new_address}'..."

  local etc_hosts_update=""
  etc_hosts_update=$(2>&1 sed -i "s/.*$entry_to_update/$new_address\t$escaped_entry_to_update/g" /etc/hosts)

  if [[ "$?" -ne 0 ]]; then
    log_error "$etc_hosts_update"
    log_error "Unable to edit /etc/hosts, terminating script."
    exit 1
  else
    log_success "/etc/hosts '${escaped_entry_to_update}' entry updated successfully to ${new_address}."
  fi
}

########################
# Looks up snap service status
# Arguments:
#   service status placeholder
#   service name
# Returns:
#   service status
#########################
snap_service_status() {
  if [[ -z "$1" ]]; then
    log_error "Please make sure to pass service status placeholder argument to snap_service_status() function."
    exit 1
  fi

  if [[ -z "$2" ]]; then
    log_error "Please make sure to pass service name argument to snap_service_status() function."
    exit 1
  fi

  local service_name="$2"

  local snap_service_status_lookup=""
  snap_service_status_lookup=$(2>&1 snap services | grep "$service_name" | awk '{print $3}')

  if [[ "$?" -ne 0 ]]; then
    log_error "$snap_service_status_lookup"
    log_error "Unable to lookup snap service status, terminating script."
    exit 1
  else
    eval "$1='$snap_service_status_lookup'"
  fi
}

########################
# Spin progress spinner once
# Arguments:
#   spinner status placeholder
#   spinner counter
# Returns:
#   spinner status
#########################
spin() {
  if [[ -z "$1" ]]; then
    log_error "Please make sure to pass spinner status placeholder argument to spin() function."
    exit 1
  fi

  if [[ -z "$2" ]]; then
    log_error "Please make sure to pass spinner counter argument to spin() function."
    exit 1
  fi

  local sc=$2
  local sp="/-\|"
  printf "\b${sp:sc++:1}"
  ((sc==${#sp})) && sc=0

  eval "$1='$sc'"
}

########################
# Finalize progress spinner
# Arguments:
#   none
# Returns:
#   none
#########################
finish_spin() {
   printf "\r%s\n" "$@"
}

########################
# Checks if file exists
# Arguments:
#   file existence placeholder
#   path to file
# Returns:
#   'true' if file exists, 'false' otherwise
#########################
does_file_exist() {
  if [[ -z "$1" ]]; then
    log_error "Please make sure to pass file existence placeholder argument to does_file_exist() function."
    exit 1
  fi

  if [[ -z "$2" ]]; then
    log_error "Please make sure to pass path to file argument to does_file_exist() function."
    exit 1
  fi

  local path_to_file="$2"

  if [[ -f "$path_to_file" ]]; then
    eval "$1='true'"
  else
    eval "$1='false'"
  fi
}
