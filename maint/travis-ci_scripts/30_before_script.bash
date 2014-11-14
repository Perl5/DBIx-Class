#!/bin/bash

# this file is executed in a subshell - set up the common stuff
source maint/travis-ci_scripts/common.bash

if [[ -n "$SHORT_CIRCUIT_SMOKE" ]] ; then exit 0 ; fi

# The prereq-install stage will not work with both POISON and DEVREL
# DEVREL wins
if [[ "$DEVREL_DEPS" = "true" ]] ; then
  export POISON_ENV=""
fi

# FIXME - this is a kludge in place of proper MDV testing. For the time
# being simply use the minimum versions of our DBI/DBDstack, to avoid
# fuckups like 0.08260 (went unnoticed for 5 months)
if [[ "$POISON_ENV" = "true" ]] ; then

  # use url-spec for DBI due to https://github.com/miyagawa/cpanminus/issues/328
  if [[ "$CLEANTEST" != "true" ]] || perl -M5.013003 -e1 &>/dev/null ; then
    # the fulltest may re-upgrade DBI, be conservative only on cleantests
    # earlier DBI will not compile without PERL_POLLUTE which was gone in 5.14
    parallel_installdeps_notest T/TI/TIMB/DBI-1.614.tar.gz
  else
    parallel_installdeps_notest T/TI/TIMB/DBI-1.57.tar.gz
  fi

  # Test both minimum DBD::SQLite and minimum BigInt SQLite
  # reverse the logic from above for this (low on full, higher on clean)
  if [[ "$CLEANTEST" = "true" ]]; then
    parallel_installdeps_notest DBD::SQLite@1.37
  else
    parallel_installdeps_notest DBD::SQLite@1.29
  fi

fi

if [[ "$CLEANTEST" = "true" ]]; then
  # get the last inc/ off cpan - we will get rid of MI
  # soon enough, but till then this will do
  # the point is to have a *really* clean perl (the ones
  # we build are guaranteed to be clean, without side
  # effects from travis preinstalls)

  # trick cpanm into executing true as shell - we just need the find+unpack
  [[ -d ~/.cpanm/latest-build/DBIx-Class-*/inc ]] || run_or_err "Downloading latest stable DBIC inc/ from CPAN" \
    "SHELL=/bin/true cpanm --look DBIx::Class"

  mv ~/.cpanm/latest-build/DBIx-Class-*/inc .

  # The first CPAN which is somewhat sane is around 1.94_56 (perl 5.12)
  # The problem is that the first sane version also brings a *lot* of
  # deps with it, notably things like YAML and HTTP::Tiny
  # The goal of CLEANTEST is to have as little extra stuff installed as
  # possible, mainly to catch "but X is perl core" mistakes
  # So instead we still use our stock (possibly old) CPAN, and add some
  # handholding

  if [[ "$DEVREL_DEPS" == "true" ]] ; then
    # We are not "quite ready" for SQLA 1.99, do not consider it
    #
    installdeps 'SQL::Abstract~<1.99'

  else

    if ! CPAN_is_sane ; then
      # no configure_requires - we will need the usual suspects anyway
      # without pre-installing these in one pass things like extract_prereqs won't work
      installdeps ExtUtils::MakeMaker ExtUtils::CBuilder Module::Build
    fi

    # FIXME - temporary until 1.46 comes out / RT#99747 is fixed
    # insufficient testing of 5.8.3, ned older DBD::SQlite, ribasushi--
    if ! perl -M5.008004 -e 1 &>/dev/null ; then
      installdeps DBI I/IS/ISHIGAKI/DBD-SQLite-1.42.tar.gz
    fi

  fi

else
  # we will be running all dbic tests - preinstall lots of stuff, run basic tests

  # do the preinstall in several passes to minimize amount of cross-deps installing
  # multiple times, and to avoid module re-architecture breaking another install
  # (e.g. once Carp is upgraded there's no more Carp::Heavy,
  # while a File::Path upgrade may cause a parallel EUMM run to fail)
  #
  parallel_installdeps_notest ExtUtils::MakeMaker
  parallel_installdeps_notest File::Path
  parallel_installdeps_notest Carp
  parallel_installdeps_notest Module::Build
  parallel_installdeps_notest File::Spec Data::Dumper Module::Runtime
  parallel_installdeps_notest Test::Exception Encode::Locale Test::Fatal
  parallel_installdeps_notest Test::Warn B::Hooks::EndOfScope Test::Differences HTTP::Status
  parallel_installdeps_notest Test::Pod::Coverage Test::EOL Devel::GlobalDestruction Sub::Name MRO::Compat Class::XSAccessor URI::Escape HTML::Entities
  parallel_installdeps_notest YAML LWP Class::Trigger JSON::XS DateTime::Format::Builder Class::Accessor::Grouped Package::Variant
  parallel_installdeps_notest SQL::Abstract Moose Module::Install JSON SQL::Translator File::Which

  # the official version is very much outdated and does not compile on 5.14+
  # use this rather updated source tree (needs to go to PAUSE):
  # https://github.com/pilcrow/perl-dbd-interbase
  if [[ -n "$DBICTEST_FIREBIRD_INTERBASE_DSN" ]] ; then
    parallel_installdeps_notest git://github.com/dbsrgits/perl-dbd-interbase.git
  fi

fi

# generate the makefile which will have different deps depending on
# the runmode and envvars set above
run_or_err "Configure on current branch" "perl Makefile.PL"

# install (remaining) dependencies, sometimes with a gentle push
if [[ "$CLEANTEST" = "true" ]]; then

  # we are doing a devrel pass - try to upgrade *everything* (we will be using cpanm so safe-ish)
  if [[ "$DEVREL_DEPS" == "true" ]] ; then

    HARD_DEPS="$(echo $(make listalldeps))"

  else

    HARD_DEPS="$(echo $(make listdeps))"

##### TEMPORARY WORKAROUNDS needed in case we will be using a fucked CPAN.pm
    if ! CPAN_is_sane ; then

      # DBD::SQLite reasonably wants DBI at config time
      perl -MDBI -e1 &>/dev/null || HARD_DEPS="DBI $HARD_DEPS"

      # this is a fucked CPAN - won't understand configure_requires of
      # various pieces we may run into
      # FIXME - need to get these off metacpan or something instead
      HARD_DEPS="ExtUtils::Depends B::Hooks::OP::Check $HARD_DEPS"

      # FIXME
      # parent is temporary due to Carp https://rt.cpan.org/Ticket/Display.html?id=88494
      HARD_DEPS="parent $HARD_DEPS"

      if CPAN_supports_BUILDPL ; then
        # We will invoke a posibly MBT based BUILD-file, but we do not support
        # configure requires. So we not only need to install MBT but its prereqs
        # FIXME This is madness
        HARD_DEPS="$(extract_prereqs Module::Build::Tiny) Module::Build::Tiny $HARD_DEPS"
      else
        # FIXME
        # work around Params::Validate not having a Makefile.PL so really old
        # toolchains can not figure out what the prereqs are ;(
        # Need to do more research before filing a bug requesting Makefile inclusion
        HARD_DEPS="$(extract_prereqs Params::Validate) $HARD_DEPS"
      fi

    fi

##### END TEMPORARY WORKAROUNDS
  fi

  installdeps $HARD_DEPS

else

  parallel_installdeps_notest "$(make listdeps)"

fi

echo_err "$(tstamp) Dependency installation finished"
# this will display list of available versions
perl Makefile.PL

# make sure we got everything we need
if [[ -n "$(make listdeps)" ]] ; then
  echo_err "$(tstamp) Not all deps installed - something went wrong :("
  sleep 1 # without this the echo below confuses the console listener >.<
  CPAN_is_sane || echo_err -e "Outdated CPAN.pm used - full installdep log follows\n$INSTALLDEPS_OUT\n\nSearch for 'NOT OK' in the text above\n\nDeps still missing:"
  sleep 3 # without this the above echo confuses the console listener >.<
  make listdeps
  exit 1
fi

# check that our MDV somewhat works
if [[ "$POISON_ENV" = "true" ]] && ( perl -MDBD::SQLite\ 1.38 -e1 || perl -MDBI\ 1.615 -e1 ) &>/dev/null ; then
  echo_err "Something went wrong - higher versions of DBI and/or DBD::SQLite than we expected"
  exit 1
fi


# announce what are we running
echo_err "
===================== DEPENDENCY CONFIGURATION COMPLETE =====================
$(tstamp) Configuration phase seems to have taken $(date -ud "@$SECONDS" '+%H:%M:%S') (@$SECONDS)

$(ci_vm_state_text)"
