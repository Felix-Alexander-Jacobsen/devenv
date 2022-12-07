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
# Library manging flow execution

# Load required libraries
#. ./liblog.sh # log_info
#. ./libmicrok8s.sh # run_microk8s_flow
#. ./libkafka.sh # run_kafka_flow
#. ./libmongodb.sh # run_mongodb_flow

declare -A FLOWS;
FLOWS["microk8s"]=run_microk8s_flow
FLOWS["kafka"]=run_kafka_flow
FLOWS["mongodb"]=run_mongodb_flow

declare -a FLOW_ACTIONS;
FLOW_ACTIONS=("start" "restart" "refresh" "stop" "remove")

########################
# Runs given flow
# Arguments:
#   flow name
#   flow action
#   invoker username
# Returns:
#   none
#########################
run_flow() {
  if [[ -z "$1" ]]; then
    log_error "Please make sure to pass flow name argument to run_flow() function."
    exit 1
  fi

  if [[ -z "$2" ]]; then
    log_error "Please make sure to pass flow action argument to run_flow() function."
    exit 1
  fi

  if [[ -z "$3" ]]; then
    log_error "Please make sure to pass invoker username argument to run_flow() function."
    exit 1
  fi

  local flow_name="$1"
  local flow_action="$2"
  local invoker_username="$3"

  if [ ! -v "FLOWS[${flow_name}]" ]; then
    log_error "Invalid flow name '${flow_name}', please choose one of existing flows, terminating script."
    log_error "Possible flows:"
    local i=0
    for i in "${!FLOWS[@]}"; do
      echo -en "\t"
      log_error "%s " "${i}"
    done
    newline
    exit 1
  fi

  if (printf '%s\n' "${FLOW_ACTIONS[@]}" | grep -xq "${flow_action}"); then
    log_info "Running flow '${flow_name}' with action '${flow_action}'..."
    newline
    ${FLOWS[$flow_name]} "${flow_action}" "${invoker_username}"
  else
    log_error "Invalid flow action '${flow_action}', please choose one of existing flow actions, terminating script."
    log_error "Possible actions:"
    local i=0
    for i in "${!FLOW_ACTIONS[@]}"; do
      echo -en "\t"
      log_error "%s " "${FLOW_ACTIONS[$i]}"
    done
    newline
    exit 1
  fi
}
