#!/bin/bash
# The MIT License (MIT)
#
# Copyright (c) 2022-2024 Felix Jacobsen
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
# Library for network related functions

# Load required libraries
#. ./liblog.sh # log_info, log_warn, log_error, newline

########################
# Gets default network interface
# Arguments:
#   network interface placeholder
# Returns:
#   default network interface
#########################
get_default_network_interface () {
  if [[ -z "$1" ]]; then
    log_error "Please make sure to pass an argument to get_default_network_interface() function."
    exit 1
  fi

  log_info "Checking available network interfaces..."

  local network_interfaces=""
  network_interfaces=$(2>&1 route)

  if [[ "$?" -ne 0 ]]; then
    log_error "$network_interfaces"
    log_error "Please make sure 'route' command is installed and available, terminating script."
    exit 1
  fi

  echo "$network_interfaces"

  local default_interface=""
  default_interface=$(echo "$network_interfaces" | grep "default " | awk '{print $8}')

  if [[ "$?" -ne 0 ]]; then
    log_error "$default_interface"
    log_error "Unable to determine default network interface, terminating script."
    exit 1
  fi

  eval "$1='$default_interface'"
}

########################
# Converts IP address string to an integer
# Arguments:
#   ip address placeholder
#   ip address string
# Returns:
#   ip address integer
#########################
inet_aton() {
  if [[ -z "$1" ]]; then
    log_error "Please make sure to pass a placeholder argument to inet_aton() function."
    exit 1
  fi

  if [[ -z "$2" ]]; then
    log_error "Please make sure to pass an ip address argument to inet_aton() function."
    exit 1
  fi

  local i=0
  local IFS=. ipaddr ip32 i
  ipaddr=($2)
  for i in 3 2 1 0
  do
      (( ip32 += ipaddr[3-i] * (256 ** i) ))
  done

  eval "$1='$ip32'"
}

########################
# Gets current IP address
# Arguments:
#   current ip address placeholder
#   network interface to inspect
# Returns:
#   current ip address
#########################
get_current_ip () {
  if [[ -z "$1" ]]; then
    log_error "Please make sure to pass a placeholder argument to get_current_ip() function."
    exit 1
  fi

  if [[ -z "$2" ]]; then
    log_error "Please make sure to pass a network interface argument to get_current_ip() function."
    exit 1
  fi

  local network_interface=$2

  log_info "Checking ip address assigned to the network interface $network_interface..."

  local ip_address=""
  ip_address=$(2>&1 ifconfig "$network_interface" | grep "inet " | awk '{print $2}')

  if [[ "$?" -ne 0 ]]; then
    log_error "$ip_address"
    log_error "Please make sure 'ifconfig' command is installed and available, terminating script."
    exit 1
  fi

  log_success "Found current IP address assigned to interface $network_interface: $ip_address"
  newline

  eval "$1='$ip_address'"
}

########################
# Calculate next IP address
# Arguments:
#   next ip address placeholder
#   the base ip address to begin the calculation with
# Returns:
#   next ip address
#########################
calculate_next_ip() {
  if [[ -z "$1" ]]; then
    log_error "Please make sure to pass a placeholder argument to calculate_next_ip() function."
    exit 1
  fi

  if [[ -z "$2" ]]; then
    log_error "Please make sure to pass the base ip address argument to calculate_next_ip() function."
    exit 1
  fi

  local base_ip_address=""
  local ip_hex=""
  local next_ip_hex=""
  local next_ip=""

  base_ip_address=$2
  ip_hex=$(printf '%.2X%.2X%.2X%.2X' $(echo "$base_ip_address" | sed -e 's/\./ /g'))
  next_ip_hex=$(printf %.8X $(echo $(( 0x$ip_hex + 1))))
  next_ip=$(printf '%d.%d.%d.%d' $(echo "$next_ip_hex" | sed -r 's/(..)/0x\1 /g'))

  eval "$1='$next_ip'"
}

########################
# Calculate new IP address using provided base IP address and an offset
# Arguments:
#   new ip address placeholder
#   the base ip address to begin the calculation with
#   ip address offset
# Returns:
#   new ip address
#########################
calculate_new_ip_with_offset() {
  if [[ -z "$1" ]]; then
    log_error "Please make sure to pass a placeholder argument to calculate_new_ip_with_offset() function."
    exit 1
  fi

  if [[ -z "$2" ]]; then
    log_error "Please make sure to pass the base ip address argument to calculate_new_ip_with_offset() function."
    exit 1
  fi

  if [[ -z "$3" ]]; then
    log_error "Please make sure to pass the offset argument (e.g. 16) to calculate_new_ip_with_offset() function."
    exit 1
  fi

  local ip_address_range_begin="$2"
  local offset=$3
  local ip=""
  local i=0

  ip="$ip_address_range_begin"
  for i in $(seq 1 "$offset"); do
    calculate_next_ip ip "$ip"
  done

  eval "$1='$ip'"
}
