#!/bin/bash

if [[ -n "$SHORT_CIRCUIT_SMOKE" ]] ; then return ; fi

# we need a mirror that both has the standard index and a backpan version rolled
# into one, due to MDV testing
CPAN_MIRROR="http://cpan.metacpan.org/"

PERL_CPANM_OPT="$PERL_CPANM_OPT --mirror $CPAN_MIRROR"

# do not set PERLBREW_CPAN_MIRROR - not all backpan-like mirrors have the perl tarballs
export PERL_MM_USE_DEFAULT=1 PERL_MM_NONINTERACTIVE=1 PERL_AUTOINSTALL_PREFER_CPAN=1 HARNESS_TIMER=1 MAKEFLAGS="-j$NUMTHREADS"

# try CPAN's latest offering if requested
if [[ "$DEVREL_DEPS" == "true" ]] ; then

  PERL_CPANM_OPT="$PERL_CPANM_OPT --dev"

fi

# Fixup CPANM_OPT to behave more like a traditional cpan client
export PERL_CPANM_OPT="--verbose --no-interactive --no-man-pages $( echo $PERL_CPANM_OPT | sed 's/--skip-satisfied//' )"

if [[ -n "$BREWVER" ]] ; then
  # since perl 5.14 a perl can safely be built concurrently with -j$large
  # (according to brute force testing and my power bill)
  if [[ "$BREWVER" == "blead" ]] || perl -Mversion -e "exit !!(version->new(q($BREWVER)) < 5.014)" ; then
    perlbrew_jopt="$NUMTHREADS"
  fi

  run_or_err "Compiling/installing Perl $BREWVER (without testing, using ${perlbrew_jopt:-1} threads, may take up to 5 minutes)" \
    "perlbrew install --as $BREWVER --notest --noman --verbose $BREWOPTS -j${perlbrew_jopt:-1}  $BREWVER"

  # can not do 'perlbrew uss' in the run_or_err subshell above, or a $()
  # furthermore `perlbrew use` returns 0 regardless of whether the perl is
  # found (won't be there unless compilation suceeded, wich *ALSO* returns 0)
  perlbrew use $BREWVER

  if [[ "$( perlbrew use | grep -oP '(?<=Currently using ).+' )" != "$BREWVER" ]] ; then
    echo_err "Unable to switch to $BREWVER - compilation failed...?"
    echo_err "$LASTOUT"
    exit 1
  fi

# no brewver - this means a travis perl, which means we want to clean up
# the presently installed libs
# Idea stolen from
# https://github.com/kentfredric/Dist-Zilla-Plugin-Prereqs-MatchInstalled-All/blob/master/maint-travis-ci/sterilize_env.pl
# Only works on 5.12+ (where sitelib was finally properly fixed)
elif [[ "$CLEANTEST" == "true" ]] && [[ "$POISON_ENV" != "true" ]] && perl -M5.012 -e 1 &>/dev/null ; then

  echo_err "$(tstamp) Cleaning precompiled Travis-Perl"
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

  echo_err "Post-cleanup contents of sitelib of the pre-compiled Travis-Perl $TRAVIS_PERL_VERSION:"
  echo_err "$(tree $(perl -MConfig -e 'print $Config{sitelib_stem}'))"
  echo_err
fi

# configure CPAN.pm - older versions go into an endless loop
# when trying to autoconf themselves
CPAN_CFG_SCRIPT="
  require CPAN;
  require CPAN::FirstTime;
  *CPAN::FirstTime::conf_sites = sub {};
  CPAN::Config->load;
  \$CPAN::Config->{urllist} = [qw{ $CPAN_MIRROR }];
  \$CPAN::Config->{halt_on_failure} = 1;
  CPAN::Config->commit;
"
run_or_err "Configuring CPAN.pm" "perl -e '$CPAN_CFG_SCRIPT'"

# poison the environment
if [[ "$POISON_ENV" = "true" ]] ; then

  # in addition to making sure tests do not rely on implicid order of
  # returned results, look through lib, find all mentioned ENVvars and
  # set them to true and see if anything explodes
  for var in \
    DBICTEST_SQLITE_REVERSE_DEFAULT_ORDER \
    $( grep -P '\$ENV\{' -r lib/ --exclude-dir Optional | grep -oP '\bDBIC\w+' | sort -u | grep -vP '^(DBIC_TRACE(_PROFILE)?|DBIC_.+_DEBUG)$' )
  do
    if [[ -z "${!var}" ]] ; then
      export $var=1
      echo "POISON_ENV: setting $var to 1"
    fi
  done

  # bogus nonexisting DBI_*
  export DBI_DSN="dbi:ODBC:server=NonexistentServerAddress"
  export DBI_DRIVER="ADO"

  # some people do in fact set this - boggle!!!
  # it of course won't work before 5.8.4
  if perl -M5.008004 -e 1 &>/dev/null ; then
    export PERL_STRICTURES_EXTRA=1
  fi

  # emulate a local::lib-like env
  # trick cpanm into executing true as shell - we just need the find+unpack
  run_or_err "Downloading latest stable DBIC from CPAN" \
    "SHELL=/bin/true cpanm --look DBIx::Class"

  export PERL5LIB="$( ls -d ~/.cpanm/latest-build/DBIx-Class-*/lib | tail -n1 ):$PERL5LIB"

  # perldoc -l <mod> searches $(pwd)/lib in addition to PERL5LIB etc, hence the cd /
  echo_err "Latest stable DBIC (without deps) locatable via \$PERL5LIB at $(cd / && perldoc -l DBIx::Class)"

fi

if [[ "$CLEANTEST" != "true" ]] ; then
  # using SQLT if will be available
  # not doing later because we will be running in a subshell
  export DBICTEST_SQLT_DEPLOY=1

fi
