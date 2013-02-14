#!/bin/bash

source maint/travis-ci_scripts/common.bash
if [[ -n "$SHORT_CIRCUIT_SMOKE" ]] ; then return ; fi

export HARNESS_TIMER=1 HARNESS_OPTIONS=c:j$NUMTHREADS

START_TIME=$SECONDS
if [[ "$CLEANTEST" = "true" ]] ; then
  echo_err "$(tstamp) Running tests with plain \`make test\`"
  run_or_err "Prepare blib" "make pure_all"
  make test
else
  PROVECMD="prove -lrswj$NUMTHREADS t xt"
  echo_err "$(tstamp) running tests with \`$PROVECMD\`"
  $PROVECMD
fi

echo "$(tstamp) Testing took a total of $(( $SECONDS - $START_TIME ))s"
