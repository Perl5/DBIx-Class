#!/bin/bash

# !!! Nothing here will be executed !!!
# The source-line calling this script is commented out in .travis.yml

source maint/travis-ci_scripts/common.bash
if [[ -n "$SHORT_CIRCUIT_SMOKE" ]] ; then return ; fi

echo_err "Nothing to do"

return 0
