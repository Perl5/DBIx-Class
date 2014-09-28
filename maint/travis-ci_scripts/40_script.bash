#!/bin/bash

if [[ -n "$SHORT_CIRCUIT_SMOKE" ]] ; then return ; fi

run_harness_tests() {
  local -x HARNESS_OPTIONS=c:j$NUMTHREADS
  make test 2> >(tee "$TEST_STDERR_LOG")
}

TEST_T0=$SECONDS
if [[ "$CLEANTEST" = "true" ]] ; then
  echo_err "$(tstamp) Running tests with plain \`make test\`"
  run_or_err "Prepare blib" "make pure_all"
  run_harness_tests
else
  PROVECMD="prove -lrswj$NUMTHREADS xt t"

  # FIXME - temporary, until Package::Stash is fixed
  if perl -M5.010 -e 1 &>/dev/null ; then
    PROVECMD="$PROVECMD -T"
  fi

  echo_err "$(tstamp) running tests with \`$PROVECMD\`"
  $PROVECMD 2> >(tee "$TEST_STDERR_LOG")
fi
TEST_T1=$SECONDS

if [[ -z "$DBICTRACE" ]] && [[ -z "$POISON_ENV" ]] && [[ -s "$TEST_STDERR_LOG" ]] ; then
  STDERR_LOG_SIZE=$(wc -l < "$TEST_STDERR_LOG")

  # prepend STDERR log
  POSTMORTEM="$(
    echo
    echo "Test run produced $STDERR_LOG_SIZE lines of output on STDERR:"
    echo "============================================================="
    cat "$TEST_STDERR_LOG"
    echo "============================================================="
    echo "End of test run STDERR output ($STDERR_LOG_SIZE lines)"
    echo
    echo
  )$POSTMORTEM"
fi

echo
echo "${POSTMORTEM:- \o/ No notable smoke run issues \o/ }"
echo
echo "$(tstamp) Testing took a total of $(( $TEST_T1 - $TEST_T0 ))s"
if [[ -n "$INSTALLDEPS_OUT" ]] ; then
  echo "$(tstamp) Full dep install log at $(/usr/bin/nopaste -q -s Shadowcat -d DepInstall <<< "$INSTALLDEPS_OUT")"
fi
echo
