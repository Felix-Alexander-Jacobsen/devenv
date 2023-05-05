#!/bin/bash
# The MIT License (MIT)
#
# Copyright (c) 2022-2023 Felix Jacobsen
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
# Library wrapper for git binary

# Load required libraries
#. ./liblog.sh # log_info, log_error

########################
# git clone command
# Arguments:
#   git repository
# Returns:
#   none
#########################
git_clone() {
  if [[ -z "$1" ]]; then
    log_error "Please make sure to pass git repository argument to git_clone() function."
    exit 1
  fi

  local url=$1

  log_info "Cloning git repository '$url'..."
  newline

  local slow_motion_text_backup=${SLOW_MOTION_TEXT}
  SLOW_MOTION_TEXT=false

  local git_call=""
  git_call=$(2>&1 su -c "git clone --progress ${url}" $INVOKER_USERNAME)

  if [[ "$?" -ne 0 ]]; then
    SLOW_MOTION_TEXT=$slow_motion_text_bac
    log_error "${git_call}"
    log_error "Unable to interact with git, terminating script."
    exit 1
  fi

  log_success "${git_call}"
  newline
  SLOW_MOTION_TEXT=$slow_motion_text_backup
}

########################
# git pull command
# Arguments:
#   git directory
# Returns:
#   none
#########################
git_pull() {
  if [[ -z "$1" ]]; then
    log_error "Please make sure to pass git directory argument to git_pull() function."
    exit 1
  fi

  local directory=$1

  log_info "Pulling git repository '$directory'..."
  newline

  local slow_motion_text_backup=${SLOW_MOTION_TEXT}
  SLOW_MOTION_TEXT=false

  local git_call=""
  git_call=$(2>&1 su -c "git -C ${directory} pull --progress" $INVOKER_USERNAME)

  if [[ "$?" -ne 0 ]]; then
    SLOW_MOTION_TEXT=$slow_motion_text_bac
    log_error "${git_call}"
    log_error "Unable to interact with git, terminating script."
    exit 1
  fi

  log_success "${git_call}"
  newline
  SLOW_MOTION_TEXT=$slow_motion_text_backup
}
