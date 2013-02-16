#!/bin/bash

source maint/travis-ci_scripts/common.bash
if [[ -n "$SHORT_CIRCUIT_SMOKE" ]] ; then return ; fi

TRAVIS_CPAN_MIRROR=$(echo "$PERL_CPANM_OPT" | grep -oP -- '--mirror\s+\S+' | head -n 1 | cut -d ' ' -f 2)
if ! [[ "$TRAVIS_CPAN_MIRROR" =~ "http://" ]] ; then
  echo_err "Unable to extract primary cpan mirror from PERL_CPANM_OPT - something is wrong"
  echo_err "PERL_CPANM_OPT: $PERL_CPANM_OPT"
  exit 1
fi

export PERL_MM_USE_DEFAULT=1 PERL_MM_NONINTERACTIVE=1 PERL_AUTOINSTALL_PREFER_CPAN=1 PERLBREW_CPAN_MIRROR="$TRAVIS_CPAN_MIRROR"

# Fixup CPANM_OPT to behave more like a traditional cpan client
export PERL_CPANM_OPT="$( echo $PERL_CPANM_OPT | sed 's/--skip-satisfied//' ) --verbose --no-interactive"

if [[ -n "$BREWVER" ]] ; then
  run_or_err "Compiling/installing Perl $BREWVER (without testing, may take up to 5 minutes)" \
    "perlbrew install --as $BREWVER --notest --verbose $BREWOPTS -j 2  $BREWVER"

  # can not do 'perlbrew uss' in the run_or_err subshell above
  perlbrew use $BREWVER || \
    ( echo_err -e "Unable to switch to $BREWVER - compillation failed?\n$LASTOUT"; exit 1 )
fi

# configure CPAN.pm - older versions go into an endless loop
# when trying to autoconf themselves
CPAN_CFG_SCRIPT="
  require CPAN;
  require CPAN::FirstTime;
  *CPAN::FirstTime::conf_sites = sub {};
  CPAN::Config->load;
  \$CPAN::Config->{urllist} = [qw{ $TRAVIS_CPAN_MIRROR }];
  \$CPAN::Config->{halt_on_failure} = 1;
  CPAN::Config->commit;
"
run_or_err "Configuring CPAN.pm" "perl -e '$CPAN_CFG_SCRIPT'"
