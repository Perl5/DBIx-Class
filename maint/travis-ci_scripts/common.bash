#!/bin/bash

set -e

TEST_STDERR_LOG=/tmp/dbictest.stderr
TIMEOUT_CMD="/usr/bin/timeout --kill-after=9.5m --signal=TERM 9m"

echo_err() { echo "$@" 1>&2 ; }

if [[ "$TRAVIS" != "true" ]] ; then
  echo_err "Running this script makes no sense outside of travis-ci"
  exit 1
fi

tstamp() { echo -n "[$(date '+%H:%M:%S')]" ; }

run_or_err() {
  echo_err -n "$(tstamp) $1 ... "

  LASTCMD="$2"
  LASTEXIT=0
  START_TIME=$SECONDS

  PRMETER_PIDFILE="$(tempfile)_$SECONDS"
  # the double bash is to hide the job control messages
  bash -c "bash -c 'echo \$\$ >> $PRMETER_PIDFILE; while true; do sleep 10; echo -n \"\${SECONDS}s ... \"; done' &"

  LASTOUT=$( eval "$2" 2>&1 ) || LASTEXIT=$?

  # stop progress meter
  for p in $(cat "$PRMETER_PIDFILE"); do kill $p ; done

  DELTA_TIME=$(( $SECONDS - $START_TIME ))

  if [[ "$LASTEXIT" != "0" ]] ; then
    if [[ -z "$3" ]] ; then
      echo_err "FAILED !!! (after ${DELTA_TIME}s)"
      echo_err "Command executed:"
      echo_err "$LASTCMD"
      echo_err "STDOUT+STDERR:"
      echo_err "$LASTOUT"
    fi

    return $LASTEXIT
  else
    echo_err "done (took ${DELTA_TIME}s)"
  fi
}

apt_install() {
  # flatten
  pkgs="$@"

  # Need to do this at every step, the sources list may very well have changed
  run_or_err "Updating APT available package list" "sudo apt-get update"

  run_or_err "Installing Debian APT packages: $pkgs" "sudo apt-get install --allow-unauthenticated  --no-install-recommends -y $pkgs"
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
  ERR=${COMBINED_OUT%!!!STDERRSTDOUTSEPARATOR!!!*}

  if [[ "$LASTEXIT" != "0" ]] ; then
    echo_err "Error occured (exit code $LASTEXIT) retrieving dependencies of $@:"
    echo_err "$ERR"
    echo_err "$OUT"
    exit 1
  fi

  # throw away warnings, up-to-date diag, ascii art, convert to modnames
  PQ=$(perl -p -e '
    s/^.*?is up to date.*$//;
    s/^\!.*//;
    s/^[^a-z]+//i;
    s/\-[^\-]+$/ /; # strip version part
    s/\-/::/g
  ' <<< "$OUT")

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

  # We want to trap the output of each process and serially append them to
  # each other as opposed to just dumping a jumbled up mass-log that would
  # need careful unpicking by a human
  #
  # While cpanm does maintain individual buildlogs in more recent versions,
  # we are not terribly interested in trying to figure out which log is which
  # dist. The verbose-output + trap STDIO technique is vastly superior in this
  # particular case
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
        'OUT=\$($TIMEOUT_CMD cpanm --notest \"\$@\" 2>&1 ) || (LASTEXIT=\$?; echo \"\$OUT\"; exit \$LASTEXIT)' \\
        'giant space monkey penises'
    "
}

installdeps() {
  if [[ -z "$@" ]] ; then return; fi

  MODLIST=$(printf "%q " "$@" | perl -pe 's/^\s+|\s+$//g')

  local -x HARNESS_OPTIONS

  HARNESS_OPTIONS="j$NUMTHREADS"

  if ! run_or_err "Attempting install of $# modules under parallel ($HARNESS_OPTIONS) testing ($MODLIST)" "_dep_inst_with_test $MODLIST" quiet_fail ; then
    local errlog="failed after ${DELTA_TIME}s Exit:$LASTEXIT Log:$(/usr/bin/nopaste -q -s Shadowcat -d "Parallel testfail" <<< "$LASTOUT")"
    echo "$errlog"

    POSTMORTEM="$POSTMORTEM$(
      echo
      echo "Depinstall of $MODLIST under $HARNESS_OPTIONS parallel testing $errlog"
    )"

    HARNESS_OPTIONS=""
    run_or_err "Retrying same $# modules without parallel testing" "_dep_inst_with_test $MODLIST"
  fi

  INSTALLDEPS_OUT="${INSTALLDEPS_OUT}${LASTOUT}"
}

_dep_inst_with_test() {
  if [[ "$DEVREL_DEPS" == "true" ]] ; then
    # --dev is already part of CPANM_OPT
    LASTCMD="$TIMEOUT_CMD cpanm $@"
    $LASTCMD 2>&1
  else
    LASTCMD="$TIMEOUT_CMD cpan $@"
    $LASTCMD 2>&1

    # older perls do not have a CPAN which can exit with error on failed install
    for m in "$@"; do
      if ! perl -e '

my $mod = (
  $ARGV[0] =~ m{ \/ .*? ([^\/]+) $ }x
    ? do { my @p = split (/\-/, $1); pop @p; join "::", @p }
    : $ARGV[0]
);

$mod = q{List::Util} if $mod eq q{Scalar::List::Utils};

eval qq{require($mod)} or ( print $@ and exit 1)

      ' "$m" 2> /dev/null ; then
        echo -e "$m installation seems to have failed"
        return 1
      fi
    done
  fi
}

CPAN_is_sane() { perl -MCPAN\ 1.94_56 -e 1 &>/dev/null ; }

CPAN_supports_BUILDPL() { perl -MCPAN\ 1.9205 -e1 &>/dev/null; }
