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
# Library with functions related to user

# Load required libraries
#. ./liblog.sh # log_info, log_warn, newline

########################
# Gets the original (non super-user) script invoker
# Arguments:
#   username placeholder
# Returns:
#   Original (non super-user) script invoker
#########################
get_invoker_username() {
  if [[ -z "$1" ]]; then
    log_error "Please make sure to pass an argument to get_invoker_username() function."
    exit 1
  fi

  local username=${SUDO_USER:-$USER}

  log_info "Looking for the original (non super-user) script invoker..."
  log_success "Invoker is '$username'."

  newline

  eval "$1='$username'"
}
