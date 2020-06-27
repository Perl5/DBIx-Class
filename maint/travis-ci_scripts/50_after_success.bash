#!/bin/bash

# this file is executed in a subshell - set up the common stuff
source maint/travis-ci_scripts/common.bash

if [[ -n "$SHORT_CIRCUIT_SMOKE" ]] || [[ "$TRAVIS_PULL_REQUEST" != "false" ]] || ASan_enabled; then
  exit 0
fi

# this part needs to run in parallel unconditionally
export VCPU_USE="$VCPU_AVAILABLE"
export HARNESS_OPTIONS="j$VCPU_USE"

[[ "$BREAK_CC" == "true" ]] && run_or_err "Unbreaking previously broken ~/bin/cc" "rm $HOME/bin/cc"

# FIXME sadly some stuff needs to be pinned for the wider deplist until CPAN can be fixed
perl -MList::Util\ 1.45 -e1 &>/dev/null || installdeps P/PE/PEVANS/Scalar-List-Utils-1.50.tar.gz
perl -MModule::Install\ 1.15 -e1 &>/dev/null || parallel_installdeps_notest E/ET/ETHER/Module-Install-1.15.tar.gz

if [[ "$DEVREL_DEPS" == "true" ]] && perl -M5.008003 -e1 &>/dev/null ; then

  # FIXME - workaround for YAML/RT#81120 and L::SRH/RT#107681
  # We don't actually need these modules, only there because of SQLT (which will be fixed)
  perl -M5.008008 -e1 &>/dev/null || parallel_installdeps_notest YAML
  perl -M5.008009 -e1 &>/dev/null || parallel_installdeps_notest Lexical::SealRequireHints

  # FIXME Change when Moose goes away
  installdeps \
    Moose \
    $(perl -Ilib -MDBIx::Class -e '
      print join " ", map
        { keys %{DBIx::Class::Optional::Dependencies->req_list_for($_) } }
        qw(
          dist_dir
          deploy
          test_pod
          test_podcoverage
          test_whitespace
          test_strictures
        )
    ')

  run_or_err "Attempt to build a dist" "rm -rf inc/ && perl Makefile.PL --skip-author-deps && make dist"
  tarball_assembled=1

elif [[ "$CLEANTEST" != "true" ]] ; then

  # FIXME - have to do this step separately:
  # once ExtUtil::MakeMaker is upgraded the lazy loads can't find base method
  # added in https://github.com/Perl-Toolchain-Gang/ExtUtils-MakeMaker/commit/cde9367d1
  parallel_installdeps_notest ExtUtils::MakeMaker

  parallel_installdeps_notest \
    $(perl -Ilib -MDBIx::Class -e '
      print join " ", map
        { keys %{DBIx::Class::Optional::Dependencies->req_list_for($_) } }
        qw(
          dist_dir
          deploy
          test_pod
          test_podcoverage
          test_whitespace
          test_strictures
        )
    ')

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


  # make sure we are retrying with newest CPAN possible (YAML breakage, etc)
  installdeps CPAN
  run_or_err "Make sure CPAN was upgraded to at least 2.28" "perl -M'CPAN 2.028' -e1"

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
