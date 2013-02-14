#!/bin/bash

source maint/travis-ci_scripts/common.bash
if [[ -n "$SHORT_CIRCUIT_SMOKE" ]] ; then return ; fi

[[ "$CLEANTEST" = "true" ]] || run_or_err "Attempt to build a dist with all prereqs present" "make dist"
