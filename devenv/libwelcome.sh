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
# Library for managing the welcome message

# Load required libraries
#. ./liblog.sh # log_info, log_warn, newline
#. ./libdevenv.sh # get_project_name
#. ./libversion.sh # get_version

########################
# Prints welcome message
# Arguments:
#   none
# Returns:
#   none
#########################
print_welcome() {
  log_warn ":: $(get_project_name) :: $(get_version) ::"
  log_info "Performing evaluation of the Development Environment, please stand by..."
  newline

  print_options

  newline
}

########################
# Prints available options and assigned values
# Arguments:
#   none
# Returns:
#   none
#########################
print_options() {
  echo "SLOW_MOTION_TEXT=${SLOW_MOTION_TEXT}"
  echo "MICROK8S_VERSION=${MICROK8S_VERSION}"
  echo "LOADBALANCER_NUM_OF_IP_ADDRESSES=${LOADBALANCER_NUM_OF_IP_ADDRESSES}"
  echo -n "PLUGINS="
  local i=0
  for i in "${!PLUGINS[@]}"; do
    printf "%s " "${PLUGINS[$i]}"
  done
  newline
  echo "KONG_ENABLED=${KONG_ENABLED}"
  echo "DASHBOARD_DOMAIN=${DASHBOARD_DOMAIN}"
  echo "DASHBOARD_CERTIFICATE=${DASHBOARD_CERTIFICATE}"
  echo -n "FLOWS="
  local i=0
  for i in "${!FLOWS[@]}"; do
    printf "%s " "$i"
  done
  newline
  echo "RUN_FLOW=${RUN_FLOW}"
  echo "FLOW_ACTION=${FLOW_ACTION}"
}
