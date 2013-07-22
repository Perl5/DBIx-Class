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

  # throw away non-children (what was in $@), throw away ascii art, convert to modnames
  perl -p -e 's/^[a-z].+//i; s/^[^a-z]+//i; s/\-[^\-]+$/ /; s/\-/::/g' <<< "$OUT"
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


CPAN_is_sane() { perl -MCPAN\ 1.94_56 -e 1 &>/dev/null ; }
