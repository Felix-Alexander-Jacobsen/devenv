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
# Library for log related functions

# The following function prints a text using custom color
# -c or --color define the color for the print. See the array colors for the available options.
# -n or --noline directs the system not to print a new line after the content.
# Last argument is the message to be printed.
cecho () {

  declare -A colors;
  colors=(\
    ['black']='\E[0;47m'\
    ['red']='\E[0;31m'\
    ['green']='\E[0;32m'\
    ['yellow']='\E[0;33m'\
    ['blue']='\E[0;34m'\
    ['magenta']='\E[0;35m'\
    ['cyan']='\E[0;36m'\
    ['white']='\E[0;37m'\
  );

  local defaultMSG="No message passed.";
  local defaultColor="black";
  local color="white";
  local defaultNewLine=true;
  local newLine=true;

  while [[ $# -gt 1 ]];
  do
  local key="$1";

  case $key in
    -c|--color)
        color="$2";
        shift;
      ;;
      -n|--noline)
          newLine=false;
      ;;
      *)
          # unknown option
      ;;
  esac
  shift;
  done

  local message=${1:-$defaultMSG};   # Defaults to default message.
  color=${color:-$defaultColor};   # Defaults to default color, if not specified.
  newLine=${newLine:-$defaultNewLine};

  echo -en "${colors[$color]}";

  if [ "$SLOW_MOTION_TEXT" = true ] ; then
    local i=0
    for ((i=0; i<${#message} ; i++)) ; do
      echo -en "${message:i:1}"
      sleep 0.002
    done
  else
    echo -en "$message";
  fi

  if [ "$newLine" = true ] ; then
      echo;
  fi
  tput sgr0; #  Reset text attributes to normal without clearing screen.

  return;
}

update_date_with_time() {
  DATE_WITH_TIME=`date "+%Y-%m-%d %H:%M:%S.%3N"`
}

log_warn () {
  update_date_with_time
  cecho -c 'yellow' "[$DATE_WITH_TIME][W] $@";
}

log_error () {
  update_date_with_time
  cecho -c 'red' "[$DATE_WITH_TIME][E] $@";
}

log_success () {
  update_date_with_time
  cecho -e -c 'green' "[$DATE_WITH_TIME][S] $@";
}

log_info () {
  update_date_with_time
  cecho -e -c 'cyan' "[$DATE_WITH_TIME][I] $@";
}

newline () {
  echo ""
}
