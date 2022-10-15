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
# Library for managing version

# Load required libraries
#. ./liblog.sh # logInfo

########################
# Gets semantic version
# Arguments:
#   none
# Returns:
#   current version
#########################
get_version() {
  local major_version="1"
  local minor_version="0"
  local patch_version="0"
  local timestamp_version="20221015T214731"
  local build_version="2"

  local retver="$major_version.$minor_version.$patch_version-$timestamp_version.$build_version"
  echo "$retver"
}
