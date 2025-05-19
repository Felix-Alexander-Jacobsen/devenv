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
# Library for interacting with Helm

# Load required libraries
#. ./liblog.sh # log_info, log_error, log_success, log_warn

########################
# Updates all helm repositories
# Arguments:
#   none
# Returns:
#   none
#########################
update_all_helm_repositories() {
  local repositories_update=""
  repositories_update=$(2>&1 microk8s helm3 repo update)

  if [[ "$?" -ne 0 ]]; then
    log_error "$repositories_update"
    log_error "Unable to interact with helm, terminating script."
    exit 1
  fi

  log_success "$repositories_update"
}

########################
# Adds new Helm repository
# Arguments:
#   repository name
#   repository url
# Returns:
#   none
#########################
add_helm_repository() {
  if [[ -z "$1" ]]; then
    log_error "Please make sure to pass repository name argument to add_helm_repository() function."
    exit 1
  fi

  if [[ -z "$2" ]]; then
    log_error "Please make sure to pass repository url argument to add_helm_repository() function."
    exit 1
  fi

  local repository_name=$1
  local repository_url=$2

  log_info "Adding '${repository_name}' Helm repository..."

  local repository_add=""
  repository_add=$(2>&1 microk8s helm3 repo add "${repository_name}" "${repository_url}")

  if [[ "$?" -ne 0 ]]; then
    log_error "$repository_add"
    log_error "Unable to interact with helm, terminating script."
    exit 1
  fi

  log_success "'${repository_name}' Helm repository added successfully."
}

########################
# Refreshes given helm repository
# Arguments:
#   repository name
#   repository url
# Returns:
#   none
#########################
refresh_helm_repository() {
  if [[ -z "$1" ]]; then
    log_error "Please make sure to pass repository name argument to refresh_helm_repository() function."
    exit 1
  fi

  if [[ -z "$2" ]]; then
    log_error "Please make sure to pass repository url argument to refresh_helm_repository() function."
    exit 1
  fi

  local repository_name=$1
  local repository_url=$2

  log_info "Refreshing '${repository_name}' Helm repository..."

  local helm_repository_exists=""
  does_helm_repository_exist helm_repository_exists "${repository_name}"

  if [[ $helm_repository_exists == *"false"* ]]; then
    add_helm_repository "${repository_name}" "${repository_url}"
  fi

  update_all_helm_repositories
}

########################
# Verifies whether a given helm repository exists
# Arguments:
#   result placeholder
#   repository name
# Returns:
#   result (true or false)
#########################
does_helm_repository_exist() {
  if [[ -z "$1" ]]; then
    log_error "Please make sure to pass result placeholder argument to does_helm_repository_exist() function."
    exit 1
  fi

  if [[ -z "$2" ]]; then
    log_error "Please make sure to pass repository name argument to does_helm_repository_exist() function."
    exit 1
  fi

  local repository_name=$2

  log_info "Checking if '${repository_name}' Helm repository exists..."

  local repository_check=""
  repository_check=$(2>&1 microk8s helm3 repo list)

  if [[ "$?" -ne 0 ]]; then
    if [[ $repository_check == *"no repositories"* ]]; then
      log_warn "$repository_check"
      eval "$1='false'"
    else
      log_error "$repository_check"
      log_error "Unable to interact with helm, terminating script."
      exit 1
    fi
  fi

  if [[ $repository_check == *"not available"* ]]; then
    log_error "$repository_check"
    log_error "Unable to interact with helm - make sure the plugin is enabled, terminating script."
    exit 1
  fi

  if [[ $repository_check == *"${repository_name}"* ]]; then
    log_success "'${repository_name}' repository is registered within helm."
    eval "$1='true'"
  else
    log_warn "'${repository_name}' repository is not registered within helm."
    eval "$1='false'"
  fi
}

########################
# Verifies whether a given deployment exists
# Arguments:
#   result placeholder
#   namespace name
#   deployment name
# Returns:
#   result (true or false)
#########################
does_helm_deployment_exist() {
  if [[ -z "$1" ]]; then
    log_error "Please make sure to pass result placeholder argument to does_helm_deployment_exist() function."
    exit 1
  fi

  if [[ -z "$2" ]]; then
    log_error "Please make sure to pass namespace name argument to does_helm_deployment_exist() function."
    exit 1
  fi

  if [[ -z "$3" ]]; then
    log_error "Please make sure to pass deployment name argument to does_helm_deployment_exist() function."
    exit 1
  fi

  local namespace_name=$2
  local deployment_name=$3

  log_info "Checking if '${deployment_name}' Helm deployment exists..."

  local deployment_check=""
  deployment_check=$(2>&1 microk8s helm3 ls -n"${namespace_name}")

  if [[ "$?" -ne 0 ]]; then
    log_error "$deployment_check"
    log_error "Unable to verify whether Helm deployment is already installed, terminating script."
    exit 1
  fi

  if [[ $deployment_check == *"${deployment_name}"* ]]; then
    log_success "'${deployment_name}' Helm deployment exists in namespace '${namespace_name}'."
    eval "$1='true'"
  else
    log_warn "'${deployment_name}' Helm deployment does not exist in namespace '${namespace_name}'."
    eval "$1='false'"
  fi
}

########################
# Creates a new deployment
# Arguments:
#   namespace name
#   deployment name
#   helm repo path
#   deployment options
# Returns:
#   none
#########################
create_helm_deployment() {
  if [[ -z "$1" ]]; then
    log_error "Please make sure to pass namespace name argument to create_helm_deployment() function."
    exit 1
  fi

  if [[ -z "$2" ]]; then
    log_error "Please make sure to pass deployment name argument to create_helm_deployment() function."
    exit 1
  fi

  if [[ -z "$3" ]]; then
    log_error "Please make sure to pass helm repo path argument to create_helm_deployment() function."
    exit 1
  fi

  if [[ -z "$4" ]]; then
    log_error "Please make sure to pass deployment options argument to create_helm_deployment() function."
    exit 1
  fi

  local namespace_name=$1
  local deployment_name=$2
  local helm_repo_path=$3
  local deployment_options=$4

  log_info "Creating Helm deployment '${deployment_name}' in '${namespace_name}' namespace from Helm repo '${helm_repo_path}'..."

  local deployment_create=""
  deployment_create=$(2>&1 microk8s helm3 install "${deployment_name}" "${helm_repo_path}" ${deployment_options} --namespace "${namespace_name}")

  if [[ "$?" -ne 0 ]]; then
    log_error "$deployment_create"
    log_error "Unable to interact with Helm - make sure repositories are properly set-up and up-to-date, terminating script."
    exit 1
  else
    log_success "$deployment_create"
  fi
}
