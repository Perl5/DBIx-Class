#!/bin/bash

# this file is executed in a subshell - set up the common stuff
source maint/travis-ci_scripts/common.bash

if [[ -n "$SHORT_CIRCUIT_SMOKE" ]] ; then exit 0 ; fi

# The DEVREL_DEPS prereq-install stage won't mix with MVDT
# DEVREL wins
if [[ "$DEVREL_DEPS" == "true" ]] ; then
  export MVDT=""
fi


# announce what are we running
echo_err "$(ci_vm_state_text)"


# FIXME - this is a kludge in place of proper MVDT testing. For the time
# being simply use the minimum versions of our DBI/DBDstack, to avoid
# fuckups like 0.08260 (went unnoticed for 5 months)
if [[ "$MVDT" == "true" ]] ; then

  # use url-spec for DBI due to https://github.com/miyagawa/cpanminus/issues/328
  if [[ "$CLEANTEST" != "true" ]] || perl -M5.013003 -e1 &>/dev/null ; then
    # the fulltest may re-upgrade DBI, be conservative only on cleantests
    # earlier DBI will not compile without PERL_POLLUTE which was gone in 5.14
    parallel_installdeps_notest T/TI/TIMB/DBI-1.614.tar.gz

    # FIXME work around DBD::DB2 being silly: https://rt.cpan.org/Ticket/Display.html?id=101659
    if [[ -n "$DBICTEST_DB2_DSN" ]] ; then
      echo_err "Installing same DBI version into the main perl (above the current local::lib)"
      $SHELL -lic "perlbrew use $( perlbrew use | grep -oP '(?<=Currently using )[^@]+' ) && parallel_installdeps_notest T/TI/TIMB/DBI-1.614.tar.gz"
    fi
  else
    parallel_installdeps_notest T/TI/TIMB/DBI-1.57.tar.gz

    # FIXME work around DBD::DB2 being silly: https://rt.cpan.org/Ticket/Display.html?id=101659
    if [[ -n "$DBICTEST_DB2_DSN" ]] ; then
      echo_err "Installing same DBI version into the main perl (above the current local::lib)"
      $SHELL -lic "perlbrew use $( perlbrew use | grep -oP '(?<=Currently using )[^@]+' ) && parallel_installdeps_notest T/TI/TIMB/DBI-1.57.tar.gz"
    fi
  fi

  # Test both minimum DBD::SQLite and minimum BigInt SQLite
  # reverse the logic from above for this (low on full, higher on clean)
  if [[ "$CLEANTEST" = "true" ]]; then
    parallel_installdeps_notest DBD::SQLite@1.37
  else
    parallel_installdeps_notest DBD::SQLite@1.29
  fi
fi

#
# try minimal fully tested installs *without* a compiler (with some exceptions of course)
if [[ "$BREAK_CC" == "true" ]] ; then

  [[ "$CLEANTEST" != "true" ]] && echo_err "Breaking the compiler without CLEANTEST makes no sense" && exit 1

  # FIXME - work around https://github.com/perl5-dbi/dbi/pull/60
  # and https://www.nntp.perl.org/group/perl.perl5.porters/2018/01/msg249123.html
  perl -MDBI -e1 &>/dev/null || perl -MStorable\ 2.16 -e1 &>/dev/null || parallel_installdeps_notest Storable

  # FIXME - working around RT#74707, https://metacpan.org/source/DOY/Package-Stash-0.37/Makefile.PL#L112-122
  #
  # DEVREL_DEPS means our installer is cpanm, which will respect failures
  # and the like, so stuff soft-failing (failed deps that are not in fact
  # needed) will not fly. Add *EVEN MORE* stuff that needs a compiler
  #
  # FIXME - the PathTools 3.47 is to work around https://rt.cpan.org/Ticket/Display.html?id=107392
  #
  installdeps Sub::Name Clone Package::Stash::XS \
              $( perl -MFile::Spec\ 3.26 -e1 &>/dev/null || echo "File::Path File::Spec" ) \
              $( perl -MList::Util\ 1.16 -e1 &>/dev/null || echo "List::Util" ) \
              $( [[ "$DEVREL_DEPS" == "true" ]] && ( perl -MFile::Spec\ 3.13 -e1 &>/dev/null || echo "S/SM/SMUELLER/PathTools-3.47.tar.gz" ) ) \
              $( perl -MDBI -e1 &>/dev/null || echo "DBI" ) \
              $( perl -MDBD::SQLite -e1 &>/dev/null || echo "DBD::SQLite" )

  mkdir -p "$HOME/bin" # this is already in $PATH, just doesn't exist
  run_or_err "Linking ~/bin/cc to /bin/false - thus essentially BREAKING the C compiler" \
             "ln -s /bin/false $HOME/bin/cc"

  # FIXME: working around RT#113682, and some other unfiled bugs
  installdeps Module::Build Devel::GlobalDestruction Class::Accessor::Grouped

  run_or_err "Linking ~/bin/cc to /bin/true - BREAKING the C compiler even harder" \
             "ln -fs /bin/true $HOME/bin/cc"
fi

if [[ "$CLEANTEST" = "true" ]]; then
  # get the last inc/ off cpan - we will get rid of MI
  # soon enough, but till then this will do
  # the point is to have a *really* clean perl (the ones
  # we build are guaranteed to be clean, without side
  # effects from travis preinstalls)
  #
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

  if [[ "$DEVREL_DEPS" = "true" ]] ; then
    # nothing for now
    /bin/true
  elif ! CPAN_is_sane ; then
    # no configure_requires - we will need the usual suspects anyway
    # without pre-installing these in one pass things won't yet work
    installdeps Module::Build
  fi

else
  # we will be running all dbic tests - preinstall lots of stuff, run basic tests

  # do the preinstall in several passes to minimize amount of cross-deps installing
  # multiple times, and to avoid module re-architecture breaking another install
  # (e.g. once Carp is upgraded there's no more Carp::Heavy)

  # (or once ExtUtil::MakeMaker is upgraded the lazy loads can't find base method
  #  added in https://github.com/Perl-Toolchain-Gang/ExtUtils-MakeMaker/commit/cde9367d1 )
  # FIXME - we shouldn't be upgrading this but alas... Test::Requires :/
  perl -MExtUtils::MakeMaker\ 6.64 -e1 &>/dev/null || parallel_installdeps_notest ExtUtils::MakeMaker

  parallel_installdeps_notest Carp
  parallel_installdeps_notest Module::Build
  parallel_installdeps_notest Test::Exception Encode::Locale Test::Fatal Module::Runtime
  parallel_installdeps_notest Test::Warn B::Hooks::EndOfScope Test::Differences HTTP::Status
  parallel_installdeps_notest Test::Pod::Coverage Test::EOL Devel::GlobalDestruction Sub::Name MRO::Compat Class::XSAccessor URI::Escape HTML::Entities
  parallel_installdeps_notest YAML LWP Class::Trigger Class::Accessor::Grouped Package::Variant
  parallel_installdeps_notest SQL::Abstract Moose Module::Install@1.15 JSON SQL::Translator File::Which Class::DBI::Plugin git://github.com/ribasushi/patchup-Perl5-PPerl.git

  # FIXME - temp workaround for RT#117959
  if ! perl -M5.008004 -e1 &>/dev/null ; then
    parallel_installdeps_notest DateTime::Locale@1.06
    parallel_installdeps_notest DateTime::TimeZone@2.02
    parallel_installdeps_notest DateTime@1.38
    parallel_installdeps_notest DateTime::Format::Strptime@1.71
  fi

  # the official version is very much outdated and does not compile on 5.14+
  # use this rather updated source tree (needs to go to PAUSE):
  # https://github.com/pilcrow/perl-dbd-interbase
  if [[ -n "$DBICTEST_FIREBIRD_INTERBASE_DSN" ]] ; then
    parallel_installdeps_notest git://github.com/ribasushi/patchup-Perl5-DBD-InterBase.git
  fi

  # SCGI does not install under < 5.8.8 perls nor under parallel make
  # FIXME: The 5.8.8 thing is likely fixable, something to do with
  # #define speedy_new(s,n,t) Newx(s,n,t)
  if perl -M5.008008 -e 1 &>/dev/null ; then
    MAKEFLAGS="" bash -c "parallel_installdeps_notest git://github.com/ribasushi/patchup-Perl5-CGI-SpeedyCGI.git"
  fi
fi


# install (remaining) dependencies, sometimes with a gentle push
if [[ "$CLEANTEST" = "true" ]]; then

  # FIXME - work around https://github.com/perl5-dbi/dbi/pull/60
  # and https://www.nntp.perl.org/group/perl.perl5.porters/2018/01/msg249123.html
  perl -MDBI -e1 &>/dev/null || perl -MStorable\ 2.16 -e1 &>/dev/null || parallel_installdeps_notest Storable

  # FIXME - test latest DBD::SQLite in all *unspecified* cases, and also work around unavailability
  # of test fix on CPAN: https://github.com/DBD-SQLite/DBD-SQLite/commit/7b949c35a

    # need to get a DBI in case we don't have it
    ! CPAN_is_sane && ! perl -MDBI -e1 &>/dev/null && installdeps DBI

    # if we installed something already - roll with it
    perl -MDBD::SQLite -e1 &>/dev/null || installdeps I/IS/ISHIGAKI/DBD-SQLite-1.55_07.tar.gz
  # END SQLite FIXME

  run_or_err "Configure on current branch" "perl Makefile.PL"

  # we are doing a devrel pass - try to upgrade *everything* (we will be using cpanm so safe-ish)
  if [[ "$DEVREL_DEPS" == "true" ]] ; then

    HARD_DEPS="$(make listalldeps | sort -R)"

  else

    HARD_DEPS="$(make listdeps | sort -R)"

##### TEMPORARY WORKAROUNDS needed in case we will be using a fucked CPAN.pm
    if ! CPAN_is_sane ; then

      # DBD::SQLite reasonably wants DBI at config time
      perl -MDBI -e1 &>/dev/null || HARD_DEPS="DBI $HARD_DEPS"

      # Hash::Merge caught up to my prediction made in 2014
      # install its "deps" manually for the time being,
      # likely won't have a chance any time soon to remove H::M
      # from the larger depchain
      HARD_DEPS="Clone::Choose $HARD_DEPS"

    fi

##### END TEMPORARY WORKAROUNDS
  fi

  installdeps $HARD_DEPS

  run_or_err "Re-configure" "perl Makefile.PL"

else

  run_or_err "Configure on current branch with --with-optdeps" "perl Makefile.PL --with-optdeps"

  # FIXME - evil evil work around for https://github.com/Manwar/Test-Strict/issues/17
  if perl -M5.025 -e1 &>/dev/null; then
    mkdir -p "$( perl -MConfig -e 'print $Config{sitelib}' )/Devel"
    cat <<MyDevelCover > "$( perl -MConfig -e 'print $Config{sitelib}' )/Devel/Cover.pm"
package Devel::Cover;
our \$VERSION = 0.43;
1;
MyDevelCover
  fi

  # if we are smoking devrels - make sure we upgrade everything we know about
  if [[ "$DEVREL_DEPS" == "true" ]] ; then
    parallel_installdeps_notest "$(make listalldeps | sort -R)"
  else
    parallel_installdeps_notest "$(make listdeps | sort -R)"
  fi

  run_or_err "Re-configure with --with-optdeps" "perl Makefile.PL --with-optdeps"
fi

echo_err "$(tstamp) Dependency installation finished"

# make sure we got everything we need
if [[ -n "$(make listdeps)" ]] ; then
  echo_err "$(tstamp) Not all deps installed - something went wrong :("
  sleep 1 # without this the echo below confuses the console listener >.<
  CPAN_is_sane || echo_err -e "Outdated CPAN.pm used - full installdep log follows\n$INSTALLDEPS_OUT\n\nSearch for 'NOT OK' in the text above\n\nDeps still missing:"
  sleep 3 # without this the above echo confuses the console listener >.<
  make listdeps
  exit 1
fi

# check that our MVDT somewhat works
if [[ "$MVDT" == "true" ]] && ( perl -MDBD::SQLite\ 1.38 -e1 || perl -MDBI\ 1.615 -e1 ) &>/dev/null ; then
  echo_err "Something went wrong - higher versions of DBI and/or DBD::SQLite than we expected"
  exit 1
fi

echo_err "
===================== DEPENDENCY CONFIGURATION COMPLETE =====================
$(tstamp) Configuration phase seems to have taken $(date -ud "@$SECONDS" '+%H:%M:%S') (@$SECONDS)"
