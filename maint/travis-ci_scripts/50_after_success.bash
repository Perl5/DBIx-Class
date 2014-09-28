#!/bin/bash

if [[ -n "$SHORT_CIRCUIT_SMOKE" ]] ; then return ; fi

if [[ "$CLEANTEST" != "true" ]] ; then
  parallel_installdeps_notest $(perl -Ilib -MDBIx::Class -e 'print join " ", keys %{DBIx::Class::Optional::Dependencies->req_list_for("dist_dir")}')
  run_or_err "Attempt to build a dist with all prereqs present" "make dist"
  echo "Contents of the resulting dist tarball:"
  echo "==========================================="
  tar -vzxf DBIx-Class-*.tar.gz
  echo "==========================================="
  run_or_err 'Attempt to configure from re-extracted distdir' \
    'bash -c "cd \$(find DBIx-Class-* -maxdepth 0 -type d | head -n 1) && perl Makefile.PL"'
fi
