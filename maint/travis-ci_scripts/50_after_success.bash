#!/bin/bash

# this file is executed in a subshell - set up the common stuff
source maint/travis-ci_scripts/common.bash

if [[ -n "$SHORT_CIRCUIT_SMOKE" ]] || [[ "$TRAVIS_PULL_REQUEST" != "false" ]] ; then exit 0 ; fi

# this part needs to run in parallel unconditionally
export VCPU_USE="$VCPU_AVAILABLE"
export HARNESS_OPTIONS="j$VCPU_USE"


if [[ "$DEVREL_DEPS" == "true" ]] && perl -M5.008003 -e1 &>/dev/null ; then

  [[ "$BREAK_CC" == "true" ]] && run_or_err "Unbreaking previously broken ~/bin/cc" "rm $HOME/bin/cc"

  # FIXME - Devel::Cover (brought by Test::Strict, but soon needed anyway)
  # does not test cleanly on 5.8.7 - just get it directly
  if perl -M5.008007 -e1 &>/dev/null && ! perl -M5.008008 -e1 &>/dev/null; then
    parallel_installdeps_notest Devel::Cover
  fi

  # FIXME - workaround for YAML/RT#81120 and L::SRH/RT#107681
  # We don't actually need these modules, only there because of SQLT (which will be fixed)
  # does not test cleanly on 5.8.7 - just get them directly
  if ! perl -M5.008008 -e1 &>/dev/null; then
    parallel_installdeps_notest YAML Lexical::SealRequireHints
  fi

  # FIXME - workaround for RT#113740
  parallel_installdeps_notest List::AllUtils

  # FIXME Change when Moose goes away
  installdeps Moose $(perl -Ilib -MDBIx::Class::Optional::Dependencies=-list_missing,dist_dir)

  run_or_err "Attempt to build a dist" "rm -rf inc/ && perl Makefile.PL && make dist"
  tarball_assembled=1

elif [[ "$CLEANTEST" != "true" ]] ; then
  parallel_installdeps_notest $(perl -Ilib -MDBIx::Class::Optional::Dependencies=-list_missing,dist_dir)

  run_or_err "Attempt to build a dist from original checkout" "make dist"
  tarball_assembled=1
fi


if [[ -n "$tarball_assembled" ]] ; then

  echo "Contents of the resulting dist tarball:"
  echo "==========================================="
  tar -vzxf DBIx-Class-*.tar.gz
  echo "==========================================="

  # kill as much as possible with fire
  purge_sitelib


  # undo some of the pollution (if any) affecting the plain install deps
  # FIXME - this will go away once we move off Moose, and a new SQLT
  # with much less recommends ships
  export DBICTEST_SQLT_DEPLOY=""
  export DBICTEST_VIA_REPLICATED=""


  # make sure we are retrying with newest CPAN possible
  #
  # not running tests on CPAN.pm - they are not terribly slow,
  # but https://rt.cpan.org/Ticket/Display.html?id=96437 sucks
  parallel_installdeps_notest CPAN
  run_or_err "Make sure CPAN was upgraded to at least 2.10" "perl -M'CPAN 2.010' -e1"

  run_or_err "Re-Configuring CPAN.pm" "perl -MCPAN -e '\
    CPAN::Config->load;

    # For the time being smoking with this setting is not realistic
    # https://rt.cpan.org/Ticket/Display.html?id=103280
    # https://rt.cpan.org/Ticket/Display.html?id=37641
    # https://rt.cpan.org/Ticket/Display.html?id=77708
    # https://rt.cpan.org/Ticket/Display.html?id=87474
    #\$CPAN::Config->{build_requires_install_policy} = q{no};

    \$CPAN::Config->{recommends_policy} = q{yes};
    CPAN::Config->commit;
  '"

  cd "$(find DBIx-Class-* -maxdepth 0 -type d | head -n 1)"

  # only run a full test cycle on devrel_deps, as they are all marked
  # as "allow fails" in the travis matrix
  if [[ "$DEVREL_DEPS" == "true" ]] ; then

    for e in $( env | grep 'DBICTEST.*DSN' | cut -f 1 -d '=' ) ; do
      echo "Unsetting $e"
      export $e=""
    done

    # FIXME - for some reason a plain `cpan .` does not work in this case
    # no time to investigate
    run_or_err \
      "Attempt to configure/test/build/install dist using latest CPAN@$(perl -MCPAN -e 'print CPAN->VERSION')" \
      "perl -MCPAN -e 'install( q{.} )'"

  else
    run_or_err \
      "Attempt to configure/build/install dist using latest CPAN@$(perl -MCPAN -e 'print CPAN->VERSION')" \
      "perl -MCPAN -e 'notest( install => q{.} )'"
  fi
fi
