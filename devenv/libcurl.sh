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
# Library wrapper for cURL binary

# Load required libraries
#. ./liblog.sh # log_info, log_error

########################
# Simple cURL call with no parameters
# Arguments:
#   result placeholder
#   url
# Returns:
#   result
#########################
simple_curl_call() {
  if [[ -z "$1" ]]; then
    log_error "Please make sure to pass result placeholder argument to simple_curl_call() function."
    exit 1
  fi

  if [[ -z "$2" ]]; then
    log_error "Please make sure to pass url argument to simple_curl_call() function."
    exit 1
  fi

  local url=$2

  log_info "Running cURL call to '$url'..."

  local curl_call=""
  curl_call=$(2>&1 curl --connect-timeout 10 "${url}")

  if [[ "$?" -ne 0 ]]; then
    log_error "$curl_call"
    log_error "Unable to interact with cURL, terminating script."
    exit 1
  fi

  eval "$1='$curl_call'"
}
