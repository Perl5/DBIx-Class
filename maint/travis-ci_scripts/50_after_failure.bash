#!/bin/bash

# this file is executed in a subshell - set up the common stuff
source maint/travis-ci_scripts/common.bash

if [[ -n "$SHORT_CIRCUIT_SMOKE" ]] ; then exit 0 ; fi

if [[ "$(dmesg)" =~ $( echo "\\bOOM\\b" ) ]] ; then
  echo_err "=== dmesg ringbuffer"
  echo_err "$(dmesg)"
fi
