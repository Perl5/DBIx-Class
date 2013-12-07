#!/bin/bash

set -e

TEST_STDERR_LOG=/tmp/dbictest.stderr

echo_err() { echo "$@" 1>&2 ; }

if [[ "$TRAVIS" != "true" ]] ; then
  echo_err "Running this script makes no sense outside of travis-ci"
  exit 1
fi

tstamp() { echo -n "[$(date '+%H:%M:%S')]" ; }

run_or_err() {
  echo_err -n "$(tstamp) $1 ... "

  LASTEXIT=0
  START_TIME=$SECONDS
  LASTOUT=$( bash -c "$2" 2>&1 ) || LASTEXIT=$?
  DELTA_TIME=$(( $SECONDS - $START_TIME ))

  if [[ "$LASTEXIT" != "0" ]] ; then
    echo_err "FAILED !!! (after ${DELTA_TIME}s)"
    echo_err "Command executed:"
    echo_err "$2"
    echo_err "STDOUT+STDERR:"
    echo_err "$LASTOUT"

    return $LASTEXIT
  else
    echo_err "done (took ${DELTA_TIME}s)"
  fi
}

extract_prereqs() {
  # once --verbose is set, --no-verbose can't disable it
  # do this by hand
  local PERL_CPANM_OPT="$( echo $PERL_CPANM_OPT | sed 's/--verbose\s*//' )"

  # hack-hack-hack
  LASTEXIT=0
  COMBINED_OUT="$( { stdout="$(cpanm --quiet --scandeps --format tree "$@")" ; } 2>&1; echo "!!!STDERRSTDOUTSEPARATOR!!!$stdout")" \
    || LASTEXIT=$?

  OUT=${COMBINED_OUT#*!!!STDERRSTDOUTSEPARATOR!!!}
  ERR=$(grep -v " is up to date." <<< "${COMBINED_OUT%!!!STDERRSTDOUTSEPARATOR!!!*}")

  if [[ "$LASTEXIT" != "0" ]] ; then
    echo_err "Error occured (exit code $LASTEXIT) retrieving dependencies of $@:"
    echo_err "$ERR"
    echo_err "$OUT"
    exit 1
  fi

  # throw away warnings, ascii art, convert to modnames
  PQ=$(perl -p -e 's/^\!.*//; s/^[^a-z]+//i; s/\-[^\-]+$/ /; s/\-/::/g' <<< "$OUT")

  # throw away what was in $@
  for m in "$@" ; do
    PQ=$( perl -p -e 's/(?:\s|^)\Q'"$m"'\E(?:\s|$)/ /mg' <<< "$PQ")
  done

  # RV
  echo "$PQ"
}

parallel_installdeps_notest() {
  if [[ -z "$@" ]] ; then return; fi

  # one module spec per line
  MODLIST="$(printf '%s\n' "$@")"

  # The reason we do things so "non-interactively" is that xargs -P will have the
  # latest cpanm instance overwrite the buildlog. There seems to be no way to
  # specify a custom buildlog, hence we just collect the verbose output
  # and display it in case of "worker" failure
  #
  # Explanation of inline args:
  #
  # [09:38] <T> you need a $0
  # [09:38] <G> hence the _
  # [09:38] <G> bash -c '...' _
  # [09:39] <T> I like -- because it's the magic that gnu getopts uses for somethign else
  # [09:39] <G> or --, yes
  # [09:39] <T> ribasushi: you could put "giant space monkey penises" instead of "--" and it would work just as well
  #
  run_or_err "Installing (without testing) $(echo $MODLIST)" \
    "echo \\
\"$MODLIST\" \\
      | xargs -d '\\n' -n 1 -P $NUMTHREADS bash -c \\
        'OUT=\$(cpanm --notest --no-man-pages \"\$@\" 2>&1 ) || (LASTEXIT=\$?; echo \"\$OUT\"; exit \$LASTEXIT)' \\
        'giant space monkey penises'
    "
}

installdeps() {
  if [[ -z "$@" ]] ; then return; fi

  echo_err "$(tstamp) Processing dependencies: $@"

  local -x HARNESS_OPTIONS

  HARNESS_OPTIONS="j$NUMTHREADS"

  echo_err -n "Attempting install of $# modules under parallel ($HARNESS_OPTIONS) testing ... "

  LASTEXIT=0
  START_TIME=$SECONDS
  LASTOUT=$( cpan_inst "$@" ) || LASTEXIT=$?
  DELTA_TIME=$(( $SECONDS - $START_TIME ))

  if [[ "$LASTEXIT" = "0" ]] ; then
    echo_err "done (took ${DELTA_TIME}s)"
  else
    local errlog="after ${DELTA_TIME}s Exit:$LASTEXIT Log:$(/usr/bin/nopaste -q -s Shadowcat -d "Parallel installfail" <<< "$LASTOUT")"
    echo_err -n "failed ($errlog) retrying with sequential testing ... "
    POSTMORTEM="$POSTMORTEM$(
      echo
      echo "Depinstall under $HARNESS_OPTIONS parallel testing failed $errlog"
      echo "============================================================="
      echo "Attempted installation of: $@"
      echo "============================================================="
    )"

    HARNESS_OPTIONS=""
    LASTEXIT=0
    START_TIME=$SECONDS
    LASTOUT=$( cpan_inst "$@" ) || LASTEXIT=$?
    DELTA_TIME=$(( $SECONDS - $START_TIME ))

    if [[ "$LASTEXIT" = "0" ]] ; then
      echo_err "done (took ${DELTA_TIME}s)"
    else
      echo_err "FAILED !!! (after ${DELTA_TIME}s)"
      echo_err "STDOUT+STDERR:"
      echo_err "$LASTOUT"
      exit 1
    fi
  fi

  INSTALLDEPS_OUT="${INSTALLDEPS_OUT}${LASTOUT}"
}

cpan_inst() {
  /usr/bin/timeout --kill-after=9.5m --signal=TERM 9m cpan "$@" 2>&1

  # older perls do not have a CPAN which can exit with error on failed install
  for m in "$@"; do
    if ! perl -e '

eval ( q{require } . (
  $ARGV[0] =~ m{ \/ .*? ([^\/]+) $ }x
    ? do { my @p = split (/\-/, $1); pop @p; join "::", @p }
    : $ARGV[0]
) ) or ( print $@ and exit 1)' "$m" 2> /dev/null ; then

      echo -e "$m installation seems to have failed"
      return 1
    fi
  done
}

CPAN_is_sane() { perl -MCPAN\ 1.94_56 -e 1 &>/dev/null ; }

CPAN_supports_BUILDPL() { perl -MCPAN\ 1.9205 -e1 &>/dev/null; }
