#!/bin/bash

# !!! Nothing here will be executed !!!
# The line calling this script is commented out in .travis.yml

# this file is executed in a subshell - set up the common stuff
source maint/travis-ci_scripts/common.bash

if [[ -n "$SHORT_CIRCUIT_SMOKE" ]] ; then exit 0 ; fi

echo_err "Nothing to do"
