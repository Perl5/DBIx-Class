#!/bin/bash

source maint/travis-ci_scripts/common.bash
if [[ -n "$SHORT_CIRCUIT_SMOKE" ]] ; then return ; fi

export HARNESS_TIMER=1 HARNESS_OPTIONS=c:j$NUMTHREADS

TEST_T0=$SECONDS
if [[ "$CLEANTEST" = "true" ]] ; then
  echo_err "$(tstamp) Running tests with plain \`make test\`"
  run_or_err "Prepare blib" "make pure_all"
  make test 2> >(tee "$TEST_STDERR_LOG")
else
  PROVECMD="prove -lrswj$NUMTHREADS t xt"
  echo_err "$(tstamp) running tests with \`$PROVECMD\`"
  $PROVECMD 2> >(tee "$TEST_STDERR_LOG")
fi
TEST_T1=$SECONDS

if [[ -z "$DBICTRACE" ]] && [[ -z "$POISON_ENV" ]] && [[ -s "$TEST_STDERR_LOG" ]] ; then
  STDERR_LOG_SIZE=$(wc -l < "$TEST_STDERR_LOG")

  echo
  echo "Test run produced $STDERR_LOG_SIZE lines of output on STDERR:"
  echo "============================================================="
  cat "$TEST_STDERR_LOG"
  echo "============================================================="
  echo "End of test run STDERR output ($STDERR_LOG_SIZE lines)"
  echo
fi

echo "$(tstamp) Testing took a total of $(( $TEST_T1 - $TEST_T0 ))s"
