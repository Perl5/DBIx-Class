#!/bin/bash

if [[ "${BASH_SOURCE[0]}" == "${0}" ]] ; then
  echo "This script can not be executed standalone - it can only be source()d" 1>&2
  exit 1
fi

if [[ -n "$SHORT_CIRCUIT_SMOKE" ]] ; then return ; fi

# we need a mirror that both has the standard index and a backpan version rolled
# into one, due to MDV testing
export CPAN_MIRROR="http://cpan.metacpan.org/"

PERL_CPANM_OPT="$PERL_CPANM_OPT --mirror $CPAN_MIRROR"

# do not set PERLBREW_CPAN_MIRROR - not all backpan-like mirrors have the perl tarballs
export PERL_MM_USE_DEFAULT=1 PERL_MM_NONINTERACTIVE=1 PERL_AUTOINSTALL_PREFER_CPAN=1 HARNESS_TIMER=1 MAKEFLAGS="-j$VCPU_USE"

# try CPAN's latest offering if requested
if [[ "$DEVREL_DEPS" == "true" ]] ; then

  PERL_CPANM_OPT="$PERL_CPANM_OPT --dev"

fi

# Fixup CPANM_OPT to behave more like a traditional cpan client
export PERL_CPANM_OPT="--verbose --no-interactive --no-man-pages $( echo $PERL_CPANM_OPT | sed 's/--skip-satisfied//' )"

if [[ -n "$BREWVER" ]] ; then

  # since perl 5.14 a perl can safely be built concurrently with -j$large
  # (according to brute force testing and my power bill)
  if [[ "$BREWVER" =~ [A-Za-z] ]] || perl -Mversion -e "exit !!(version->new(q($BREWVER)) < 5.014)" ; then
    perlbrew_jopt="$VCPU_USE"
  fi

  BREWSRC="$BREWVER"

  if is_cperl; then
    if [[ "$BREWVER" == "cperl-master" ]] ; then
      git clone --single-branch --depth=1 --branch=master https://github.com/perl11/cperl /tmp/cperl-master
      BREWSRC="/tmp/cperl-master"
    else
      # FFS perlbrew ( see http://wollmers-perl.blogspot.de/2015/10/install-cperl-with-perlbrew.html )
      wget -qO- https://github.com/perl11/cperl/archive/$BREWVER.tar.gz > /tmp/cperl-$BREWVER.tar.gz
      BREWSRC="/tmp/cperl-$BREWVER.tar.gz"
    fi
  elif [[ "$BREWVER" == "schmorp_stableperl" ]] ; then
    BREWSRC="http://stableperl.schmorp.de/dist/stableperl-5.22.0-1.001.tar.gz"
  fi

  run_or_err "Compiling/installing Perl $BREWVER (without testing, using ${perlbrew_jopt:-1} threads, may take up to 5 minutes)" \
    "perlbrew install --as $BREWVER --notest --noman --verbose $BREWOPTS -j${perlbrew_jopt:-1}  $BREWSRC"

  # FIXME work around https://github.com/perl11/cperl/issues/144
  # (still affecting 5.22.3)
  if is_cperl && ! [[ -f ~/perl5/perlbrew/perls/$BREWVER/bin/perl ]] ; then
    ln -s ~/perl5/perlbrew/perls/$BREWVER/bin/cperl ~/perl5/perlbrew/perls/$BREWVER/bin/perl || /bin/true
  fi

  # can not do 'perlbrew use' in the run_or_err subshell above, or a $()
  # furthermore some versions of `perlbrew use` return 0 regardless of whether
  # the perl is found (won't be there unless compilation suceeded, wich *ALSO* returns 0)
  perlbrew use $BREWVER || /bin/true

  if \
    ! [[ -x ~/perl5/perlbrew/perls/$BREWVER/bin/perl ]] \
  ||  [[ "$( perlbrew use | grep -oP '(?<=Currently using ).+' )" != "$BREWVER" ]]
  then
    echo_err "Unable to switch to $BREWVER - compilation failed...?"
    echo_err "$LASTOUT"
    exit 1
  fi

# no brewver - this means a travis perl, which means we want to clean up
# the presently installed libs
elif [[ "$CLEANTEST" == "true" ]] && [[ "$POISON_ENV" != "true" ]] ; then
  purge_sitelib
fi

if [[ "$POISON_ENV" = "true" ]] ; then
  # create a perlbrew-specific local lib
  perlbrew lib create travis-local
  perlbrew use "$( perlbrew use | grep -oP '(?<=Currently using ).+' )@travis-local"
  echo_err "POISON_ENV active - adding a local lib: $(perlbrew use)"
fi

# configure CPAN.pm - older versions go into an endless loop
# when trying to autoconf themselves
CPAN_CFG_SCRIPT="
  require CPAN;
  require CPAN::FirstTime;
  *CPAN::FirstTime::conf_sites = sub {};
  CPAN::Config->load;
  \$CPAN::Config->{urllist} = [qw{ $CPAN_MIRROR }];
  \$CPAN::Config->{halt_on_failure} = $( is_cperl && echo -n 0 || echo -n 1 );
  CPAN::Config->commit;
"
run_or_err "Configuring CPAN.pm" "perl -e '$CPAN_CFG_SCRIPT'"


# These envvars are always set, more *maybe* below
export DBIC_SHUFFLE_UNORDERED_RESULTSETS=1

# bogus nonexisting DBI_*
export DBI_DSN="dbi:ODBC:server=NonexistentServerAddress"
export DBI_DRIVER="ADO"

# some people do in fact set this - boggle!!!
# it of course won't work before 5.8.4
if perl -M5.008004 -e 1 &>/dev/null ; then
  export PERL_STRICTURES_EXTRA=1
fi


# poison the environment
if [[ "$POISON_ENV" = "true" ]] ; then

  toggle_vars=( MVDT )

  [[ "$CLEANTEST" == "true" ]] && toggle_vars+=( BREAK_CC )

  for var in "${toggle_vars[@]}"  ; do
    if [[ -z "${!var}" ]] ; then
      export $var=true
      echo "POISON_ENV: setting $var to 'true'"
    fi
  done

  # look through lib, find all mentioned DBIC* ENVvars and set them to true and see if anything explodes
  toggle_booleans=( $( grep -ohP '\bDBIC_[0-9_A-Z]+' -r lib/ --exclude-dir Optional | sort -u | grep -vP '^(DBIC_TRACE(_PROFILE)?|DBIC_.+_DEBUG)$' ) )

  # some extra pollutants
  toggle_booleans+=( \
    DBICTEST_ASSERT_NO_SPURIOUS_EXCEPTION_ACTION \
    DBICTEST_SQLITE_USE_FILE \
    DBICTEST_RUN_ALL_TESTS \
    DBICTEST_SQLITE_REVERSE_DEFAULT_ORDER \
  )

  # if we have Moose - try to run everything under replicated
  # FIXME - when switching to Moo kill this
  if [[ "$CLEANTEST" != "true" ]] && perl -M5.008003 -e 1 &>/dev/null ; then
    toggle_booleans+=( DBICTEST_VIA_REPLICATED )
  fi

  for var in "${toggle_booleans[@]}"
  do
    if [[ -z "${!var}" ]] ; then
      export $var=1
      echo "POISON_ENV: setting $var to 1"
    fi
  done

  echo "POISON_ENV: setting PERL_UNICODE=SAD"
  export PERL_UNICODE=SAD


### emulate a local::lib-like env

  # trick cpanm into executing true as shell - we just need the find+unpack
  run_or_err "Downloading latest stable DBIC from CPAN" \
    "SHELL=/bin/true cpanm --look DBIx::Class"

  # move it somewhere as following cpanm will clobber it
  run_or_err "Moving latest stable DBIC from CPAN to /tmp" "mv ~/.cpanm/latest-build/DBIx-Class-*/lib /tmp/stable_dbic_lib"

  export PERL5LIB="/tmp/stable_dbic_lib:$PERL5LIB"

  # perldoc -l <mod> searches $(pwd)/lib in addition to PERL5LIB etc, hence the cd /
  echo_err "Latest stable DBIC (without deps) locatable via \$PERL5LIB at $(cd / && perldoc -l DBIx::Class)"
fi

if [[ "$CLEANTEST" != "true" ]] ; then
  # using SQLT if will be available
  # not doing later because we will be running in a subshell
  export DBICTEST_SQLT_DEPLOY=1

fi

# FIXME - work around https://github.com/miyagawa/cpanminus/issues/462
# seriously...
perl -p -i -e 's/\blocal\$self->\{notest\}=1;//' $(which cpanm)
