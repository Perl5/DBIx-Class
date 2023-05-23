#!/bin/bash

# "autodie"
set -e

# FIXME: Work around travis IO capture bugs
# https://github.com/travis-ci/travis-ci/issues/8973
# https://github.com/travis-ci/travis-ci/issues/8920
perl -MFcntl -e 'fcntl( $_, F_SETFL, 0 ) for \*STDOUT, \*STDERR'

TEST_STDERR_LOG=/tmp/dbictest.stderr
TIMEOUT_CMD="/usr/bin/timeout --kill-after=16m --signal=TERM 15m"

echo_err() { echo "$@" 1>&2 ; }

if [[ "$TRAVIS" != "true" ]] ; then
  echo_err "Running this script makes no sense outside of travis-ci"
  exit 1
fi

tstamp() { echo -n "[$(date '+%H:%M:%S')]" ; }

CPAN_is_sane() { perl -MCPAN\ 1.94_56 -e 1 &>/dev/null ; }

CPAN_supports_BUILDPL() { perl -MCPAN\ 1.9205 -e1 &>/dev/null; }

ASan_enabled() { perl -V:config_args | grep -q fsanitize=address ; }

ci_vm_state_text() {
  echo "
========================== CI System information ============================

= CPUinfo
$(perl -0777 -p -e 's/.+\n\n(?!\z)//s' < /proc/cpuinfo)

= Meminfo
$(free -m -t)

= Diskinfo
$(df -h)

$(mount | grep '^/')

= Kernel info
$(uname -a)

= Network Configuration
$(ip addr)

= Network Sockets Status
$( (sudo netstat -an46p || netstat -an46p) | grep -Pv '\s(CLOSING|(FIN|TIME|CLOSE)_WAIT.?|LAST_ACK)\s')

= Processlist
$(ps fuxa)

= Environment
$(env | grep -P 'TEST|HARNESS|MAKE|TRAVIS|PERL|DBIC|PATH|SHELL' | LC_ALL=C sort | cat -v)

= Perl in use
$(perl -V)
============================================================================="
}

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
      if [[ "$(dmesg)" =~ $( echo "\\bOOM\\b" ) ]] ; then
        echo_err "=== dmesg ringbuffer"
        echo_err "$(dmesg)"
      fi
    fi

    return $LASTEXIT
  else
    echo_err "done (took ${DELTA_TIME}s)"
  fi
}

apt_install() {
  # flatten
  pkgs="$@"

  run_or_err "Installing APT packages: $pkgs" "sudo apt-get install --allow-unauthenticated  --no-install-recommends -y $pkgs"
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
  MODLIST="$(printf '%s\n' "$@" | sort -R)"

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
      | xargs -d '\\n' -n 1 -P $VCPU_USE bash -c \\
        'OUT=\$(maint/getstatus $TIMEOUT_CMD cpanm --notest \"\$@\" 2>&1 ) || (LASTEXIT=\$?; echo \"\$OUT\"; exit \$LASTEXIT)' \\
        'giant space monkey penises'
    "
}

export -f parallel_installdeps_notest run_or_err echo_err tstamp ASan_enabled CPAN_is_sane CPAN_supports_BUILDPL

installdeps() {
  if [[ -z "$@" ]] ; then return; fi

  MODLIST=$(printf "%q " "$@" | perl -pe 's/^\s+|\s+$//g')

  local -x HARNESS_OPTIONS

  HARNESS_OPTIONS="j$VCPU_USE"

  if ! run_or_err "Attempting install of $# modules under parallel ($HARNESS_OPTIONS) testing ($MODLIST)" "_dep_inst_with_test $MODLIST" quiet_fail ; then
    local errlog="failed after ${DELTA_TIME}s Exit:$LASTEXIT Log:$(/usr/bin/perl /usr/bin/nopaste -q -s Shadowcat -d "Parallel testfail" <<< "$LASTOUT")"
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
    $LASTCMD 2>&1 || return 1

  else
    LASTCMD="$TIMEOUT_CMD cpan $@"
    $LASTCMD 2>&1 || return 1

    # older perls do not have a CPAN which can exit with error on failed install
    for m in "$@"; do
      if ! perl -e '

$ARGV[0] =~ s/-TRIAL\.//;

my $mod = (
  # abuse backtrack
  $ARGV[0] =~ m{ / .*? ( [^/]+ ) $ }x
    ? do { my @p = split (/\-/, $1); pop @p; join "::", @p }
    : $ARGV[0]
);

# map some install-names to a module/version combo
# serves both as a grandfathered title-less tarball, and
# as a minimum version check for upgraded core modules
my $eval_map = {

  # this is temporary, will need something more robust down the road
  # (perhaps by then Module::CoreList will be dep-free)
  "Module::Build" => { ver => "0.4214" },
  "podlators" => { mod => "Pod::Man", ver => "2.17" },

  "File::Spec" => { ver => "3.47" },
  "Cwd" => { ver => "3.47" },

  "List::Util" => { ver => "1.42" },
  "Scalar::Util" => { ver => "1.42" },
  "Scalar::List::Utils" => { mod => "List::Util", ver => "1.42" },
};

my $m = $eval_map->{$mod}{mod} || $mod;

eval(
  "require $m"

  .

  ($eval_map->{$mod}{ver}
    ? "; $m->VERSION(\$eval_map->{\$mod}{ver}) "
    : ""
  )

  .

  "; 1"
)
  or
( print $@ and exit 1)

      ' "$m" 2> /dev/null ; then
        echo -e "$m installation seems to have failed"
        return 1
      fi
    done
  fi
}

# Idea stolen from
# https://github.com/kentfredric/Dist-Zilla-Plugin-Prereqs-MatchInstalled-All/blob/master/maint-travis-ci/sterilize_env.pl
# Only works on 5.12+ (where sitelib was finally properly fixed)
purge_sitelib() {
  echo_err "$(tstamp) Sterilizing the Perl installation (cleaning up sitelib)"

  if perl -M5.012 -e1 &>/dev/null ; then

    perl -M5.012 -MConfig -MFile::Find -e '
      my $sitedirs = {
        map { $Config{$_} => 1 }
          grep { $_ =~ /site(lib|arch)exp$/ }
            keys %Config
      };
      find({ bydepth => 1, no_chdir => 1, follow_fast => 1, wanted => sub {
        ! $sitedirs->{$_} and ( -d _ ? rmdir : unlink )
      } }, keys %$sitedirs )
    '
  fi
}
