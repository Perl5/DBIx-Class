#!/bin/bash

# this file is executed in a subshell - set up the common stuff
source maint/travis-ci_scripts/common.bash

if [[ -n "$SHORT_CIRCUIT_SMOKE" ]] ; then exit 0 ; fi

run_harness_tests() {
  local -x HARNESS_OPTIONS=c:j$VCPU_USE
  if [[ "$VCPU_USE" == 1 ]] ; then
    ulim=$(( ( $(ps xH | wc -l) - 3 ) + 4 )) # (real count excluding header + ps + wc) + space for ( make + tee + harness + <actual test> )
    echo_err "$(tstamp) Setting process/thread limit to $ulim"
    ulimit -u $ulim
    sleep 5 # needed to settle things down a bit
  fi
  make test 2> >(tee "$TEST_STDERR_LOG")
}

# announce everything we have on this box
TRAVIS="" perl -Ilib t/00describe_environment.t >/dev/null

TEST_T0=$SECONDS
if [[ "$CLEANTEST" = "true" ]] ; then
  echo_err "$(tstamp) Running tests with plain \`make test\`"
  run_or_err "Prepare blib" "make pure_all"
  run_harness_tests
else
  PROVECMD="prove -lrswTj$VCPU_USE xt t"

  # List every single SKIP/TODO when they are visible
  if [[ "$VCPU_USE" == 1 ]] ; then
    PROVECMD="$PROVECMD --directives"
  fi

  echo_err "$(tstamp) running tests with \`$PROVECMD\`"
  $PROVECMD 2> >(tee "$TEST_STDERR_LOG")
fi
TEST_T1=$SECONDS

if \
   [[ -z "$DBIC_TRACE" ]] \
&& [[ -z "$DBIC_MULTICREATE_DEBUG" ]] \
&& [[ -z "$DBICTEST_DEBUG_CONCURRENCY_LOCKS" ]] \
&& [[ -z "$DBICTEST_VERSION_WARNS_INDISCRIMINATELY" ]] \
&& [[ -s "$TEST_STDERR_LOG" ]] ; then
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
  echo "$(tstamp) Full dep install log at $(/usr/bin/perl /usr/bin/nopaste -q -s Shadowcat -d DepInstall <<< "$INSTALLDEPS_OUT")"
fi
echo
